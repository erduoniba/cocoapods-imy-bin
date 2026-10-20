'use strict'

const crypto = require('crypto')
const fs = require('fs/promises')
const path = require('path')
const os = require('os')
const StorageDriver = require('./storageDriver')
const { validateSegment } = require('./localStorageDriver')

class S3StorageDriver extends StorageDriver {
  constructor(options = {}) {
    super()
    this.endpoint = options.endpoint || process.env.S3_ENDPOINT || 'http://127.0.0.1:9000'
    this.bucket = options.bucket || process.env.S3_BUCKET || 'binary-artifacts'
    this.region = options.region || process.env.S3_REGION || 'us-east-1'
    this.accessKeyId = options.accessKeyId || process.env.S3_ACCESS_KEY || ''
    this.secretAccessKey = options.secretAccessKey || process.env.S3_SECRET_KEY || ''
    this.tempRoot = path.join(os.tmpdir(), '.s3-uploads')
    this.remoteIndex = new Map()
  }

  artifactKey(name, version) {
    return `${validateSegment(name, 'name')}/${validateSegment(version, 'version')}/artifact.zip`
  }

  componentDirectory(name, version) {
    return path.join(
      this.tempRoot,
      validateSegment(name, 'name'),
      validateSegment(version, 'version')
    )
  }

  async ensureStorageRoot() {
    await fs.mkdir(this.tempRoot, { recursive: true, mode: 0o700 })
  }

  async createUploadDirectory() {
    await fs.mkdir(this.tempRoot, { recursive: true, mode: 0o700 })
    return fs.mkdtemp(path.join(this.tempRoot, 's3-upload-'))
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
    const key = this.artifactKey(name, version)
    const sha256 = await this.calculateSha256(uploadPath)
    this.remoteIndex.set(key, { path: uploadPath, sha256, storedAt: new Date() })
    return `s3://${this.bucket}/${key}`
  }

  async removeFile(filename) {
    if (filename) {
      await fs.rm(filename, { force: true })
    }
  }

  async removeComponentVersion(name, version) {
    const key = this.artifactKey(name, version)
    this.remoteIndex.delete(key)
  }

  async findArtifact(name, version) {
    const key = this.artifactKey(name, version)
    const entry = this.remoteIndex.get(key)
    return entry ? entry.path : null
  }

  getPresignedDownloadUrl(name, version, expiresIn = 3600) {
    const key = this.artifactKey(name, version)
    return `${this.endpoint}/${this.bucket}/${key}?X-Amz-Expires=${expiresIn}`
  }
}

module.exports = {
  S3StorageDriver,
}
