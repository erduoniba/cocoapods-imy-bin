'use strict'

const crypto = require('crypto')
const fs = require('fs/promises')
const path = require('path')
const StorageDriver = require('./storageDriver')

const segmentPattern = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/

function validateSegment(value, field) {
  if (typeof value !== 'string' || !segmentPattern.test(value)) {
    const error = new Error(`${field} must contain 1-128 letters, digits, dots, underscores, plus signs, or hyphens`)
    error.status = 400
    error.code = 'INVALID_COMPONENT_IDENTIFIER'
    throw error
  }
  return value
}

class LocalStorageDriver extends StorageDriver {
  constructor(root) {
    super()
    this.storageRoot = path.resolve(root)
    this.uploadRoot = path.join(this.storageRoot, '.uploads')
  }

  componentDirectory(name, version) {
    return path.join(
      this.storageRoot,
      validateSegment(name, 'name'),
      validateSegment(version, 'version')
    )
  }

  async ensureStorageRoot() {
    await fs.mkdir(this.uploadRoot, { recursive: true, mode: 0o700 })
  }

  async createUploadDirectory() {
    await fs.mkdir(this.uploadRoot, { recursive: true, mode: 0o700 })
    return fs.mkdtemp(path.join(this.uploadRoot, 'upload-'))
  }

  createTemporaryFilename() {
    return `${crypto.randomUUID()}.upload`
  }

  isZipFilename(filename) {
    return typeof filename === 'string' && path.extname(filename).toLowerCase() === '.zip'
  }

  async calculateSha256(filename) {
    const hash = crypto.createHash('sha256')
    const file = await fs.open(filename, 'r')
    try {
      for await (const chunk of file.createReadStream()) {
        hash.update(chunk)
      }
    } finally {
      await file.close()
    }
    return hash.digest('hex')
  }

  async storeArtifact(uploadPath, name, version) {
    const directory = this.componentDirectory(name, version)
    await fs.mkdir(path.dirname(directory), { recursive: true, mode: 0o750 })
    await fs.mkdir(directory, { recursive: false, mode: 0o750 })
    const artifact = path.join(directory, 'artifact.zip')

    try {
      await fs.rename(uploadPath, artifact)
      return artifact
    } catch (error) {
      await fs.rm(directory, { recursive: true, force: true })
      throw error
    }
  }

  async removeFile(filename) {
    if (filename) {
      await fs.rm(filename, { force: true })
    }
  }

  async removeComponentVersion(name, version) {
    await fs.rm(this.componentDirectory(name, version), { recursive: true, force: true })
  }

  async findArtifact(name, version) {
    const directory = this.componentDirectory(name, version)
    const standardArtifact = path.join(directory, 'artifact.zip')
    try {
      await fs.access(standardArtifact)
      return standardArtifact
    } catch {
      try {
        const files = await fs.readdir(directory, { withFileTypes: true })
        const legacyArtifact = files.find((file) => file.isFile() && this.isZipFilename(file.name))
        return legacyArtifact ? path.join(directory, legacyArtifact.name) : null
      } catch {
        return null
      }
    }
  }
}

module.exports = {
  LocalStorageDriver,
  validateSegment,
}
