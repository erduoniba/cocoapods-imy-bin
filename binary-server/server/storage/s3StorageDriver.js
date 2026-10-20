'use strict'

const crypto = require('crypto')
const fs = require('fs/promises')
const path = require('path')
const os = require('os')
const StorageDriver = require('./storageDriver')
const { validateSegment } = require('./localStorageDriver')

function hmac(key, data, encoding) {
  return crypto.createHmac('sha256', key).update(data, 'utf8').digest(encoding)
}

function sha256Hex(data) {
  return crypto.createHash('sha256').update(data, 'utf8').digest('hex')
}

function deriveSigningKey(secretAccessKey, dateStamp, region, service = 's3') {
  const kDate = hmac(`AWS4${secretAccessKey}`, dateStamp)
  const kRegion = hmac(kDate, region)
  const kService = hmac(kRegion, service)
  return hmac(kService, 'aws4_request')
}

class S3StorageDriver extends StorageDriver {
  constructor(options = {}) {
    super()
    this.endpoint = (options.endpoint || process.env.S3_ENDPOINT || 'http://127.0.0.1:9000').replace(/\/+$/, '')
    this.bucket = options.bucket || process.env.S3_BUCKET || 'binary-artifacts'
    this.region = options.region || process.env.S3_REGION || 'us-east-1'
    this.accessKeyId = options.accessKeyId || process.env.S3_ACCESS_KEY || 'minioadmin'
    this.secretAccessKey = options.secretAccessKey || process.env.S3_SECRET_KEY || 'minioadmin'
    this.tempRoot = options.tempRoot || path.join(os.tmpdir(), '.s3-uploads')
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

  getPresignedDownloadUrl(name, version, expiresIn = 3600, now = new Date()) {
    const key = this.artifactKey(name, version)
    const iso = now.toISOString().replace(/[:-]|\.\d{3}/g, '')
    const dateStamp = iso.slice(0, 8)
    const credentialScope = `${dateStamp}/${this.region}/s3/aws4_request`
    const credential = `${this.accessKeyId}/${credentialScope}`

    const parsedUrl = new URL(`${this.endpoint}/${this.bucket}/${key}`)
    const queryParams = new URLSearchParams({
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': credential,
      'X-Amz-Date': iso,
      'X-Amz-Expires': String(expiresIn),
      'X-Amz-SignedHeaders': 'host',
    })
    queryParams.sort()

    const canonicalRequest = [
      'GET',
      parsedUrl.pathname,
      queryParams.toString(),
      `host:${parsedUrl.host}\n`,
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n')

    const stringToSign = [
      'AWS4-HMAC-SHA256',
      iso,
      credentialScope,
      sha256Hex(canonicalRequest),
    ].join('\n')

    const signingKey = deriveSigningKey(this.secretAccessKey, dateStamp, this.region, 's3')
    const signature = hmac(signingKey, stringToSign, 'hex')
    queryParams.set('X-Amz-Signature', signature)

    return `${parsedUrl.origin}${parsedUrl.pathname}?${queryParams.toString()}`
  }
}

module.exports = {
  S3StorageDriver,
}
