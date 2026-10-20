'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')

const { loadConfig } = require('../server/config')
const { validateRelease, validatePolicy } = require('../server/platform/validation')
const { verifyActivation, visibleManagedArtifact } = require('../server/platform/workflow')
const { createApp } = require('../app')

const platformToken = 'p'.repeat(48)
const agentToken = 'a'.repeat(48)

function platformConfig() {
  return loadConfig({ PLATFORM_API_ENABLED: 'true', PLATFORM_API_TOKEN: platformToken, PLATFORM_AGENT_TOKEN: agentToken })
}

test('platform API is opt-in and fails closed in production without OIDC', () => {
  assert.equal(loadConfig({}).platformEnabled, false)
  assert.throws(() => loadConfig({ PLATFORM_API_ENABLED: 'true' }), /PLATFORM_API_TOKEN/)
  assert.throws(() => loadConfig({
    PLATFORM_API_ENABLED: 'true', PLATFORM_API_TOKEN: platformToken, PLATFORM_AGENT_TOKEN: platformToken,
  }), /distinct/)
  assert.throws(() => loadConfig({
    NODE_ENV: 'production', PLATFORM_API_ENABLED: 'true', PLATFORM_API_TOKEN: platformToken,
    PLATFORM_AGENT_TOKEN: agentToken, BINARY_SERVER_TOKEN: 'l'.repeat(48),
  }), /not production-ready/)
})

test('untrusted callers cannot reach platform routes or legacy mutation routes', async () => {
  const server = createApp(platformConfig()).listen(0, '127.0.0.1')
  try {
    await new Promise((resolve) => server.once('listening', resolve))
    const base = `http://127.0.0.1:${server.address().port}`
    const noToken = await fetch(`${base}/api/v1/releases`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })
    assert.equal(noToken.status, 401)
    const wrongRole = await fetch(`${base}/api/v1/jobs/claim`, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${platformToken}` },
      body: JSON.stringify({ agentId: 'agent-1' }),
    })
    assert.equal(wrongRole.status, 401)
    const legacy = await fetch(`${base}/frameworks`, { method: 'POST' })
    assert.notEqual(legacy.status, 201)
  } finally {
    await new Promise((resolve) => server.close(resolve))
  }
})

test('accepts paired release identifiers and rejects ambiguous managed policies', () => {
  assert.deepEqual(validateRelease({
    name: 'HDDynamicPod', version: '1.2.3', sourceCommit: 'a'.repeat(40),
  }), { name: 'HDDynamicPod', version: '1.2.3', sourceCommit: 'a'.repeat(40) })
  assert.throws(() => validateRelease({ name: 'Pod', version: '1', sourceCommit: 'A'.repeat(40) }), /lowercase/)
  assert.throws(() => validatePolicy({ targets: [
    { name: 'App', dependencies: [{ name: 'Pod', version: '1', mode: 'source' }, { name: 'Pod', version: '1', mode: 'binary' }] },
  ] }), /duplicate dependency/)
  assert.throws(() => validatePolicy({ targets: [{ name: 'App', dependencies: [] }, { name: 'App', dependencies: [] }] }), /duplicate targets/)
  assert.throws(() => validatePolicy({ targets: [
    { name: 'App', dependencies: [{ name: 'Pod', version: '1', mode: 'source' }] },
    { name: 'Other', dependencies: [{ name: 'Pod', version: '1', mode: 'binary' }] },
  ] }), /conflicting versions or modes/)
})

test('managed release stays invisible until both specs and artifact checksum pass', () => {
  const release = {
    _id: 'release-1', name: 'Pod', version: '1', status: 'requested',
    sourceSpecCommit: 'a'.repeat(40), binarySpecCommit: null,
  }
  const artifact = { managedReleaseId: 'release-1', status: 'staged', sha256: 'b'.repeat(64) }
  assert.equal(visibleManagedArtifact(release, artifact), false)
  assert.throws(() => verifyActivation(release, artifact, artifact.sha256), /Both spec repositories/)
  release.binarySpecCommit = 'c'.repeat(40)
  assert.throws(() => verifyActivation(release, artifact, 'd'.repeat(64)), /checksum mismatch/)
  assert.deepEqual(verifyActivation(release, artifact, artifact.sha256), {
    name: 'Pod', version: '1', sha256: artifact.sha256,
  })
  release.status = 'active'
  assert.equal(visibleManagedArtifact(release, artifact), true)
  assert.equal(visibleManagedArtifact(release, { ...artifact, managedReleaseId: 'other' }), false)
})
