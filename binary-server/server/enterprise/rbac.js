'use strict'

const crypto = require('crypto')

const ROLE_PERMISSIONS = {
  developer: ['artifact:read', 'policy:read', 'telemetry:write', 'quality:check'],
  maintainer: [
    'artifact:read',
    'artifact:publish',
    'policy:read',
    'telemetry:write',
    'quality:check',
    'job:enqueue',
  ],
  architect: [
    'artifact:read',
    'artifact:publish',
    'policy:read',
    'policy:write',
    'policy:activate',
    'telemetry:read',
    'telemetry:write',
    'quality:check',
    'job:enqueue',
    'audit:read',
  ],
  admin: ['*'],
}

function hasPermission(role, permission) {
  const perms = ROLE_PERMISSIONS[role] || []
  return perms.includes('*') || perms.includes(permission)
}

function issueSsoSessionToken({ email, role = 'developer', provider = 'oidc' }, secret = 'imybin-sso-secret') {
  if (!email || typeof email !== 'string' || !email.includes('@')) {
    throw new Error('A valid enterprise email is required for SSO exchange')
  }
  const normalizedRole = ROLE_PERMISSIONS[role] ? role : 'developer'
  const payload = {
    sub: email,
    role: normalizedRole,
    provider,
    exp: Date.now() + 8 * 3600 * 1000,
  }
  const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url')
  const sig = crypto.createHmac('sha256', secret).update(encoded, 'utf8').digest('base64url')
  return {
    token: `IMYSSO.${encoded}.${sig}`,
    actor: email,
    role: normalizedRole,
    permissions: ROLE_PERMISSIONS[normalizedRole],
    expiresAt: new Date(payload.exp).toISOString(),
  }
}

function verifySsoSessionToken(token, secret = 'imybin-sso-secret') {
  if (!token || typeof token !== 'string' || !token.startsWith('IMYSSO.')) {
    return null
  }
  const parts = token.split('.')
  if (parts.length !== 3) return null
  const [, encoded, sig] = parts
  const expected = crypto.createHmac('sha256', secret).update(encoded, 'utf8').digest('base64url')
  const a = Buffer.from(sig)
  const b = Buffer.from(expected)
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null

  try {
    const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'))
    if (payload.exp <= Date.now()) return null
    return payload
  } catch {
    return null
  }
}

module.exports = {
  ROLE_PERMISSIONS,
  hasPermission,
  issueSsoSessionToken,
  verifySsoSessionToken,
}
