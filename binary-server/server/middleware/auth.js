const crypto = require('crypto')

function getBearerToken(header) {
  const match = /^Bearer\s+(.+)$/i.exec(header || '')
  return match ? match[1] : ''
}

function tokensMatch(actual, expected) {
  const actualBuffer = Buffer.from(actual)
  const expectedBuffer = Buffer.from(expected)
  return actualBuffer.length === expectedBuffer.length && crypto.timingSafeEqual(actualBuffer, expectedBuffer)
}

function createMutationAuthenticator(config) {
  return async (ctx, next) => {
    if (!config.apiToken) {
      await next()
      return
    }

    const providedToken = getBearerToken(ctx.get('authorization')) || ctx.get('x-binary-server-token')
    if (!tokensMatch(providedToken, config.apiToken)) {
      ctx.throw(401, 'A valid API token is required for this operation', {
        code: 'UNAUTHORIZED',
      })
    }
    await next()
  }
}

module.exports = {
  createMutationAuthenticator,
  getBearerToken,
  tokensMatch,
}
