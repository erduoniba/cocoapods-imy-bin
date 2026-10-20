'use strict'

const { createStorageDriver, validateSegment, LocalStorageDriver, S3StorageDriver } = require('../storage')

function createStorage(root, options = {}) {
  const driverType = options.type || process.env.STORAGE_DRIVER || 'local'
  return createStorageDriver(driverType, { root, ...options })
}

module.exports = {
  createStorage,
  validateSegment,
  LocalStorageDriver,
  S3StorageDriver,
}
