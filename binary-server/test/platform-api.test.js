'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs/promises')
const os = require('os')
const path = require('path')
const mongoose = require('mongoose')

const { createApp } = require('../app')
const { loadConfig } = require('../server/config')
const Release = require('../server/models/release')
const BuildJob = require('../server/models/build_job')
const Component = require('../server/models/component')
const Project = require('../server/models/project')
const ProjectPolicyRevision = require('../server/models/project_policy')
const AuditEvent = require('../server/models/audit_event')

const operatorToken = 'o'.repeat(48)
const agentToken = 'a'.repeat(48)
const commit = 'f'.repeat(40)

function query(value) {
  return { lean() { return this }, async exec() { return typeof value === 'function' ? value() : value } }
}

function stub(model, method, replacement, restore) {
  const original = model[method]
  model[method] = replacement
  restore.push(() => { model[method] = original })
}

test('paired release stays hidden until both attested specs and staged ZIP are verified', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'imy-platform-api-'))
  const releaseId = new mongoose.Types.ObjectId()
  const jobId = new mongoose.Types.ObjectId()
  let release
  let artifact
  let job
  const actions = []
  const restore = []
  let server
  try {
    stub(Release, 'findOne', (filter) => query(() => release?.name === filter.name &&
      release?.version === filter.version && (!filter.status || filter.status === release.status) ? release : null), restore)
    stub(Release, 'findById', (id) => query(() => String(id) === String(releaseId) ? release : null), restore)
    stub(Release, 'create', async (input) => { release = {
      ...input, _id: releaseId, status: 'requested', sourceSpecCommit: null, binarySpecCommit: null,
    }; return release }, restore)
    stub(Release, 'updateOne', (filter, update) => query(() => {
      if (String(filter._id) !== String(releaseId) || release.status !== filter.status) return { modifiedCount: 0 }
      if (filter.sourceSpecCommit !== undefined && release.sourceSpecCommit !== filter.sourceSpecCommit) return { modifiedCount: 0 }
      if (filter.binarySpecCommit !== undefined && release.binarySpecCommit !== filter.binarySpecCommit) return { modifiedCount: 0 }
      Object.assign(release, update.$set)
      return { modifiedCount: 1 }
    }), restore)

    stub(BuildJob, 'updateOne', (filter, update) => query(() => {
      if (!job && update.$setOnInsert) job = { _id: jobId, releaseId, status: 'queued', attempts: 0 }
      if (job && update.$set) Object.assign(job, update.$set)
      return { modifiedCount: 1 }
    }), restore)
    stub(BuildJob, 'findOneAndUpdate', (_filter, update) => query(() => {
      if (!job || job.status !== 'queued') return null
      Object.assign(job, update.$set)
      job.attempts += 1
      return job
    }), restore)
    stub(BuildJob, 'findOne', (filter) => query(() => {
      if (!job || (filter._id && String(filter._id) !== String(jobId)) ||
          String(filter.releaseId ?? releaseId) !== String(releaseId) ||
          filter.leaseId !== job.leaseId || job.status !== filter.status ||
          job.leaseExpiresAt <= new Date()) return null
      return job
    }), restore)
    stub(Component, 'findOne', (filter) => query(() => {
      if (!artifact || filter.name !== artifact.name || filter.version !== artifact.version ||
          (filter.status && filter.status !== artifact.status) ||
          (filter.managedReleaseId && String(filter.managedReleaseId) !== String(artifact.managedReleaseId))) return null
      return artifact
    }), restore)
    stub(Component, 'create', async (input) => { artifact = { ...input, _id: new mongoose.Types.ObjectId() }; return artifact }, restore)
    stub(AuditEvent, 'create', async (input) => { actions.push(input.action); return input }, restore)

    const config = loadConfig({ PLATFORM_API_ENABLED: 'true', PLATFORM_API_TOKEN: operatorToken,
      PLATFORM_AGENT_TOKEN: agentToken, BINARY_STORAGE_ROOT: root })
    server = createApp(config).listen(0, '127.0.0.1')
    await new Promise((resolve) => server.once('listening', resolve))
    const base = `http://127.0.0.1:${server.address().port}`
    async function post(url, token, body, lease) {
      return fetch(`${base}${url}`, { method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', ...(lease ? { 'x-job-lease': lease } : {}) },
        body: JSON.stringify(body),
      })
    }
    const requested = await post('/api/v1/releases', operatorToken,
      { name: 'DemoPod', version: '1.0.0', sourceCommit: commit })
    assert.equal(requested.status, 202)
    const duplicate = await post('/api/v1/releases', operatorToken,
      { name: 'DemoPod', version: '1.0.0', sourceCommit: commit })
    assert.equal(duplicate.status, 202)
    assert.equal(actions.filter((action) => action === 'release.requested').length, 1)

    const claimed = await post('/api/v1/jobs/claim', agentToken, { agentId: 'mac-1' })
    assert.equal(claimed.status, 200)
    const { leaseId } = await claimed.json()
    const zipURL = `${base}/api/v1/artifacts/DemoPod/1.0.0/zip`
    const before = await fetch(zipURL, { headers: { authorization: `Bearer ${operatorToken}` } })
    assert.equal(before.status, 404)

    const form = new FormData()
    const bytes = Buffer.from('PK\x03\x04demo-archive')
    form.append('file', new Blob([bytes], { type: 'application/zip' }), 'DemoPod.zip')
    const staged = await fetch(`${base}/api/v1/releases/${releaseId}/artifact`, {
      method: 'POST', headers: { authorization: `Bearer ${agentToken}`, 'x-job-lease': leaseId }, body: form,
    })
    assert.equal(staged.status, 201)
    const source = await post(`/api/v1/releases/${releaseId}/steps`, agentToken,
      { step: 'source', specCommit: '1'.repeat(40) }, leaseId)
    assert.equal(source.status, 200)
    const premature = await post(`/api/v1/jobs/${jobId}/finish`, agentToken, { success: true }, leaseId)
    assert.equal(premature.status, 409)
    assert.equal(release.status, 'requested')

    const binary = await post(`/api/v1/releases/${releaseId}/steps`, agentToken,
      { step: 'binary', specCommit: '2'.repeat(40) }, leaseId)
    assert.equal(binary.status, 200)
    const badSha = artifact.sha256
    artifact.sha256 = '0'.repeat(64)
    const mismatch = await post(`/api/v1/jobs/${jobId}/finish`, agentToken, { success: true }, leaseId)
    assert.equal(mismatch.status, 409)
    assert.equal(release.status, 'requested')
    artifact.sha256 = badSha
    const finished = await post(`/api/v1/jobs/${jobId}/finish`, agentToken, { success: true }, leaseId)
    assert.equal(finished.status, 200)
    assert.equal(release.status, 'active')
    const download = await fetch(zipURL, { headers: { authorization: `Bearer ${operatorToken}` } })
    assert.equal(download.status, 200)
    assert.deepEqual(Buffer.from(await download.arrayBuffer()), bytes)
    assert.equal(actions.filter((action) => action === 'release.activated').length, 1)
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve))
    restore.reverse().forEach((fn) => fn())
    await fs.rm(root, { recursive: true, force: true })
  }
})


test('policy activation is optimistic and only accepts an active paired release', async () => {
  const restore = []
  let server
  let project
  let policy
  const actions = []
  try {
    stub(Release, 'exists', async (filter) => filter.name === 'Foo' && filter.version === '1.0.0' && filter.status === 'active', restore)
    stub(Project, 'updateOne', (filter) => query(() => {
      project ||= { key: filter.key, activeRevision: null }
      return { modifiedCount: 1 }
    }), restore)
    stub(Project, 'findOneAndUpdate', (filter, update) => query(() => {
      if (filter.activeRevision !== project?.activeRevision) return null
      project.activeRevision = update.$set.activeRevision
      return project
    }), restore)
    stub(Project, 'findOne', (filter) => query(() => filter.key === project?.key ? project : null), restore)
    stub(ProjectPolicyRevision, 'create', async (input) => { policy = input; return policy }, restore)
    stub(ProjectPolicyRevision, 'findOne', (filter) => query(() =>
      filter.project === policy?.project && filter.revision === policy?.revision ? policy : null), restore)
    stub(AuditEvent, 'create', async (input) => { actions.push(input.action); return input }, restore)

    const config = loadConfig({ PLATFORM_API_ENABLED: 'true', PLATFORM_API_TOKEN: operatorToken,
      PLATFORM_AGENT_TOKEN: agentToken })
    server = createApp(config).listen(0, '127.0.0.1')
    await new Promise((resolve) => server.once('listening', resolve))
    const base = `http://127.0.0.1:${server.address().port}/api/v1/projects/SampleApp/policies`
    const post = (suffix, body) => fetch(base + suffix, { method: 'POST',
      headers: { authorization: `Bearer ${operatorToken}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
    const draft = await post('', { targets: [{ name: 'App', dependencies: [
      { name: 'Foo', version: '1.0.0', mode: 'binary' },
    ] }] })
    assert.equal(draft.status, 201)
    const { revision } = await draft.json()
    const activated = await post('/activate', { revision, expectedRevision: null })
    assert.equal(activated.status, 200)
    const conflict = await post('/activate', { revision, expectedRevision: null })
    assert.equal(conflict.status, 409)
    const current = await fetch(base + '/active', { headers: { authorization: `Bearer ${operatorToken}` } })
    assert.equal(current.status, 200)
    assert.equal((await current.json()).revision, revision)
    const unavailable = await post('', { targets: [{ name: 'App', dependencies: [
      { name: 'Unknown', version: '1.0.0', mode: 'source' },
    ] }] })
    assert.equal(unavailable.status, 409)
    assert.deepEqual(actions, ['policy.created', 'policy.activated'])
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve))
    restore.reverse().forEach((fn) => fn())
  }
})
