const test = require('node:test')
const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const fs = require('node:fs/promises')
const os = require('node:os')
const path = require('node:path')

const { createStorage, validateSegment } = require('../server/utils/dir')

test('rejects traversal and unsupported component identifiers', () => {
  assert.equal(validateSegment('IMY-Core_1.0', 'name'), 'IMY-Core_1.0')
  assert.throws(() => validateSegment('../secrets', 'name'), /INVALID_COMPONENT_IDENTIFIER|name must/)
  assert.throws(() => validateSegment('contains/slash', 'name'), /INVALID_COMPONENT_IDENTIFIER|name must/)
  assert.throws(() => validateSegment('', 'version'), /INVALID_COMPONENT_IDENTIFIER|version must/)
})

test('stores an artifact in one version directory and preserves another version', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'binary-server-storage-'))
  const storage = createStorage(root)
  const uploadDirectory = await storage.createUploadDirectory()
  const uploadPath = path.join(uploadDirectory, storage.createTemporaryFilename())
  const contents = Buffer.from('binary-artifact')

  try {
    await fs.writeFile(uploadPath, contents)
    const sha256 = await storage.calculateSha256(uploadPath)
    const artifact = await storage.storeArtifact(uploadPath, 'Core', '1.0.0')
    const otherVersion = storage.componentDirectory('Core', '2.0.0')

    await fs.mkdir(otherVersion, { recursive: true })
    await fs.writeFile(path.join(otherVersion, 'artifact.zip'), 'newer-artifact')

    assert.equal(sha256, crypto.createHash('sha256').update(contents).digest('hex'))
    assert.equal(await storage.findArtifact('Core', '1.0.0'), artifact)

    await storage.removeComponentVersion('Core', '1.0.0')

    await assert.rejects(fs.access(artifact))
    await fs.access(path.join(otherVersion, 'artifact.zip'))
  } finally {
    await fs.rm(root, { recursive: true, force: true })
  }
})

test('returns no artifact when a component directory is missing', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'binary-server-storage-'))
  const storage = createStorage(root)

  try {
    assert.equal(await storage.findArtifact('Missing', '1.0.0'), null)
  } finally {
    await fs.rm(root, { recursive: true, force: true })
  }
})

test('s3 storage driver stores artifacts and generates presigned download urls', async () => {
  const s3 = createStorage(null, {
    type: 's3',
    endpoint: 'https://oss-cn-hangzhou.aliyuncs.com',
    bucket: 'test-bucket',
  })

  await s3.ensureStorageRoot()
  const uploadDir = await s3.createUploadDirectory()
  const filename = path.join(uploadDir, s3.createTemporaryFilename())
  await fs.writeFile(filename, 's3-content')

  try {
    assert.equal(s3.isZipFilename('package.zip'), true)
    assert.equal(s3.isZipFilename('package.tar.gz'), false)

    const uri = await s3.storeArtifact(filename, 'MyPod', '0.1.0')
    assert.equal(uri, 's3://test-bucket/MyPod/0.1.0/artifact.zip')

    const found = await s3.findArtifact('MyPod', '0.1.0')
    assert.equal(found, filename)

    const url = s3.getPresignedDownloadUrl('MyPod', '0.1.0')
    assert.match(url, /^https:\/\/oss-cn-hangzhou\.aliyuncs\.com\/test-bucket\/MyPod\/0\.1\.0\/artifact\.zip/)

    await s3.removeComponentVersion('MyPod', '0.1.0')
    assert.equal(await s3.findArtifact('MyPod', '0.1.0'), null)
  } finally {
    await fs.rm(uploadDir, { recursive: true, force: true })
  }
})
