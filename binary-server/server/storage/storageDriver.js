'use strict'

class StorageDriver {
  async ensureStorageRoot() {
    throw new Error('ensureStorageRoot must be implemented')
  }

  async createUploadDirectory() {
    throw new Error('createUploadDirectory must be implemented')
  }

  createTemporaryFilename() {
    throw new Error('createTemporaryFilename must be implemented')
  }

  isZipFilename(_filename) {
    throw new Error('isZipFilename must be implemented')
  }

  async calculateSha256(_filename) {
    throw new Error('calculateSha256 must be implemented')
  }

  async storeArtifact(_uploadPath, _name, _version) {
    throw new Error('storeArtifact must be implemented')
  }

  async removeFile(_filename) {
    throw new Error('removeFile must be implemented')
  }

  async removeComponentVersion(_name, _version) {
    throw new Error('removeComponentVersion must be implemented')
  }

  async findArtifact(_name, _version) {
    throw new Error('findArtifact must be implemented')
  }
}

module.exports = StorageDriver
