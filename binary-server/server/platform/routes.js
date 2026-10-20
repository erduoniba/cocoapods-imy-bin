'use strict'

const crypto = require('crypto')
const fs = require('fs')
const Router = require('@koa/router')
const multer = require('@koa/multer')
const mongoose = require('mongoose')

const { getBearerToken, tokensMatch } = require('../middleware/auth')
const { validateSegment } = require('../utils/dir')
const { conflict, invalid, validateCommit, validatePolicy, validateRelease } = require('./validation')
const { verifyActivation, visibleManagedArtifact } = require('./workflow')
const Release = require('../models/release')
const BuildJob = require('../models/build_job')
const Component = require('../models/component')
const Project = require('../models/project')
const ProjectPolicyRevision = require('../models/project_policy')
const AuditEvent = require('../models/audit_event')

const LEASE_MS = 2 * 60 * 1000
const MAX_JSON_BYTES = 1024 * 1024

async function json(ctx) {
  if (!/^application\/json(?:\s*;|$)/i.test(ctx.get('content-type'))) invalid('application/json required')
  const chunks = []
  let length = 0
  for await (const chunk of ctx.req) {
    length += chunk.length
    if (length > MAX_JSON_BYTES) {
      const error = new Error('JSON body exceeds 1 MiB')
      error.status = 413
      error.code = 'BODY_TOO_LARGE'
      throw error
    }
    chunks.push(chunk)
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    invalid('Malformed JSON body')
  }
}

function requireId(ctx, value) {
  if (!mongoose.isValidObjectId(value)) invalid('Invalid id')
  return value
}

function createPlatformRouter({ config, storage }) {
  const router = new Router({ prefix: '/api/v1' })
  const upload = multer({
    storage: multer.diskStorage({
      destination: (_req, _file, callback) => storage.createUploadDirectory().then(
        (directory) => callback(null, directory), callback
      ),
      filename: (_req, _file, callback) => callback(null, storage.createTemporaryFilename()),
    }),
    limits: { fileSize: config.maxUploadBytes, files: 1, fields: 0 },
    fileFilter: (_req, file, callback) => callback(null, storage.isZipFilename(file.originalname)),
  })

  function authenticate(kind) {
    return async (ctx, next) => {
      const expected = kind === 'agent' ? config.agentToken : config.platformToken
      const provided = getBearerToken(ctx.get('authorization'))
      if (!provided || !tokensMatch(provided, expected)) {
        ctx.throw(401, 'A valid platform token is required', { code: 'UNAUTHORIZED' })
      }
      ctx.state.actor = kind === 'agent' ? 'macos-agent' : 'platform-operator'
      await next()
    }
  }

  async function audit(ctx, action, subject, details = {}) {
    await AuditEvent.create({ actor: ctx.state.actor, action, subject, details })
  }

  async function leasedJob(ctx, releaseId) {
    const leaseId = ctx.get('x-job-lease')
    if (!leaseId) ctx.throw(403, 'A job lease is required', { code: 'LEASE_REQUIRED' })
    const job = await BuildJob.findOne({
      releaseId, leaseId, status: 'leased', leaseExpiresAt: { $gt: new Date() },
    }).lean().exec()
    if (!job) ctx.throw(409, 'The job lease has expired or belongs to another worker', { code: 'LEASE_CONFLICT' })
    return job
  }

  router.post('/releases', authenticate('operator'), async (ctx) => {
    const input = validateRelease(await json(ctx))
    let release = await Release.findOne({ name: input.name, version: input.version }).lean().exec()
    if (release && release.sourceCommit !== input.sourceCommit) conflict('This component version is reserved by another source commit')
    if (!release) {
      try {
        release = await Release.create(input)
        await audit(ctx, 'release.requested', `${input.name}@${input.version}`, { sourceCommit: input.sourceCommit })
      } catch (error) {
        if (error.code !== 11000) throw error
        release = await Release.findOne({ name: input.name, version: input.version }).lean().exec()
        if (!release || release.sourceCommit !== input.sourceCommit) conflict('Component version conflict')
      }
    }
    if (release.status === 'requested') {
      await BuildJob.updateOne({ releaseId: release._id }, { $setOnInsert: { releaseId: release._id } }, { upsert: true }).exec()
    }
    ctx.status = 202
    ctx.body = { id: release._id, name: release.name, version: release.version, status: release.status }
  })

  router.get('/releases/:id', authenticate('operator'), async (ctx) => {
    const release = await Release.findById(requireId(ctx, ctx.params.id)).lean().exec()
    if (!release) ctx.throw(404, 'Release not found', { code: 'NOT_FOUND' })
    ctx.body = release
  })

  router.post('/releases/:id/retry', authenticate('operator'), async (ctx) => {
    const id = requireId(ctx, ctx.params.id)
    const release = await Release.findOneAndUpdate(
      { _id: id, status: 'failed' }, { $set: { status: 'requested', failureSummary: null } }, { new: true }
    ).lean().exec()
    if (!release) conflict('Only failed releases can be retried')
    await BuildJob.updateOne(
      { releaseId: id, status: 'failed' },
      { $set: { status: 'queued', leaseId: null, leaseOwner: null, leaseExpiresAt: null } }
    ).exec()
    await audit(ctx, 'release.retried', `${release.name}@${release.version}`)
    ctx.status = 202
    ctx.body = { id, status: release.status }
  })

  router.post('/jobs/claim', authenticate('agent'), async (ctx) => {
    const body = await json(ctx)
    const agentId = validateSegment(body?.agentId, 'agentId')
    const now = new Date()
    const leaseId = crypto.randomUUID()
    const job = await BuildJob.findOneAndUpdate(
      { $or: [{ status: 'queued' }, { status: 'leased', leaseExpiresAt: { $lte: now } }] },
      { $set: { status: 'leased', leaseId, leaseOwner: agentId, leaseExpiresAt: new Date(now.getTime() + LEASE_MS) }, $inc: { attempts: 1 } },
      { sort: { createdAt: 1 }, new: true }
    ).lean().exec()
    if (!job) { ctx.status = 204; return }
    const release = await Release.findById(job.releaseId).lean().exec()
    ctx.body = { jobId: job._id, leaseId, leaseExpiresAt: job.leaseExpiresAt, release: {
      id: release._id, name: release.name, version: release.version, sourceCommit: release.sourceCommit,
      sourceSpecCommit: release.sourceSpecCommit, binarySpecCommit: release.binarySpecCommit,
    } }
  })

  router.post('/jobs/:id/heartbeat', authenticate('agent'), async (ctx) => {
    const id = requireId(ctx, ctx.params.id)
    const leaseId = ctx.get('x-job-lease')
    const job = await BuildJob.findOneAndUpdate(
      { _id: id, leaseId, status: 'leased', leaseExpiresAt: { $gt: new Date() } },
      { $set: { leaseExpiresAt: new Date(Date.now() + LEASE_MS) } }, { new: true }
    ).lean().exec()
    if (!job) conflict('Job lease expired')
    ctx.body = { leaseExpiresAt: job.leaseExpiresAt }
  })

  router.post('/jobs/:id/events', authenticate('agent'), async (ctx) => {
    const id = requireId(ctx, ctx.params.id)
    const body = await json(ctx)
    if (!['output', 'phase', 'warning', 'error'].includes(body?.kind) ||
        typeof body.message !== 'string' || body.message.length > 4096) invalid('Invalid job event')
    const job = await BuildJob.findOneAndUpdate(
      { _id: id, leaseId: ctx.get('x-job-lease'), status: 'leased', leaseExpiresAt: { $gt: new Date() } },
      { $push: { events: { $each: [{ kind: body.kind, message: body.message, at: new Date() }], $slice: -1000 } } },
      { new: true }
    ).lean().exec()
    if (!job) conflict('Job lease expired')
    ctx.status = 202
    ctx.body = { accepted: true }
  })

  router.post('/releases/:id/steps', authenticate('agent'), async (ctx) => {
    const id = requireId(ctx, ctx.params.id)
    await leasedJob(ctx, id)
    const body = await json(ctx)
    const field = { source: 'sourceSpecCommit', binary: 'binarySpecCommit' }[body?.step]
    if (!field) invalid('step must be source or binary')
    const commit = validateCommit(body.specCommit)
    const release = await Release.findById(id).lean().exec()
    if (!release || release.status !== 'requested') conflict('Release is not accepting steps')
    if (release[field] && release[field] !== commit) conflict('Published spec commit cannot be changed')
    if (!release[field]) {
      const result = await Release.updateOne({ _id: id, [field]: null, status: 'requested' }, { $set: { [field]: commit } }).exec()
      if (result.modifiedCount !== 1) {
        const current = await Release.findById(id).lean().exec()
        if (current?.[field] !== commit) conflict('Published spec commit cannot be changed')
      }
      await audit(ctx, `release.${body.step}SpecAttested`, `${release.name}@${release.version}`, { specCommit: commit })
    }
    ctx.body = { step: body.step, specCommit: commit }
  })

  router.post('/releases/:id/artifact', authenticate('agent'), upload.single('file'), async (ctx) => {
    const file = ctx.file
    try {
      const id = requireId(ctx, ctx.params.id)
      await leasedJob(ctx, id)
      const release = await Release.findById(id).lean().exec()
      if (!release || release.status !== 'requested') conflict('Release is not accepting artifacts')
      if (!file || !storage.isZipFilename(file.originalname)) invalid('One ZIP file is required')
      const handle = await fs.promises.open(file.path, 'r')
      const header = Buffer.alloc(4)
      try { await handle.read(header, 0, 4, 0) } finally { await handle.close() }
      if (!header.equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]))) invalid('Invalid ZIP header')
      const sha256 = await storage.calculateSha256(file.path)
      const existing = await Component.findOne({ name: release.name, version: release.version }).lean().exec()
      if (existing) {
        if (String(existing.managedReleaseId) !== String(id) || existing.sha256 !== sha256 || existing.status !== 'staged') {
          conflict('A different artifact already exists for this version')
        }
        ctx.body = { sha256, size: existing.size }
        return
      }
      let artifact
      try {
        artifact = await Component.create({
          name: release.name, version: release.version, sha256, size: file.size,
          status: 'staged', managedReleaseId: id,
        })
      } catch (error) {
        if (error.code === 11000) conflict('A different artifact already exists for this version')
        throw error
      }
      try {
        await storage.storeArtifact(file.path, release.name, release.version)
      } catch (error) {
        await Component.deleteOne({ _id: artifact._id, status: 'staged' }).exec()
        throw error
      }
      await audit(ctx, 'artifact.staged', `${release.name}@${release.version}`, { sha256, size: file.size })
      ctx.status = 201
      ctx.body = { sha256, size: file.size }
    } finally {
      await storage.removeFile(file?.path)
    }
  })

  router.post('/jobs/:id/finish', authenticate('agent'), async (ctx) => {
    const id = requireId(ctx, ctx.params.id)
    const body = await json(ctx)
    if (typeof body?.success !== 'boolean') invalid('success must be a boolean')
    const job = await BuildJob.findOne({
      _id: id, leaseId: ctx.get('x-job-lease'), status: 'leased', leaseExpiresAt: { $gt: new Date() },
    }).lean().exec()
    if (!job) conflict('Job lease expired')
    const release = await Release.findById(job.releaseId).lean().exec()
    if (!release || release.status !== 'requested') conflict('Release is not awaiting completion')
    if (!body.success) {
      const summary = typeof body.failureSummary === 'string' ? body.failureSummary.slice(0, 1000) : 'Agent reported failure'
      await Release.updateOne({ _id: release._id, status: 'requested' }, { $set: { status: 'failed', failureSummary: summary } }).exec()
      await BuildJob.updateOne({ _id: id, leaseId: job.leaseId }, { $set: { status: 'failed', leaseExpiresAt: null } }).exec()
      await audit(ctx, 'release.failed', `${release.name}@${release.version}`, { summary })
      ctx.body = { status: 'failed' }
      return
    }
    const artifact = await Component.findOne({
      name: release.name, version: release.version, status: 'staged', managedReleaseId: release._id,
    }).lean().exec()
    const filename = await storage.findArtifact(release.name, release.version)
    const checksum = filename ? await storage.calculateSha256(filename) : null
    verifyActivation(release, artifact, checksum)
    // Only this status change exposes the managed release. Legacy /frameworks never lists staged artifacts.
    const activated = await Release.updateOne({ _id: release._id, status: 'requested' }, { $set: { status: 'active' } }).exec()
    if (activated.modifiedCount !== 1) conflict('Release was already completed')
    await BuildJob.updateOne({ _id: id, leaseId: job.leaseId }, { $set: { status: 'succeeded', leaseExpiresAt: null } }).exec()
    await audit(ctx, 'release.activated', `${release.name}@${release.version}`, { sha256: artifact.sha256 })
    ctx.body = { status: 'active', sha256: artifact.sha256 }
  })

  router.get('/artifacts/:name/:version/zip', authenticate('operator'), async (ctx) => {
    const name = validateSegment(ctx.params.name, 'name')
    const version = validateSegment(ctx.params.version, 'version')
    const release = await Release.findOne({ name, version, status: 'active' }).lean().exec()
    if (!release) ctx.throw(404, 'Release not active', { code: 'NOT_FOUND' })
    const artifact = await Component.findOne({ name, version, status: 'staged', managedReleaseId: release._id }).lean().exec()
    if (!visibleManagedArtifact(release, artifact)) ctx.throw(404, 'Artifact not available', { code: 'NOT_FOUND' })
    const filename = await storage.findArtifact(name, version)
    if (!filename) ctx.throw(404, 'Artifact file not available', { code: 'NOT_FOUND' })
    ctx.type = 'application/zip'
    ctx.length = (await fs.promises.stat(filename)).size
    ctx.body = fs.createReadStream(filename)
  })

  router.post('/projects/:key/policies', authenticate('operator'), async (ctx) => {
    const project = validateSegment(ctx.params.key, 'project')
    const targets = validatePolicy(await json(ctx))
    // Only active, paired releases can be referenced in a managed policy.
    for (const target of targets) {
      for (const dependency of target.dependencies) {
        const exists = await Release.exists({ name: dependency.name, version: dependency.version, status: 'active' })
        if (!exists) conflict(`${dependency.name}@${dependency.version} is not an active paired release`)
      }
    }
    const revision = crypto.randomUUID()
    await Project.updateOne({ key: project }, { $setOnInsert: { key: project } }, { upsert: true }).exec()
    const policy = await ProjectPolicyRevision.create({ project, revision, targets })
    await audit(ctx, 'policy.created', `${project}@${revision}`)
    ctx.status = 201
    ctx.body = { project, revision, targets: policy.targets }
  })

  router.post('/projects/:key/policies/activate', authenticate('operator'), async (ctx) => {
    const project = validateSegment(ctx.params.key, 'project')
    const body = await json(ctx)
    const revision = body?.revision
    const expectedRevision = body?.expectedRevision ?? null
    if (typeof revision !== 'string' || typeof expectedRevision !== 'string' && expectedRevision !== null) invalid('Invalid revisions')
    const policy = await ProjectPolicyRevision.findOne({ project, revision }).lean().exec()
    if (!policy) ctx.throw(404, 'Policy revision not found', { code: 'NOT_FOUND' })
    const updated = await Project.findOneAndUpdate(
      { key: project, activeRevision: expectedRevision }, { $set: { activeRevision: revision } }, { new: true }
    ).lean().exec()
    if (!updated) conflict('The active policy revision has changed')
    await audit(ctx, 'policy.activated', `${project}@${revision}`, { previousRevision: expectedRevision })
    ctx.body = { project, revision }
  })

  router.get('/projects/:key/policies/active', authenticate('operator'), async (ctx) => {
    const project = validateSegment(ctx.params.key, 'project')
    const current = await Project.findOne({ key: project }).lean().exec()
    if (!current?.activeRevision) ctx.throw(404, 'No active policy', { code: 'NOT_FOUND' })
    const policy = await ProjectPolicyRevision.findOne({ project, revision: current.activeRevision }).lean().exec()
    if (!policy) ctx.throw(503, 'Active policy missing', { code: 'POLICY_MISSING' })
    ctx.body = { project, revision: policy.revision, targets: policy.targets }
  })

  router.get('/projects/:key/policies/:revision', authenticate('operator'), async (ctx) => {
    const project = validateSegment(ctx.params.key, 'project')
    const revision = ctx.params.revision
    const policy = await ProjectPolicyRevision.findOne({ project, revision }).lean().exec()
    if (!policy) ctx.throw(404, 'Policy revision not found', { code: 'NOT_FOUND' })
    ctx.body = { project, revision: policy.revision, targets: policy.targets }
  })

  return router
}

module.exports = { createPlatformRouter, json }
