'use strict'

const StorageDriver = require('./storageDriver')
const { LocalStorageDriver, validateSegment } = require('./localStorageDriver')
const { S3StorageDriver } = require('./s3StorageDriver')

function createStorageDriver(type = process.env.STORAGE_DRIVER || 'local', options = {}) {
  const normalized = (type || '').toLowerCase()
  if (normalized === 's3' || normalized === 'minio' || normalized === 'oss') {
    return new S3StorageDriver(options)
  }
  return new LocalStorageDriver(options.root || options.storageRoot || process.env.BINARY_STORAGE_ROOT || '.binary')
}

module.exports = {
  StorageDriver,
  LocalStorageDriver,
  S3StorageDriver,
  createStorageDriver,
  validateSegment,
}
