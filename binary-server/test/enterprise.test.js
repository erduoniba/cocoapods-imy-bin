'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { generateLicenseKey, verifyLicenseKey } = require('../server/enterprise/license')
const { issueSsoSessionToken, verifySsoSessionToken, hasPermission } = require('../server/enterprise/rbac')
const { TelemetryAndQualityService } = require('../server/enterprise/telemetry')
const { computePolicyDiff } = require('../server/enterprise/dashboard')
const { ImyBuildAgent } = require('../bin/imy-build-agent')
const { S3StorageDriver } = require('../server/storage')

test('enterprise license key signs, verifies, and rejects tampered or expired keys', () => {
  const key = generateLicenseKey({
    org: 'Acme Mobile Team',
    tier: 'enterprise',
    seats: 120,
    expiresAt: new Date(Date.now() + 86400_000).toISOString(),
  })
  const verified = verifyLicenseKey(key)
  assert.equal(verified.valid, true)
  assert.equal(verified.org, 'Acme Mobile Team')
  assert.equal(verified.tier, 'enterprise')
  assert.ok(verified.features.includes('remote_build_farm'))

  const tampered = `${key}x`
  assert.equal(verifyLicenseKey(tampered).valid, false)

  const expiredKey = generateLicenseKey({
    org: 'Expired Corp',
    tier: 'pro',
    expiresAt: new Date(Date.now() - 86400_000).toISOString(),
  })
  assert.equal(verifyLicenseKey(expiredKey).valid, false)
})

test('enterprise SSO token exchange and RBAC permission matrix enforce roles', () => {
  const session = issueSsoSessionToken({ email: 'dev@imybin.org', role: 'developer' })
  assert.ok(session.token.startsWith('IMYSSO.'))
  const decoded = verifySsoSessionToken(session.token)
  assert.equal(decoded.sub, 'dev@imybin.org')
  assert.equal(decoded.role, 'developer')

  assert.equal(hasPermission('developer', 'artifact:read'), true)
  assert.equal(hasPermission('developer', 'policy:activate'), false)
  assert.equal(hasPermission('architect', 'policy:activate'), true)
  assert.equal(hasPermission('admin', 'any:permission'), true)
})

test('telemetry service computes ROI hours saved and evaluates quality gates', () => {
  const svc = new TelemetryAndQualityService()
  svc.recordInstallEvent({ project: 'HDImyBinApp', developer: 'alice', totalPods: 20, binaryHitPods: 18, durationSeconds: 12 })
  svc.recordInstallEvent({ project: 'HDImyBinApp', developer: 'bob', totalPods: 20, binaryHitPods: 20, durationSeconds: 8 })

  const roi = svc.getRoiSummary()
  assert.equal(roi.totalInstalls, 2)
  assert.equal(roi.averageHitRatePercent, 95)
  assert.ok(roi.totalSavedSeconds > 0)

  const failedGate = svc.evaluateArtifactQualityGate({
    name: 'HDStaticPod',
    version: '0.2.0',
    previousSizeBytes: 100_000,
    currentSizeBytes: 150_000, // +50% growth > 20% limit
    exportedSymbols: ['_OBJC_CLASS_$_Foo', '_OBJC_CLASS_$_Foo'],
    hasPrivacyManifest: false,
  })
  assert.equal(failedGate.passed, false)
  assert.equal(failedGate.issues.length, 3)

  const passedGate = svc.evaluateArtifactQualityGate({
    name: 'HDStaticPod',
    version: '0.2.1',
    previousSizeBytes: 100_000,
    currentSizeBytes: 105_000,
    exportedSymbols: ['_OBJC_CLASS_$_Foo', '_OBJC_CLASS_$_Bar'],
    hasPrivacyManifest: true,
  })
  assert.equal(passedGate.passed, true)
})

test('policy diff engine detects added, removed, and modified dependencies across targets', () => {
  const before = [
    {
      name: 'HDImyBinApp',
      dependencies: [
        { name: 'HDStaticPod', version: '0.1.10', mode: 'binary' },
        { name: 'LegacyPod', version: '1.0.0', mode: 'source' },
      ],
    },
  ]
  const after = [
    {
      name: 'HDImyBinApp',
      dependencies: [
        { name: 'HDStaticPod', version: '0.1.11', mode: 'binary' },
        { name: 'HDDynamicPod', version: '0.2.0', mode: 'binary' },
      ],
    },
  ]
  const diff = computePolicyDiff(before, after)
  assert.equal(diff.length, 3)
  assert.deepEqual(
    diff.map((d) => `${d.name}:${d.change}`),
    ['HDDynamicPod:added', 'HDStaticPod:modified', 'LegacyPod:removed']
  )
})

test('S3 storage driver computes AWS Signature V4 presigned download URL and Build Agent claims jobs', async () => {
  const s3 = new S3StorageDriver({
    endpoint: 'https://s3.example.com',
    bucket: 'imybin-prod',
    region: 'ap-east-1',
    accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
    secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  })
  const url = s3.getPresignedDownloadUrl('HDStaticPod', '0.1.11', 3600, new Date('2026-10-20T12:00:00Z'))
  assert.ok(url.includes('X-Amz-Algorithm=AWS4-HMAC-SHA256'))
  assert.ok(url.includes('X-Amz-Signature='))

  let calledUrl = ''
  const agent = new ImyBuildAgent({
    serverUrl: 'http://127.0.0.1:8080',
    agentToken: 'secret-agent-token',
    agentId: 'mac-mini-01',
    fetchImpl: async (u) => {
      calledUrl = u
      return {
        status: 200,
        ok: true,
        json: async () => ({ jobId: 'job-1', leaseId: 'lease-1', release: { name: 'HDStaticPod', version: '0.1.11' } }),
      }
    },
  })
  const claimed = await agent.claimNextJob()
  assert.equal(calledUrl, 'http://127.0.0.1:8080/api/v1/jobs/claim')
  assert.equal(claimed.jobId, 'job-1')
})
