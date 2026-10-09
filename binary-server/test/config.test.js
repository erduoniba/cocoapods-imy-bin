const test = require('node:test')
const assert = require('node:assert/strict')

const { loadConfig } = require('../server/config')

test('loads explicit production configuration', () => {
  const config = loadConfig({
    NODE_ENV: 'production',
    BINARY_SERVER_TOKEN: 'a-secure-token-that-is-longer-than-32-characters',
    MONGODB_URI: 'mongodb://127.0.0.1:27017/binary_database',
    PORT: '9192',
    MAX_UPLOAD_BYTES: '1024',
    BINARY_STORAGE_ROOT: '/tmp/binary-server-test',
  })

  assert.equal(config.port, 9192)
  assert.equal(config.maxUploadBytes, 1024)
  assert.equal(config.host, '127.0.0.1')
})

test('rejects a production configuration without a secure token', () => {
  assert.throws(
    () => loadConfig({ NODE_ENV: 'production' }),
    /BINARY_SERVER_TOKEN/
  )
})

test('rejects invalid MongoDB URLs and numeric values', () => {
  assert.throws(
    () => loadConfig({ MONGODB_URI: 'https://example.com/database' }),
    /MONGODB_URI/
  )
  assert.throws(
    () => loadConfig({ PORT: '0' }), /PORT/)
})
