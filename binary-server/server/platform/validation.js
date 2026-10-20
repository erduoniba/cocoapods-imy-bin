'use strict'

const { validateSegment } = require('../utils/dir')
const commitPattern = /^[a-f0-9]{40}$/

function invalid(message) {
  const error = new Error(message)
  error.status = 400
  error.code = 'INVALID_PLATFORM_INPUT'
  throw error
}

function conflict(message) {
  const error = new Error(message)
  error.status = 409
  error.code = 'PLATFORM_CONFLICT'
  throw error
}

function validateCommit(value) {
  if (typeof value !== 'string' || !commitPattern.test(value)) {
    invalid('A full lowercase 40-character Git commit SHA is required')
  }
  return value
}

function validateRelease(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) invalid('JSON object required')
  return {
    name: validateSegment(body.name, 'name'),
    version: validateSegment(body.version, 'version'),
    sourceCommit: validateCommit(body.sourceCommit),
  }
}

function validatePolicy(body) {
  if (!body || !Array.isArray(body.targets) || body.targets.length === 0 || body.targets.length > 100) {
    invalid('targets must be a nonempty array (at most 100)')
  }
  const componentSelections = new Map()
  const targets = body.targets.map((target) => {
    const name = validateSegment(target?.name, 'target')
    if (!Array.isArray(target.dependencies) || target.dependencies.length > 500) {
      invalid('dependencies must be an array (at most 500)')
    }
    const names = new Set()
    const dependencies = target.dependencies.map((dependency) => {
      const component = validateSegment(dependency?.name, 'component')
      const version = validateSegment(dependency?.version, 'version')
      if (names.has(component)) invalid(`duplicate dependency: ${component}`)
      names.add(component)
      if (!['source', 'binary'].includes(dependency?.mode)) invalid('mode must be source or binary')
      const selection = `${version}:${dependency.mode}`
      if (componentSelections.has(component) && componentSelections.get(component) !== selection) {
        invalid(`${component} has conflicting versions or modes across targets`)
      }
      componentSelections.set(component, selection)
      return { name: component, version, mode: dependency.mode }
    })
    return { name, dependencies }
  })
  if (new Set(targets.map((target) => target.name)).size !== targets.length) invalid('duplicate targets')
  return targets
}

module.exports = { conflict, invalid, validateCommit, validatePolicy, validateRelease }
