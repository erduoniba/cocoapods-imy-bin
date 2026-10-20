const path = require('path')

function readPositiveInteger(value, fallback, field) {
  if (value === undefined || value === '') {
    return fallback
  }

  const parsed = Number.parseInt(value, 10)
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${field} must be a positive integer`)
  }
  return parsed
}

function loadConfig(environment = process.env) {
  const nodeEnv = environment.NODE_ENV || 'development'
  const apiToken = environment.BINARY_SERVER_TOKEN || ''
  const platformEnabled = environment.PLATFORM_API_ENABLED === 'true'
  const platformToken = environment.PLATFORM_API_TOKEN || ''
  const agentToken = environment.PLATFORM_AGENT_TOKEN || ''
  const mongodbUri = environment.MONGODB_URI || 'mongodb://127.0.0.1:27017/binary_database'

  if (!/^mongodb(\+srv)?:\/\//.test(mongodbUri)) {
    throw new Error('MONGODB_URI must use the mongodb:// or mongodb+srv:// scheme')
  }
  if (platformEnabled && (platformToken.length < 32 || agentToken.length < 32 || platformToken === agentToken)) {
    throw new Error('PLATFORM_API_TOKEN and PLATFORM_AGENT_TOKEN must be distinct and at least 32 characters')
  }
  if (platformEnabled && nodeEnv === 'production') {
    throw new Error('Platform API is not production-ready without OIDC and object storage')
  }
  if (nodeEnv === 'production' && apiToken.length < 32) {
    throw new Error('BINARY_SERVER_TOKEN must contain at least 32 characters in production')
  }

  return {
    nodeEnv,
    host: environment.HOST || '127.0.0.1',
    port: readPositiveInteger(environment.PORT, 8080, 'PORT'),
    mongodbUri,
    mongodbServerSelectionTimeoutMs: readPositiveInteger(
      environment.MONGODB_SERVER_SELECTION_TIMEOUT_MS,
      5_000,
      'MONGODB_SERVER_SELECTION_TIMEOUT_MS'
    ),
    storageRoot: path.resolve(environment.BINARY_STORAGE_ROOT || path.join(process.cwd(), '.binary')),
    maxUploadBytes: readPositiveInteger(environment.MAX_UPLOAD_BYTES, 500 * 1024 * 1024, 'MAX_UPLOAD_BYTES'),
    apiToken,
    platformEnabled,
    platformToken,
    agentToken,
  }
}

module.exports = {
  loadConfig,
}
