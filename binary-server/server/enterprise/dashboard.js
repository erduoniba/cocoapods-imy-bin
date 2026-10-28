'use strict'

const Router = require('@koa/router')
const mongoose = require('mongoose')
const Component = require('../models/component')
const Release = require('../models/release')
const BuildJob = require('../models/build_job')
const Project = require('../models/project')
const ProjectPolicyRevision = require('../models/project_policy')
const AuditEvent = require('../models/audit_event')
const { verifyLicenseKey, generateLicenseKey } = require('./license')
const { issueSsoSessionToken, verifySsoSessionToken, hasPermission } = require('./rbac')
const { TelemetryAndQualityService } = require('./telemetry')
const { getBearerToken, tokensMatch } = require('../middleware/auth')
const configTableService = require('./config_table_service')

const MAX_JSON_BYTES = 1024 * 1024

async function parseJsonBody(ctx) {
  const chunks = []
  let length = 0
  for await (const chunk of ctx.req) {
    length += chunk.length
    if (length > MAX_JSON_BYTES) {
      ctx.throw(413, 'JSON body exceeds 1 MiB')
    }
    chunks.push(chunk)
  }
  if (chunks.length === 0) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    ctx.throw(400, 'Malformed JSON body')
  }
}

function computePolicyDiff(fromTargets = [], toTargets = []) {
  const fromMap = new Map()
  for (const t of fromTargets) {
    for (const dep of t.dependencies || []) {
      fromMap.set(`${t.name}:${dep.name}`, dep)
    }
  }
  const toMap = new Map()
  for (const t of toTargets) {
    for (const dep of t.dependencies || []) {
      toMap.set(`${t.name}:${dep.name}`, dep)
    }
  }

  const changes = []
  const allKeys = new Set([...fromMap.keys(), ...toMap.keys()])
  for (const key of Array.from(allKeys).sort()) {
    const [target, name] = key.split(':')
    const before = fromMap.get(key)
    const after = toMap.get(key)
    if (!before && after) {
      changes.push({ target, name, change: 'added', after })
    } else if (before && !after) {
      changes.push({ target, name, change: 'removed', before })
    } else if (before.version !== after.version || before.mode !== after.mode) {
      changes.push({ target, name, change: 'modified', before, after })
    }
  }
  return changes
}

function createEnterpriseRouter({ config }) {
  const router = new Router()
  const telemetryService = new TelemetryAndQualityService()
  let activeLicenseKey = process.env.IMYBIN_LICENSE_KEY || generateLicenseKey({ org: 'ImyBin Open-Core Community', tier: 'enterprise', seats: 100 })

  function requireEnterpriseAuth(permission) {
    return async (ctx, next) => {
      const bearer = getBearerToken(ctx.get('authorization'))
      if (bearer) {
        const ssoPayload = verifySsoSessionToken(bearer)
        if (ssoPayload) {
          if (permission && !hasPermission(ssoPayload.role, permission)) {
            ctx.throw(403, `Role '${ssoPayload.role}' lacks permission '${permission}'`, { code: 'FORBIDDEN' })
          }
          ctx.state.actor = ssoPayload.sub
          ctx.state.role = ssoPayload.role
          await next()
          return
        }
        if (
          (config.platformToken && tokensMatch(bearer, config.platformToken)) ||
          (config.apiToken && tokensMatch(bearer, config.apiToken))
        ) {
          ctx.state.actor = 'platform-operator'
          ctx.state.role = 'admin'
          await next()
          return
        }
      }
      if (config.nodeEnv !== 'production' && !config.platformEnabled) {
        ctx.state.actor = 'dev-operator'
        ctx.state.role = 'admin'
        await next()
        return
      }
      ctx.throw(401, 'A valid SSO or platform token is required', { code: 'UNAUTHORIZED' })
    }
  }

  // --- Enterprise SSO, License & Telemetry Routes ---
  router.post('/api/v1/enterprise/sso/exchange', async (ctx) => {
    const body = await parseJsonBody(ctx)
    try {
      const session = issueSsoSessionToken({
        email: body.email,
        role: body.role || 'developer',
        provider: body.provider || 'oidc',
      })
      ctx.status = 200
      ctx.body = session
    } catch (error) {
      ctx.throw(400, error.message)
    }
  })

  router.post('/api/v1/enterprise/license/verify', async (ctx) => {
    const body = await parseJsonBody(ctx)
    const keyToVerify = body.licenseKey || activeLicenseKey
    const result = verifyLicenseKey(keyToVerify)
    if (body.licenseKey && result.valid) {
      activeLicenseKey = body.licenseKey
    }
    ctx.body = result
  })

  router.post('/api/v1/enterprise/telemetry/install', requireEnterpriseAuth('telemetry:write'), async (ctx) => {
    const body = await parseJsonBody(ctx)
    const recorded = telemetryService.recordInstallEvent(body)
    ctx.status = 201
    ctx.body = recorded
  })

  router.get('/api/v1/enterprise/telemetry/roi', requireEnterpriseAuth('telemetry:read'), async (ctx) => {
    ctx.body = telemetryService.getRoiSummary()
  })

  router.post('/api/v1/enterprise/quality-gates/evaluate', requireEnterpriseAuth('quality:check'), async (ctx) => {
    const body = await parseJsonBody(ctx)
    const report = telemetryService.evaluateArtifactQualityGate(body)
    ctx.status = report.passed ? 200 : 422
    ctx.body = report
  })

  router.get('/api/v1/enterprise/policies/:project/diff', requireEnterpriseAuth('policy:read'), async (ctx) => {
    const { project } = ctx.params
    const { fromRevision, toRevision } = ctx.query
    if (!fromRevision || !toRevision) {
      ctx.throw(400, 'fromRevision and toRevision query parameters are required')
    }
    const [fromDoc, toDoc] = await Promise.all([
      ProjectPolicyRevision.findOne({ project, revision: fromRevision }).lean().exec(),
      ProjectPolicyRevision.findOne({ project, revision: toRevision }).lean().exec(),
    ])
    if (!fromDoc || !toDoc) {
      ctx.throw(404, 'One or both policy revisions were not found')
    }
    ctx.body = {
      project,
      fromRevision,
      toRevision,
      changes: computePolicyDiff(fromDoc.targets, toDoc.targets),
    }
  })

  router.get('/api/v1/enterprise/overview', async (ctx) => {
    const isConnected = mongoose.connection.readyState === 1
    const [components, releases, jobs, projects, audits] = isConnected
      ? await Promise.all([
          Component.find({}).sort({ updatedAt: -1 }).limit(50).lean().exec(),
          Release.find({}).sort({ updatedAt: -1 }).limit(30).lean().exec(),
          BuildJob.find({}).sort({ updatedAt: -1 }).limit(20).lean().exec(),
          Project.find({}).lean().exec(),
          AuditEvent.find({}).sort({ createdAt: -1 }).limit(30).lean().exec(),
        ])
      : [[], [], [], [], []]

    ctx.body = {
      license: verifyLicenseKey(activeLicenseKey),
      roi: telemetryService.getRoiSummary(),
      qualityReports: telemetryService.qualityReports.slice(-10).reverse(),
      components,
      releases,
      jobs,
      projects,
      audits,
    }
  })

  // --- Configuration Tables (配置表) REST APIs ---
  router.get('/api/v1/config-tables', async (ctx) => {
    ctx.body = await configTableService.listConfigTables()
  })

  router.get('/api/v1/config-tables/:project', async (ctx) => {
    const table = await configTableService.getConfigTable(ctx.params.project)
    if (!table) ctx.throw(404, `Config table '${ctx.params.project}' not found`)
    ctx.body = table
  })

  router.get('/api/v1/config-tables/:project/export', async (ctx) => {
    const table = await configTableService.getConfigTable(ctx.params.project)
    if (!table) ctx.throw(404, `Config table '${ctx.params.project}' not found`)
    ctx.set('Content-Disposition', `attachment; filename="${ctx.params.project}.imy-bin-config.json"`)
    ctx.type = 'application/json; charset=utf-8'
    ctx.body = JSON.stringify(table, null, 2)
  })

  router.post('/api/v1/config-tables', async (ctx) => {
    const body = await parseJsonBody(ctx)
    try {
      const created = await configTableService.createConfigTable(body, ctx.state.actor || 'admin')
      ctx.status = 201
      ctx.body = created
    } catch (err) {
      ctx.throw(err.status || 400, err.message)
    }
  })

  router.put('/api/v1/config-tables/:project', async (ctx) => {
    const body = await parseJsonBody(ctx)
    try {
      const updated = await configTableService.updateConfigTable(ctx.params.project, body, ctx.state.actor || 'admin')
      ctx.body = updated
    } catch (err) {
      ctx.throw(err.status || 400, err.message)
    }
  })

  router.post('/api/v1/config-tables/:project/sync', async (ctx) => {
    const body = await parseJsonBody(ctx)
    try {
      const synced = await configTableService.syncConfigTableDelta(ctx.params.project, body, ctx.state.actor || 'local-sync')
      ctx.body = synced
    } catch (err) {
      ctx.throw(err.status || 400, err.message)
    }
  })

  router.post('/api/v1/config-tables/:project/duplicate', async (ctx) => {
    const body = await parseJsonBody(ctx)
    try {
      const result = await configTableService.duplicateConfigTable(ctx.params.project, body, ctx.state.actor || 'admin')
      ctx.status = 201
      ctx.body = result
    } catch (err) {
      ctx.throw(err.status || 400, err.message)
    }
  })

  router.delete('/api/v1/config-tables/:project', async (ctx) => {
    try {
      const result = await configTableService.deleteConfigTable(ctx.params.project, ctx.state.actor || 'admin')
      ctx.body = result
    } catch (err) {
      ctx.throw(err.status || 400, err.message)
    }
  })

  // --- Web Admin Dashboard Route ---
  router.get(['/', '/dashboard', '/admin/config-tables'], async (ctx) => {
    ctx.type = 'text/html; charset=utf-8'
    ctx.body = renderDashboardHtml()
  })

  return router
}

function renderDashboardHtml() {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>ImyBin Enterprise Control Plane — 配置表管理后台与大盘</title>
  <style>
    :root {
      --bg: #0b1120;
      --card: #1e293b;
      --card-hover: #263349;
      --border: #334155;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --accent: #38bdf8;
      --accent-hover: #0284c7;
      --green: #10b981;
      --green-bg: rgba(16, 185, 129, 0.15);
      --amber: #f59e0b;
      --amber-bg: rgba(245, 158, 11, 0.15);
      --purple: #a855f7;
      --purple-bg: rgba(168, 85, 247, 0.15);
      --blue: #3b82f6;
      --blue-bg: rgba(59, 130, 246, 0.15);
      --red: #ef4444;
      --red-bg: rgba(239, 68, 68, 0.15);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
      background: var(--bg);
      color: var(--text);
      padding: 0 0 60px 0;
    }
    header {
      background: #0f172a;
      border-bottom: 1px solid var(--border);
      padding: 16px 32px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      position: sticky;
      top: 0;
      z-index: 50;
    }
    .header-left {
      display: flex;
      align-items: center;
      gap: 16px;
    }
    .brand-logo {
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.5px;
      background: linear-gradient(135deg, #38bdf8 0%, #818cf8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .nav-tabs {
      display: flex;
      gap: 8px;
      margin-left: 24px;
    }
    .nav-tab {
      padding: 8px 16px;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      border: 1px solid transparent;
      color: var(--text-muted);
      transition: all 0.15s ease;
      background: transparent;
    }
    .nav-tab:hover {
      color: var(--text);
      background: rgba(255, 255, 255, 0.05);
    }
    .nav-tab.active {
      color: #fff;
      background: var(--card);
      border-color: var(--border);
    }
    .badge {
      background: rgba(56, 189, 248, 0.15);
      color: var(--accent);
      padding: 4px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 600;
    }
    .main-container {
      max-width: 1400px;
      margin: 24px auto;
      padding: 0 24px;
    }
    .tab-content {
      display: none;
    }
    .tab-content.active {
      display: block;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 20px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      border: 1px solid var(--border);
      background: #334155;
      color: var(--text);
      transition: all 0.15s ease;
      text-decoration: none;
    }
    .btn:hover {
      background: #475569;
      border-color: #64748b;
    }
    .btn-primary {
      background: #0284c7;
      border-color: #0369a1;
      color: #fff;
    }
    .btn-primary:hover {
      background: #0369a1;
    }
    .btn-success {
      background: #059669;
      border-color: #047857;
      color: #fff;
    }
    .btn-success:hover {
      background: #047857;
    }
    .btn-danger {
      background: rgba(239, 68, 68, 0.2);
      border-color: rgba(239, 68, 68, 0.4);
      color: #fca5a5;
    }
    .btn-danger:hover {
      background: rgba(239, 68, 68, 0.4);
    }
    .btn-sm {
      padding: 4px 10px;
      font-size: 12px;
    }
    .toolbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
      margin-bottom: 20px;
    }
    .toolbar-left, .toolbar-right {
      display: flex;
      align-items: center;
      gap: 10px;
      flex-wrap: wrap;
    }
    .form-control {
      background: #0f172a;
      border: 1px solid var(--border);
      color: var(--text);
      padding: 8px 12px;
      border-radius: 8px;
      font-size: 13px;
      outline: none;
    }
    .form-control:focus {
      border-color: var(--accent);
    }
    select.form-control {
      cursor: pointer;
    }
    /* App Version Column Bar */
    .column-bar {
      display: flex;
      align-items: center;
      gap: 8px;
      overflow-x: auto;
      padding: 6px 0 16px 0;
      border-bottom: 1px solid var(--border);
      margin-bottom: 20px;
    }
    .column-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 16px;
      border-radius: 20px;
      background: #0f172a;
      border: 1px solid var(--border);
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      color: var(--text-muted);
      transition: all 0.15s ease;
      white-space: nowrap;
    }
    .column-pill:hover {
      border-color: #64748b;
      color: var(--text);
    }
    .column-pill.viewing {
      background: rgba(56, 189, 248, 0.12);
      border-color: var(--accent);
      color: #fff;
    }
    .column-pill .active-star {
      background: #f59e0b;
      color: #000;
      font-size: 10px;
      padding: 2px 6px;
      border-radius: 10px;
      font-weight: 700;
    }
    /* Mode Badges */
    .mode-badge {
      display: inline-flex;
      align-items: center;
      padding: 3px 8px;
      border-radius: 6px;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .mode-binary { background: var(--green-bg); color: var(--green); }
    .mode-source { background: var(--blue-bg); color: #60a5fa; }
    .mode-local { background: var(--amber-bg); color: var(--amber); }
    .mode-branch { background: var(--purple-bg); color: var(--purple); }
    /* Tables */
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      text-align: left;
      padding: 12px 10px;
      border-bottom: 1px solid var(--border);
    }
    th {
      color: var(--text-muted);
      font-weight: 600;
      background: rgba(15, 23, 42, 0.6);
    }
    tr:hover td {
      background: rgba(255, 255, 255, 0.02);
    }
    .table-input {
      background: #0f172a;
      border: 1px solid var(--border);
      color: var(--text);
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 12px;
      width: 100%;
    }
    .table-input:focus {
      border-color: var(--accent);
    }
    /* Overview grid */
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }
    .metric {
      font-size: 28px;
      font-weight: 700;
      margin-top: 8px;
      color: var(--accent);
    }
    /* Modal */
    .modal-backdrop {
      position: fixed;
      top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(0, 0, 0, 0.7);
      backdrop-filter: blur(4px);
      display: none;
      align-items: center;
      justify-content: center;
      z-index: 100;
    }
    .modal-backdrop.open {
      display: flex;
    }
    .modal-card {
      background: #1e293b;
      border: 1px solid var(--border);
      border-radius: 14px;
      width: 90%;
      max-width: 540px;
      padding: 24px;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.5);
    }
    .modal-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 18px;
    }
    .modal-title {
      font-size: 18px;
      font-weight: 700;
      margin: 0;
    }
    .modal-body {
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .modal-footer {
      display: flex;
      justify-content: flex-end;
      gap: 10px;
      margin-top: 24px;
    }
    .form-group {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .form-group label {
      font-size: 12px;
      font-weight: 600;
      color: var(--text-muted);
    }
    /* Toast */
    #toast-container {
      position: fixed;
      bottom: 24px;
      right: 24px;
      z-index: 200;
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .toast {
      background: #1e293b;
      border: 1px solid var(--border);
      border-left: 4px solid var(--accent);
      color: var(--text);
      padding: 12px 20px;
      border-radius: 8px;
      box-shadow: 0 10px 25px rgba(0,0,0,0.4);
      font-size: 13px;
      animation: slideIn 0.2s ease-out;
    }
    .toast.success { border-left-color: var(--green); }
    .toast.error { border-left-color: var(--red); }
    @keyframes slideIn {
      from { transform: translateX(50px); opacity: 0; }
      to { transform: translateX(0); opacity: 1; }
    }
  </style>
</head>
<body>
  <header>
    <div class="header-left">
      <div class="brand-logo">ImyBin Control Plane</div>
      <nav class="nav-tabs">
        <button class="nav-tab active" onclick="switchTab('config-tables')">📋 组件配置表管理</button>
        <button class="nav-tab" onclick="switchTab('overview')">📊 制品矩阵与效能大盘</button>
      </nav>
    </div>
    <div>
      <span id="license-badge" class="badge">加载授权中…</span>
    </div>
  </header>

  <div class="main-container">
    <!-- TAB 1: 配置表管理后台 -->
    <div id="tab-config-tables" class="tab-content active">
      <!-- Toolbar -->
      <div class="toolbar">
        <div class="toolbar-left">
          <label style="font-size:13px;color:var(--text-muted);font-weight:600;">工程配置表：</label>
          <select id="project-select" class="form-control" style="min-width:200px;font-weight:600;" onchange="loadSelectedProject()">
            <option value="">加载中…</option>
          </select>
          <button class="btn btn-primary" onclick="openNewTableModal()">＋ 新建配置表</button>
          <button class="btn" onclick="openDuplicateTableModal()">⎘ 复制配置表</button>
          <button class="btn btn-danger btn-sm" onclick="deleteCurrentTable()">🗑 删除配置表</button>
        </div>
        <div class="toolbar-right">
          <button class="btn" onclick="openImportModal()">⬆ 导入 JSON</button>
          <button class="btn" onclick="exportCurrentTable()">⬇ 导出 .imy-bin-config.json</button>
          <button class="btn btn-success" style="font-weight:700;" onclick="saveCurrentTable()">💾 保存修改</button>
        </div>
      </div>

      <!-- Project Metadata Card -->
      <div class="card" style="padding:16px 20px;">
        <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:16px;">
          <div style="display:flex;align-items:center;gap:20px;flex-wrap:wrap;">
            <div>
              <span style="font-size:12px;color:var(--text-muted);">目标工程：</span>
              <span id="meta-project-name" style="font-weight:700;font-size:16px;color:#fff;">-</span>
            </div>
            <div>
              <span style="font-size:12px;color:var(--text-muted);">环境参数：</span>
              <select id="meta-environment" class="form-control" style="padding:4px 8px;font-size:12px;">
                <option value="dev">dev (开发环境)</option>
                <option value="debug_iphoneos">debug_iphoneos (真机 Debug)</option>
                <option value="release_iphoneos">release_iphoneos (真机 Release)</option>
              </select>
            </div>
            <div>
              <span style="font-size:12px;color:var(--text-muted);">默认模式：</span>
              <select id="meta-default-mode" class="form-control" style="padding:4px 8px;font-size:12px;">
                <option value="binary">binary (二进制优先)</option>
                <option value="source">source (源码模式)</option>
                <option value="local">local (本地开发)</option>
                <option value="branch">branch (远程分支)</option>
              </select>
            </div>
          </div>
          <div>
            <span style="font-size:12px;color:var(--text-muted);">最后更新：</span>
            <span id="meta-updated-at" style="font-size:12px;color:var(--text-muted);font-family:monospace;">-</span>
          </div>
        </div>
      </div>

      <!-- App Version Columns Bar -->
      <div class="card">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
          <div style="display:flex;align-items:center;gap:10px;">
            <span style="font-weight:700;font-size:14px;">App 版本列管控 (App Release Baselines)</span>
            <span style="font-size:12px;color:var(--text-muted);">点击切换查看各 App 版本组件依赖</span>
          </div>
          <div style="display:flex;align-items:center;gap:8px;">
            <button class="btn btn-sm btn-primary" onclick="setActiveColumn()">★ 设为生效版本</button>
            <button class="btn btn-sm" onclick="openDuplicateColumnModal()">⎘ 复制此版本列</button>
            <button class="btn btn-sm" onclick="openNewColumnModal()">＋ 新增版本列</button>
            <button class="btn btn-sm btn-danger" onclick="deleteCurrentColumn()">✕ 删除此列</button>
          </div>
        </div>

        <div id="column-bar" class="column-bar">
          <!-- Column Pills Injected Here -->
        </div>

        <div style="display:flex;justify-content:space-between;align-items:center;margin-top:6px;">
          <div id="column-desc" style="font-size:12px;color:var(--text-muted);">说明：加载中…</div>
          <div style="display:flex;gap:12px;align-items:center;">
            <input type="text" id="component-filter" class="form-control" placeholder="按组件名称过滤..." style="width:200px;font-size:12px;" oninput="filterComponents()" />
            <button class="btn btn-sm btn-primary" onclick="openAddComponentModal()">＋ 添加组件</button>
          </div>
        </div>

        <!-- Components Matrix Table -->
        <table style="margin-top:16px;">
          <thead>
            <tr>
              <th style="width:22%;">组件名称</th>
              <th style="width:16%;">依赖模式 (Mode)</th>
              <th style="width:18%;">版本号 (Version)</th>
              <th style="width:30%;">分支 / Git / 本地相对路径</th>
              <th style="width:8%;text-align:center;">启用状态</th>
              <th style="width:6%;text-align:center;">操作</th>
            </tr>
          </thead>
          <tbody id="components-tbody">
            <tr><td colspan="6" style="color:var(--text-muted);text-align:center;padding:24px;">正在加载配置表数据…</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- TAB 2: 企业资产与效能大盘 -->
    <div id="tab-overview" class="tab-content">
      <div class="grid">
        <div class="card">
          <div style="color:var(--text-muted);font-size:13px;">已发布二进制组件版本</div>
          <div id="m-components" class="metric">0</div>
        </div>
        <div class="card">
          <div style="color:var(--text-muted);font-size:13px;">平均二进制命中率</div>
          <div id="m-hitrate" class="metric" style="color:var(--green);">0%</div>
        </div>
        <div class="card">
          <div style="color:var(--text-muted);font-size:13px;">累计节省全员编译工时</div>
          <div id="m-saved" class="metric">0 h</div>
        </div>
        <div class="card">
          <div style="color:var(--text-muted);font-size:13px;">云端构建队列任务数</div>
          <div id="m-jobs" class="metric" style="color:var(--amber);">0</div>
        </div>
      </div>

      <div class="card" style="margin-bottom:20px;">
        <h3 style="margin-top:0;">已发布组件制品资产矩阵 (Component Artifacts)</h3>
        <table>
          <thead>
            <tr><th>组件名称</th><th>版本号</th><th>状态</th><th>SHA-256 校验值</th></tr>
          </thead>
          <tbody id="artifacts-tbody">
            <tr><td colspan="4" style="color:var(--text-muted);">正在加载数据…</td></tr>
          </tbody>
        </table>
      </div>

      <div class="card">
        <h3 style="margin-top:0;">企业级不可篡改审计日志 (Audit Events)</h3>
        <table>
          <thead>
            <tr><th>时间</th><th>操作人 (Actor)</th><th>事件 (Action)</th><th>目标对象 (Subject)</th></tr>
          </thead>
          <tbody id="audits-tbody">
            <tr><td colspan="4" style="color:var(--text-muted);">暂无审计记录</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- MODALS -->

  <!-- Modal 1: 新建配置表 -->
  <div id="modal-new-table" class="modal-backdrop">
    <div class="modal-card">
      <div class="modal-header">
        <h3 class="modal-title">新建工程配置表</h3>
        <button class="btn btn-sm" onclick="closeModals()">✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label>工程标识名称 (Project Key)*</label>
          <input type="text" id="new-table-project" class="form-control" placeholder="如 MyApp 或 DemoApp" />
        </div>
        <div class="form-group">
          <label>初始 App 版本列名称*</label>
          <input type="text" id="new-table-column" class="form-control" value="1.0.0" />
        </div>
        <div class="form-group">
          <label>默认依赖解析模式</label>
          <select id="new-table-default-mode" class="form-control">
            <option value="binary" selected>binary (二进制优先)</option>
            <option value="source">source (源码模式)</option>
            <option value="local">local (本地开发)</option>
            <option value="branch">branch (远程分支)</option>
          </select>
        </div>
        <div class="form-group">
          <label>运行环境 (Environment)</label>
          <select id="new-table-env" class="form-control">
            <option value="dev" selected>dev</option>
            <option value="debug_iphoneos">debug_iphoneos</option>
            <option value="release_iphoneos">release_iphoneos</option>
          </select>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModals()">取消</button>
        <button class="btn btn-primary" onclick="submitNewTable()">立即创建</button>
      </div>
    </div>
  </div>

  <!-- Modal 2: 复制配置表 -->
  <div id="modal-duplicate-table" class="modal-backdrop">
    <div class="modal-card">
      <div class="modal-header">
        <h3 class="modal-title">复制配置表 (克隆工程依赖配置)</h3>
        <button class="btn btn-sm" onclick="closeModals()">✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label>源配置表：</label>
          <input type="text" id="dup-source-project" class="form-control" disabled />
        </div>
        <div class="form-group">
          <label>目标新工程标识名称 (Target Project)*</label>
          <input type="text" id="dup-target-project" class="form-control" placeholder="如 MyApp-Beta 或 DemoRelease" />
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModals()">取消</button>
        <button class="btn btn-primary" onclick="submitDuplicateTable()">开始复制</button>
      </div>
    </div>
  </div>

  <!-- Modal 3: 新增/复制版本列 -->
  <div id="modal-column" class="modal-backdrop">
    <div class="modal-card">
      <div class="modal-header">
        <h3 id="modal-column-title" class="modal-title">新增 App 版本列</h3>
        <button class="btn btn-sm" onclick="closeModals()">✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label>App 版本列标识 (如 1.3.0 或 release/202611)*</label>
          <input type="text" id="col-input-name" class="form-control" placeholder="如 1.3.0" />
        </div>
        <div class="form-group">
          <label>版本描述说明</label>
          <input type="text" id="col-input-desc" class="form-control" placeholder="如 App 1.3.0 迭代发版基线" />
        </div>
        <div class="form-group">
          <label>依赖基线来源 (从已有版本列复制)</label>
          <select id="col-input-source" class="form-control">
            <option value="">(空基线 / 手动添加)</option>
          </select>
        </div>
        <div class="form-group" style="flex-direction:row;align-items:center;gap:8px;">
          <input type="checkbox" id="col-input-set-active" checked />
          <label for="col-input-set-active" style="cursor:pointer;font-size:13px;color:var(--text);">创建后设为当前生效版本</label>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModals()">取消</button>
        <button class="btn btn-primary" onclick="submitColumnModal()">确定保存</button>
      </div>
    </div>
  </div>

  <!-- Modal 4: 添加组件 -->
  <div id="modal-add-component" class="modal-backdrop">
    <div class="modal-card">
      <div class="modal-header">
        <h3 class="modal-title">添加组件依赖</h3>
        <button class="btn btn-sm" onclick="closeModals()">✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label>组件 Pod 名称*</label>
          <input type="text" id="add-comp-name" class="form-control" placeholder="如 HDDynamicPod" />
        </div>
        <div class="form-group">
          <label>依赖解析模式 (Mode)*</label>
          <select id="add-comp-mode" class="form-control" onchange="toggleAddCompInputs()">
            <option value="binary" selected>binary (二进制 XCFramework)</option>
            <option value="source">source (版本源码)</option>
            <option value="local">local (本地工作区源码)</option>
            <option value="branch">branch (远程 Git 分支)</option>
          </select>
        </div>
        <div class="form-group" id="group-comp-version">
          <label>版本号 (Version)</label>
          <input type="text" id="add-comp-version" class="form-control" placeholder="如 0.1.6-beta.7" />
        </div>
        <div class="form-group" id="group-comp-path" style="display:none;">
          <label>本地相对路径 (Path)</label>
          <input type="text" id="add-comp-path" class="form-control" placeholder="如 ../HDDynamicPod" />
        </div>
        <div class="form-group" id="group-comp-branch" style="display:none;">
          <label>Git 仓库地址与分支</label>
          <input type="text" id="add-comp-git" class="form-control" placeholder="Git 地址 (可选)" style="margin-bottom:6px;" />
          <input type="text" id="add-comp-branch-name" class="form-control" placeholder="分支名，如 dev 或 feature/login" />
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModals()">取消</button>
        <button class="btn btn-primary" onclick="submitAddComponent()">添加至列表</button>
      </div>
    </div>
  </div>

  <!-- Modal 5: 导入配置表 -->
  <div id="modal-import" class="modal-backdrop">
    <div class="modal-card" style="max-width:680px;">
      <div class="modal-header">
        <h3 class="modal-title">导入 .imy-bin-config.json</h3>
        <button class="btn btn-sm" onclick="closeModals()">✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label>请粘贴 .imy-bin-config.json 内容：</label>
          <textarea id="import-json-text" class="form-control" style="height:280px;font-family:monospace;font-size:12px;"></textarea>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModals()">取消</button>
        <button class="btn btn-primary" onclick="submitImport()">解析并导入</button>
      </div>
    </div>
  </div>

  <div id="toast-container"></div>

  <script>
    let state = {
      tables: [],
      currentTable: null,
      viewingColumn: null, // Column currently being inspected/edited
    };

    function showToast(message, type = 'success') {
      const c = document.getElementById('toast-container');
      const el = document.createElement('div');
      el.className = 'toast ' + type;
      el.textContent = message;
      c.appendChild(el);
      setTimeout(() => {
        el.style.opacity = '0';
        setTimeout(() => el.remove(), 300);
      }, 3500);
    }

    function switchTab(tab) {
      document.querySelectorAll('.nav-tab').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      if (tab === 'config-tables') {
        document.querySelectorAll('.nav-tab')[0].classList.add('active');
        document.getElementById('tab-config-tables').classList.add('active');
      } else {
        document.querySelectorAll('.nav-tab')[1].classList.add('active');
        document.getElementById('tab-overview').classList.add('active');
        loadOverviewData();
      }
    }

    function closeModals() {
      document.querySelectorAll('.modal-backdrop').forEach(m => m.classList.remove('open'));
    }

    async function fetchTables() {
      try {
        const r = await fetch('/api/v1/config-tables');
        state.tables = await r.json();
        const sel = document.getElementById('project-select');
        sel.innerHTML = '';
        if (state.tables.length === 0) {
          sel.innerHTML = '<option value="">暂无配置表</option>';
          renderEmptyTable();
          return;
        }
        state.tables.forEach(t => {
          const opt = document.createElement('option');
          opt.value = t.project;
          opt.textContent = t.project + ' (' + (t.columns ? t.columns.length : 1) + ' 个版本列)';
          sel.appendChild(opt);
        });

        // If not selected, select first or keep current
        const currentProject = state.currentTable ? state.currentTable.project : state.tables[0].project;
        sel.value = currentProject;
        await loadProject(currentProject);
      } catch (err) {
        showToast('加载配置表失败: ' + err.message, 'error');
      }
    }

    async function loadSelectedProject() {
      const proj = document.getElementById('project-select').value;
      if (proj) await loadProject(proj);
    }

    async function loadProject(projectName) {
      try {
        const r = await fetch('/api/v1/config-tables/' + encodeURIComponent(projectName));
        if (!r.ok) throw new Error('HTTP ' + r.status);
        state.currentTable = await r.json();
        state.viewingColumn = state.currentTable.activeColumn || (state.currentTable.columns && state.currentTable.columns[0] && state.currentTable.columns[0].name) || '1.0.0';
        renderCurrentTable();
      } catch (err) {
        showToast('读取配置表失败: ' + err.message, 'error');
      }
    }

    function renderEmptyTable() {
      document.getElementById('meta-project-name').textContent = '-';
      document.getElementById('column-bar').innerHTML = '<div style="color:var(--text-muted);font-size:13px;">请先创建或选择一个工程配置表</div>';
      document.getElementById('components-tbody').innerHTML = '<tr><td colspan="6" style="color:var(--text-muted);text-align:center;padding:24px;">暂无数据</td></tr>';
    }

    function renderCurrentTable() {
      const t = state.currentTable;
      if (!t) return;

      document.getElementById('meta-project-name').textContent = t.project;
      document.getElementById('meta-environment').value = t.environment || 'dev';
      document.getElementById('meta-default-mode').value = t.defaultMode || 'binary';
      document.getElementById('meta-updated-at').textContent = t.updatedAt ? new Date(t.updatedAt).toLocaleString() : '-';

      // Render column pills
      const colBar = document.getElementById('column-bar');
      colBar.innerHTML = '';
      const cols = t.columns || [];
      cols.forEach(col => {
        const pill = document.createElement('div');
        pill.className = 'column-pill' + (col.name === state.viewingColumn ? ' viewing' : '');
        pill.onclick = () => {
          state.viewingColumn = col.name;
          renderCurrentTable();
        };

        let html = '<span>' + col.name + '</span>';
        if (col.name === t.activeColumn) {
          html += '<span class="active-star">当前生效</span>';
        }
        pill.innerHTML = html;
        colBar.appendChild(pill);
      });

      // Viewing column data
      const viewingColObj = cols.find(c => c.name === state.viewingColumn) || cols[0];
      if (viewingColObj) {
        document.getElementById('column-desc').textContent = '说明：' + (viewingColObj.description || '无特殊说明') + ' (' + (viewingColObj.components ? viewingColObj.components.length : 0) + ' 个依赖)';
        renderComponentsTable(viewingColObj.components || []);
      } else {
        renderComponentsTable(t.components || []);
      }
    }

    function renderComponentsTable(components) {
      const tbody = document.getElementById('components-tbody');
      const filter = (document.getElementById('component-filter').value || '').toLowerCase().trim();
      const filtered = components
        .map((c, idx) => ({ c, idx }))
        .filter(({ c }) => !filter || c.name.toLowerCase().includes(filter));

      if (filtered.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="color:var(--text-muted);text-align:center;padding:24px;">' + (filter ? '无匹配组件' : '当前版本列暂无组件依赖，点击上方“＋ 添加组件”') + '</td></tr>';
        return;
      }

      tbody.innerHTML = filtered.map(({ c, idx }) => {
        const modeClass = 'mode-' + (c.mode || 'binary');
        const isBranch = c.mode === 'branch';
        const isLocal = c.mode === 'local';

        let pathGitInput = '';
        if (isBranch) {
          pathGitInput = '<input type="text" class="table-input" placeholder="分支 (如 dev)" value="' + (c.branch || '') + '" onchange="updateCompField(' + idx + ', \\'branch\\', this.value)" />';
        } else if (isLocal) {
          pathGitInput = '<input type="text" class="table-input" placeholder="本地相对路径 (如 ../Pod)" value="' + (c.path || '') + '" onchange="updateCompField(' + idx + ', \\'path\\', this.value)" />';
        } else {
          pathGitInput = '<span style="color:var(--text-muted);font-size:12px;">' + (c.path || '默认远端二进制/源码源') + '</span>';
        }

        return '<tr>' +
          '<td><b>' + c.name + '</b></td>' +
          '<td>' +
            '<select class="table-input" onchange="updateCompMode(' + idx + ', this.value)">' +
              '<option value="binary"' + (c.mode === 'binary' ? ' selected' : '') + '>🟢 二进制 (binary)</option>' +
              '<option value="source"' + (c.mode === 'source' ? ' selected' : '') + '>🔵 源码 (source)</option>' +
              '<option value="local"' + (c.mode === 'local' ? ' selected' : '') + '>🟡 本地 (local)</option>' +
              '<option value="branch"' + (c.mode === 'branch' ? ' selected' : '') + '>🟣 分支 (branch)</option>' +
            '</select>' +
          '</td>' +
          '<td><input type="text" class="table-input" value="' + (c.version || '') + '" placeholder="如 0.1.0" onchange="updateCompField(' + idx + ', \\'version\\', this.value)" /></td>' +
          '<td>' + pathGitInput + '</td>' +
          '<td style="text-align:center;"><input type="checkbox" ' + (c.enabled !== false ? 'checked' : '') + ' onchange="updateCompField(' + idx + ', \\'enabled\\', this.checked)" /></td>' +
          '<td style="text-align:center;"><button class="btn btn-sm btn-danger" onclick="removeComp(' + idx + ')">✕</button></td>' +
        '</tr>';
      }).join('');
    }

    function getCurrentViewingComponents() {
      if (!state.currentTable) return [];
      const cols = state.currentTable.columns || [];
      const viewingColObj = cols.find(c => c.name === state.viewingColumn);
      return viewingColObj ? (viewingColObj.components || []) : (state.currentTable.components || []);
    }

    function updateCompMode(idx, newMode) {
      const comps = getCurrentViewingComponents();
      if (comps[idx]) {
        comps[idx].mode = newMode;
        renderCurrentTable();
      }
    }

    function updateCompField(idx, field, value) {
      const comps = getCurrentViewingComponents();
      if (comps[idx]) {
        comps[idx][field] = value;
      }
    }

    function removeComp(idx) {
      const comps = getCurrentViewingComponents();
      if (comps[idx] && confirm('确定要移除组件 ' + comps[idx].name + ' 吗？')) {
        comps.splice(idx, 1);
        renderCurrentTable();
      }
    }

    function filterComponents() {
      const comps = getCurrentViewingComponents();
      renderComponentsTable(comps);
    }

    function setActiveColumn() {
      if (!state.currentTable || !state.viewingColumn) return;
      state.currentTable.activeColumn = state.viewingColumn;
      renderCurrentTable();
      showToast('已将 ' + state.viewingColumn + ' 设为生效版本列，请点击“保存修改”以同步！');
    }

    async function saveCurrentTable() {
      if (!state.currentTable) return;
      const t = state.currentTable;
      t.environment = document.getElementById('meta-environment').value;
      t.defaultMode = document.getElementById('meta-default-mode').value;

      try {
        const r = await fetch('/api/v1/config-tables/' + encodeURIComponent(t.project), {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(t),
        });
        if (!r.ok) {
          const err = await r.json();
          throw new Error(err.message || 'HTTP ' + r.status);
        }
        state.currentTable = await r.json();
        renderCurrentTable();
        showToast('✅ 配置表保存成功并已同步！');
      } catch (err) {
        showToast('保存失败: ' + err.message, 'error');
      }
    }

    function exportCurrentTable() {
      if (!state.currentTable) return;
      window.location.href = '/api/v1/config-tables/' + encodeURIComponent(state.currentTable.project) + '/export';
    }

    async function deleteCurrentTable() {
      if (!state.currentTable) return;
      const proj = state.currentTable.project;
      if (!confirm('确定要删除配置表 ' + proj + ' 吗？此操作不可撤销。')) return;
      try {
        const r = await fetch('/api/v1/config-tables/' + encodeURIComponent(proj), { method: 'DELETE' });
        if (!r.ok) throw new Error('HTTP ' + r.status);
        showToast('配置表 ' + proj + ' 已删除');
        state.currentTable = null;
        await fetchTables();
      } catch (err) {
        showToast('删除失败: ' + err.message, 'error');
      }
    }

    async function deleteCurrentColumn() {
      if (!state.currentTable || !state.viewingColumn) return;
      const cols = state.currentTable.columns || [];
      if (cols.length <= 1) {
        alert('无法删除：配置表必须至少保留一个 App 版本列。');
        return;
      }
      if (!confirm('确定要删除版本列 ' + state.viewingColumn + ' 吗？')) return;
      const idx = cols.findIndex(c => c.name === state.viewingColumn);
      if (idx >= 0) {
        cols.splice(idx, 1);
        if (state.currentTable.activeColumn === state.viewingColumn) {
          state.currentTable.activeColumn = cols[0].name;
        }
        state.viewingColumn = cols[0].name;
        renderCurrentTable();
        showToast('版本列已删除，请点击“保存修改”以同步生效！');
      }
    }

    // Modal Triggers
    function openNewTableModal() {
      document.getElementById('new-table-project').value = '';
      document.getElementById('new-table-column').value = '1.0.0';
      document.getElementById('modal-new-table').classList.add('open');
    }

    async function submitNewTable() {
      const project = document.getElementById('new-table-project').value.trim();
      const colName = document.getElementById('new-table-column').value.trim();
      const defaultMode = document.getElementById('new-table-default-mode').value;
      const environment = document.getElementById('new-table-env').value;
      if (!project || !colName) {
        alert('请输入工程名称和初始版本列标识');
        return;
      }
      try {
        const r = await fetch('/api/v1/config-tables', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            project,
            activeColumn: colName,
            defaultMode,
            environment,
            columns: [{
              name: colName,
              description: colName + ' 初始发版基线',
              components: [],
            }],
          }),
        });
        if (!r.ok) {
          const err = await r.json();
          throw new Error(err.message || 'HTTP ' + r.status);
        }
        closeModals();
        showToast('🎉 新建配置表 ' + project + ' 成功！');
        await fetchTables();
        await loadProject(project);
      } catch (err) {
        showToast('创建失败: ' + err.message, 'error');
      }
    }

    function openDuplicateTableModal() {
      if (!state.currentTable) return;
      document.getElementById('dup-source-project').value = state.currentTable.project;
      document.getElementById('dup-target-project').value = state.currentTable.project + '-Copy';
      document.getElementById('modal-duplicate-table').classList.add('open');
    }

    async function submitDuplicateTable() {
      const source = state.currentTable.project;
      const targetProject = document.getElementById('dup-target-project').value.trim();
      if (!targetProject) {
        alert('请输入新工程名称');
        return;
      }
      try {
        const r = await fetch('/api/v1/config-tables/' + encodeURIComponent(source) + '/duplicate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ targetProject }),
        });
        if (!r.ok) {
          const err = await r.json();
          throw new Error(err.message || 'HTTP ' + r.status);
        }
        closeModals();
        showToast('⎘ 配置表已复制为 ' + targetProject + '！');
        await fetchTables();
        await loadProject(targetProject);
      } catch (err) {
        showToast('复制失败: ' + err.message, 'error');
      }
    }

    function openNewColumnModal() {
      document.getElementById('modal-column-title').textContent = '新增 App 版本列';
      document.getElementById('col-input-name').value = '';
      document.getElementById('col-input-desc').value = '';
      populateColumnSources();
      document.getElementById('modal-column').classList.add('open');
    }

    function openDuplicateColumnModal() {
      if (!state.currentTable || !state.viewingColumn) return;
      document.getElementById('modal-column-title').textContent = '复制版本列 (从 ' + state.viewingColumn + ' 复制)';
      document.getElementById('col-input-name').value = state.viewingColumn + '-copy';
      document.getElementById('col-input-desc').value = '由 ' + state.viewingColumn + ' 复制创建的 App 版本基线';
      populateColumnSources(state.viewingColumn);
      document.getElementById('modal-column').classList.add('open');
    }

    function populateColumnSources(selected) {
      const sel = document.getElementById('col-input-source');
      sel.innerHTML = '<option value="">(空白基线 / 不复制组件)</option>';
      const cols = (state.currentTable && state.currentTable.columns) || [];
      cols.forEach(c => {
        const opt = document.createElement('option');
        opt.value = c.name;
        opt.textContent = c.name + ' (' + (c.components ? c.components.length : 0) + ' 个组件)';
        if (selected && c.name === selected) opt.selected = true;
        sel.appendChild(opt);
      });
    }

    async function submitColumnModal() {
      const colName = document.getElementById('col-input-name').value.trim();
      const desc = document.getElementById('col-input-desc').value.trim();
      const sourceCol = document.getElementById('col-input-source').value;
      const setActive = document.getElementById('col-input-set-active').checked;
      if (!colName) {
        alert('请输入版本列标识');
        return;
      }
      try {
        const r = await fetch('/api/v1/config-tables/' + encodeURIComponent(state.currentTable.project) + '/duplicate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            targetColumn: colName,
            sourceColumn: sourceCol,
            description: desc,
            setActive,
          }),
        });
        if (!r.ok) {
          const err = await r.json();
          throw new Error(err.message || 'HTTP ' + r.status);
        }
        state.currentTable = await r.json();
        state.viewingColumn = colName;
        closeModals();
        renderCurrentTable();
        showToast('✅ 版本列 ' + colName + ' 创建成功！');
      } catch (err) {
        showToast('创建列失败: ' + err.message, 'error');
      }
    }

    function openAddComponentModal() {
      document.getElementById('add-comp-name').value = '';
      document.getElementById('add-comp-version').value = '';
      document.getElementById('add-comp-mode').value = 'binary';
      document.getElementById('add-comp-path').value = '';
      document.getElementById('add-comp-git').value = '';
      document.getElementById('add-comp-branch-name').value = '';
      toggleAddCompInputs();
      document.getElementById('modal-add-component').classList.add('open');
    }

    function toggleAddCompInputs() {
      const m = document.getElementById('add-comp-mode').value;
      document.getElementById('group-comp-path').style.display = (m === 'local') ? 'flex' : 'none';
      document.getElementById('group-comp-branch').style.display = (m === 'branch') ? 'flex' : 'none';
    }

    function submitAddComponent() {
      const name = document.getElementById('add-comp-name').value.trim();
      const mode = document.getElementById('add-comp-mode').value;
      const version = document.getElementById('add-comp-version').value.trim();
      const path = document.getElementById('add-comp-path').value.trim() || null;
      const git = document.getElementById('add-comp-git').value.trim() || null;
      const branch = document.getElementById('add-comp-branch-name').value.trim() || null;

      if (!name) {
        alert('请输入组件 Pod 名称');
        return;
      }

      const comps = getCurrentViewingComponents();
      if (comps.some(c => c.name === name)) {
        alert('组件 ' + name + ' 已存在于当前版本列中');
        return;
      }

      comps.push({
        name,
        mode,
        version,
        path,
        git,
        branch,
        enabled: true,
        supportsLocal: mode === 'local',
      });

      closeModals();
      renderCurrentTable();
      showToast('已添加组件 ' + name + '，请点击“保存修改”！');
    }

    function openImportModal() {
      document.getElementById('import-json-text').value = '';
      document.getElementById('modal-import').classList.add('open');
    }

    async function submitImport() {
      const raw = document.getElementById('import-json-text').value.trim();
      if (!raw) return;
      try {
        const payload = JSON.parse(raw);
        if (!payload.project) throw new Error('缺少 project 字段');
        const r = await fetch('/api/v1/config-tables', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        if (!r.ok) {
          // If already exists, update instead
          const updateRes = await fetch('/api/v1/config-tables/' + encodeURIComponent(payload.project), {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
          });
          if (!updateRes.ok) throw new Error('导入更新失败');
        }
        closeModals();
        showToast('✅ 导入成功！');
        await fetchTables();
        await loadProject(payload.project);
      } catch (err) {
        alert('解析或导入错误: ' + err.message);
      }
    }

    // Tab 2: Overview & Artifacts
    function loadOverviewData() {
      fetch('/api/v1/enterprise/overview')
        .then(r => r.json())
        .then(data => {
          const lic = data.license || {};
          document.getElementById('license-badge').textContent =
            (lic.tier || 'community').toUpperCase() + ' · ' + (lic.org || 'Community');
          document.getElementById('m-components').textContent = (data.components || []).length;
          document.getElementById('m-hitrate').textContent = ((data.roi && data.roi.averageHitRatePercent) || 0) + '%';
          document.getElementById('m-saved').textContent = ((data.roi && data.roi.totalSavedHours) || 0) + ' h';
          document.getElementById('m-jobs').textContent = (data.jobs || []).length;

          const cBody = document.getElementById('artifacts-tbody');
          if ((data.components || []).length === 0) {
            cBody.innerHTML = '<tr><td colspan="4" style="color:var(--text-muted);">暂无已上传的二进制组件</td></tr>';
          } else {
            cBody.innerHTML = data.components.map(c =>
              '<tr><td><b>' + c.name + '</b></td><td>' + c.version + '</td><td>' + (c.status || 'active') +
              '</td><td style="font-family:monospace;font-size:12px;">' + (c.sha256 || '-') + '</td></tr>'
            ).join('');
          }

          const aBody = document.getElementById('audits-tbody');
          if ((data.audits || []).length > 0) {
            aBody.innerHTML = data.audits.map(a =>
              '<tr><td>' + new Date(a.createdAt).toLocaleString() + '</td><td>' + a.actor +
              '</td><td><code>' + a.action + '</code></td><td>' + a.subject + '</td></tr>'
            ).join('');
          }
        })
        .catch(() => {});
    }

    // Init
    fetchTables();
    loadOverviewData();
  </script>
</body>
</html>`
}

module.exports = {
  createEnterpriseRouter,
  computePolicyDiff,
  renderDashboardHtml,
}
