'use strict'

const crypto = require('crypto')

const DEFAULT_SIGNING_SECRET = process.env.LICENSE_SIGNING_SECRET || 'imybin-enterprise-license-secret-key-2026'

const TIER_FEATURES = {
  community: ['local_storage', 'cli_switch', 'basic_archive'],
  pro: ['local_storage', 's3_storage', 'cli_switch', 'basic_archive', 'policy_sync', 'roi_telemetry'],
  enterprise: [
    'local_storage',
    's3_storage',
    'cli_switch',
    'basic_archive',
    'policy_sync',
    'roi_telemetry',
    'sso_rbac',
    'remote_build_farm',
    'quality_gates',
    'audit_log',
  ],
}

function generateLicenseKey(payload, secret = DEFAULT_SIGNING_SECRET) {
  const normalized = {
    org: String(payload.org || 'Default Org'),
    tier: ['community', 'pro', 'enterprise'].includes(payload.tier) ? payload.tier : 'enterprise',
    seats: Number(payload.seats || 50),
    expiresAt: payload.expiresAt || new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
    issuedAt: payload.issuedAt || new Date().toISOString(),
  }
  const encodedPayload = Buffer.from(JSON.stringify(normalized), 'utf8').toString('base64url')
  const signature = crypto.createHmac('sha256', secret).update(encodedPayload, 'utf8').digest('base64url')
  return `IMYLIC.${encodedPayload}.${signature}`
}

function verifyLicenseKey(licenseKey, secret = DEFAULT_SIGNING_SECRET, now = new Date()) {
  if (!licenseKey || typeof licenseKey !== 'string' || !licenseKey.startsWith('IMYLIC.')) {
    return {
      valid: false,
      tier: 'community',
      reason: 'Missing or malformed license key prefix',
      features: TIER_FEATURES.community,
    }
  }
  const parts = licenseKey.split('.')
  if (parts.length !== 3) {
    return {
      valid: false,
      tier: 'community',
      reason: 'Invalid license key structure',
      features: TIER_FEATURES.community,
    }
  }

  const [, encodedPayload, providedSig] = parts
  const expectedSig = crypto.createHmac('sha256', secret).update(encodedPayload, 'utf8').digest('base64url')

  const a = Buffer.from(providedSig)
  const b = Buffer.from(expectedSig)
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return {
      valid: false,
      tier: 'community',
      reason: 'License signature verification failed',
      features: TIER_FEATURES.community,
    }
  }

  try {
    const payload = JSON.parse(Buffer.from(encodedPayload, 'base64url').toString('utf8'))
    const expiresAt = new Date(payload.expiresAt)
    if (Number.isNaN(expiresAt.getTime()) || expiresAt <= now) {
      return {
        valid: false,
        tier: 'community',
        org: payload.org,
        expiresAt: payload.expiresAt,
        reason: 'License has expired',
        features: TIER_FEATURES.community,
      }
    }
    const tier = TIER_FEATURES[payload.tier] ? payload.tier : 'community'
    return {
      valid: true,
      org: payload.org,
      tier,
      seats: payload.seats,
      expiresAt: payload.expiresAt,
      issuedAt: payload.issuedAt,
      features: TIER_FEATURES[tier],
    }
  } catch {
    return {
      valid: false,
      tier: 'community',
      reason: 'Invalid license payload JSON',
      features: TIER_FEATURES.community,
    }
  }
}

module.exports = {
  TIER_FEATURES,
  generateLicenseKey,
  verifyLicenseKey,
}
