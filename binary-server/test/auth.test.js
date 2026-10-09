const test = require('node:test')
const assert = require('node:assert/strict')

const { getBearerToken, tokensMatch } = require('../server/middleware/auth')

test('extracts bearer tokens without accepting other schemes', () => {
  assert.equal(getBearerToken('Bearer token-value'), 'token-value')
  assert.equal(getBearerToken('bearer another-token'), 'another-token')
  assert.equal(getBearerToken('Basic credentials'), '')
  assert.equal(getBearerToken(''), '')
})

test('compares tokens without accepting different lengths', () => {
  assert.equal(tokensMatch('same-token', 'same-token'), true)
  assert.equal(tokensMatch('different-token', 'same-token'), false)
  assert.equal(tokensMatch('', 'same-token'), false)
})
