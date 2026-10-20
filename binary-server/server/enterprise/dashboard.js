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

  router.get(['/', '/dashboard'], async (ctx) => {
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
  <title>ImyBin Enterprise Control Plane — 企业级二进制研发管控大盘</title>
  <style>
    :root {
      --bg: #0f172a;
      --card: #1e293b;
      --border: #334155;
      --text: #f8fafc;
      --muted: #94a3b8;
      --accent: #38bdf8;
      --green: #4ade80;
      --amber: #fbbf24;
    }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
      background: var(--bg);
      color: var(--text);
      padding: 24px 32px;
    }
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 1px solid var(--border);
      padding-bottom: 16px;
      margin-bottom: 24px;
    }
    .badge {
      background: rgba(56, 189, 248, 0.15);
      color: var(--accent);
      padding: 4px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 600;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 18px;
    }
    .metric {
      font-size: 28px;
      font-weight: 700;
      margin-top: 8px;
      color: var(--accent);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      text-align: left;
      padding: 10px 8px;
      border-bottom: 1px solid var(--border);
    }
    th { color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <div>
      <h1 style="margin:0;font-size:22px;">ImyBin Enterprise Control Plane</h1>
      <p style="margin:4px 0 0;color:var(--muted);font-size:13px;">
        iOS 组件化 XCFramework 二进制制品、平台策略 Revision、云端构建集群与编译提效 ROI 管控中心
      </p>
    </div>
    <span id="license-badge" class="badge">加载授权中…</span>
  </header>

  <div class="grid">
    <div class="card">
      <div style="color:var(--muted);font-size:13px;">已发布二进制组件版本</div>
      <div id="m-components" class="metric">0</div>
    </div>
    <div class="card">
      <div style="color:var(--muted);font-size:13px;">平均二进制命中率</div>
      <div id="m-hitrate" class="metric" style="color:var(--green);">0%</div>
    </div>
    <div class="card">
      <div style="color:var(--muted);font-size:13px;">累计节省全员编译工时</div>
      <div id="m-saved" class="metric">0 h</div>
    </div>
    <div class="card">
      <div style="color:var(--muted);font-size:13px;">云端构建队列任务数</div>
      <div id="m-jobs" class="metric" style="color:var(--amber);">0</div>
    </div>
  </div>

  <div class="card" style="margin-bottom:20px;">
    <h3 style="margin-top:0;">已发布组件制品资产矩阵 (Component Artifacts)</h3>
    <table>
      <thead>
        <tr><th>组件名称</th><th>版本号</th><th>状态</th><th>SHA-256 校验值</th></tr>
      </thead>
      <tbody id="components-tbody">
        <tr><td colspan="4" style="color:var(--muted);">正在加载数据…</td></tr>
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
        <tr><td colspan="4" style="color:var(--muted);">暂无审计记录</td></tr>
      </tbody>
    </table>
  </div>

  <script>
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

        const cBody = document.getElementById('components-tbody');
        if ((data.components || []).length === 0) {
          cBody.innerHTML = '<tr><td colspan="4" style="color:var(--muted);">暂无已上传的二进制组件</td></tr>';
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
  </script>
</body>
</html>`
}

module.exports = {
  createEnterpriseRouter,
  computePolicyDiff,
}
