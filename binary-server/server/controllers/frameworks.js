'use strict'

const fs = require('fs')

const Component = require('../models/component')
const { validateSegment } = require('../utils/dir')

function readyStatusFilter() {
  return {
    $or: [
      { status: 'ready' },
      { status: { $exists: false } },
    ],
  }
}

function validationError(message, code) {
  const error = new Error(message)
  error.status = 400
  error.code = code
  return error
}

function readField(ctx, field) {
  const value = ctx.request.body?.[field]
  return typeof value === 'string' ? value.trim() : ''
}

function readNames(ctx) {
  const rawNames = ctx.query.names ? ctx.query.names.split(',') : [ctx.params.name].filter(Boolean)
  return rawNames.map((name) => validateSegment(name, 'name'))
}

async function health(ctx) {
  const isReady = Component.db.readyState === 1
  ctx.status = isReady ? 200 : 503
  ctx.body = { status: isReady ? 'ok' : 'unavailable' }
}

async function show(ctx) {
  const names = readNames(ctx)
  const version = ctx.params.version ? validateSegment(ctx.params.version, 'version') : null
  const conditions = readyStatusFilter()

  if (names.length > 0) {
    conditions.name = names.length === 1 ? names[0] : { $in: names }
  }
  if (version) {
    conditions.version = version
  }

  const components = await Component.find(conditions)
    .select({ name: 1, version: 1 })
    .sort({ name: 1, version: -1 })
    .lean()
    .exec()

  ctx.body = components.reduce((result, component) => {
    result[component.name] ||= []
    result[component.name].push(component.version)
    return result
  }, {})
}

async function create(ctx) {
  const name = validateSegment(readField(ctx, 'name'), 'name')
  const version = validateSegment(readField(ctx, 'version'), 'version')
  const annotate = readField(ctx, 'annotate')
  const file = ctx.file

  if (!file || !ctx.storage.isZipFilename(file.originalname)) {
    throw validationError('A single .zip file is required', 'INVALID_UPLOAD')
  }
  if (annotate.length > 1_000) {
    throw validationError('annotate must not exceed 1000 characters', 'INVALID_ANNOTATE')
  }

  let component
  try {
    const sha256 = await ctx.storage.calculateSha256(file.path)
    component = await Component.create({
      name,
      version,
      annotate,
      sha256,
      size: file.size,
      status: 'pending',
    })
  } catch (error) {
    await ctx.storage.removeFile(file.path)
    if (error?.code === 11000) {
      ctx.throw(409, 'A binary artifact already exists for this component version', {
        code: 'COMPONENT_VERSION_EXISTS',
      })
    }
    throw error
  }

  try {
    await ctx.storage.storeArtifact(file.path, name, version)
    await Component.updateOne({ _id: component._id }, { $set: { status: 'ready' } }).exec()
  } catch (error) {
    await Component.deleteOne({ _id: component._id }).exec()
    await ctx.storage.removeFile(file.path)
    throw error
  }

  ctx.status = 201
  ctx.body = {
    name,
    version,
    sha256: component.sha256,
    size: component.size,
  }
}

async function destroy(ctx) {
  const name = validateSegment(ctx.params.name, 'name')
  const version = validateSegment(ctx.params.version, 'version')
  const component = await Component.findOneAndUpdate(
    { name, version, ...readyStatusFilter() },
    { $set: { status: 'deleting' } },
    { new: true }
  ).exec()

  if (!component) {
    ctx.throw(404, 'No binary artifact exists for this component version', {
      code: 'COMPONENT_VERSION_NOT_FOUND',
    })
  }

  try {
    await ctx.storage.removeComponentVersion(name, version)
    await Component.deleteOne({ _id: component._id }).exec()
  } catch (error) {
    await Component.updateOne({ _id: component._id }, { $set: { status: 'ready' } }).exec()
    throw error
  }

  ctx.status = 204
}

async function download(ctx) {
  const name = validateSegment(ctx.params.name, 'name')
  const version = validateSegment(ctx.params.version, 'version')
  const component = await Component.findOne({ name, version, ...readyStatusFilter() }).lean().exec()

  if (!component) {
    ctx.throw(404, 'No binary artifact exists for this component version', {
      code: 'COMPONENT_VERSION_NOT_FOUND',
    })
  }

  const artifact = await ctx.storage.findArtifact(name, version)
  if (!artifact) {
    ctx.throw(404, 'The component record exists but its artifact is unavailable', {
      code: 'ARTIFACT_NOT_FOUND',
    })
  }

  const metadata = await fs.promises.stat(artifact)
  ctx.type = 'application/zip'
  ctx.length = metadata.size
  ctx.body = fs.createReadStream(artifact)
}

module.exports = {
  create,
  destroy,
  download,
  health,
  show,
}
