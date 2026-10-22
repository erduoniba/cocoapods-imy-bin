'use strict'

const mongoose = require('mongoose')
const ConfigTable = require('../models/config_table')
const AuditEvent = require('../models/audit_event')

function isDbConnected() {
  return mongoose.connection.readyState === 1
}

function normalizeDoc(doc) {
  if (!doc) return null
  const raw = typeof doc.toObject === 'function' ? doc.toObject() : { ...doc }
  delete raw._id
  delete raw.__v

  // Ensure columns is an array
  const columns = Array.isArray(raw.columns) ? raw.columns.map(col => {
    const colCopy = { ...col }
    delete colCopy._id
    if (colCopy.components) {
      colCopy.components = colCopy.components.map(c => {
        const cCopy = { ...c }
        delete cCopy._id
        return cCopy
      })
    }
    return colCopy
  }) : []

  // Ensure activeColumn
  const activeColName = raw.activeColumn || (columns[0] && columns[0].name) || '1.0.0'
  const activeCol = columns.find(c => c.name === activeColName) || columns[0]

  // Top level components mirrors active column
  const components = activeCol && activeCol.components ? activeCol.components : (raw.components || [])

  return {
    $schema: 'https://imybin.org/schemas/imy-bin-config.schema.json',
    version: raw.version || 1,
    project: raw.project,
    environment: raw.environment || 'dev',
    defaultMode: raw.defaultMode || 'binary',
    updatedAt: (raw.updatedAt ? new Date(raw.updatedAt) : new Date()).toISOString(),
    activeColumn: activeColName,
    columns,
    components,
  }
}

async function listConfigTables() {
  if (isDbConnected()) {
    const docs = await ConfigTable.find({}).sort({ updatedAt: -1 }).lean().exec()
    return docs.map(normalizeDoc)
  }
  return Array.from(ConfigTable._inMemoryTables.values()).map(normalizeDoc)
}

async function getConfigTable(project) {
  if (isDbConnected()) {
    const doc = await ConfigTable.findOne({ project }).lean().exec()
    return doc ? normalizeDoc(doc) : null
  }
  const item = ConfigTable._inMemoryTables.get(project)
  return item ? normalizeDoc(item) : null
}

async function createConfigTable(payload, actor = 'admin') {
  if (!payload || !payload.project || !payload.project.trim()) {
    const err = new Error('Project name is required')
    err.status = 400
    throw err
  }
  const projectName = payload.project.trim()

  const existing = await getConfigTable(projectName)
  if (existing) {
    const err = new Error(`Configuration table for project '${projectName}' already exists`)
    err.status = 409
    throw err
  }

  const activeColumn = payload.activeColumn || '1.0.0'
  const now = new Date()
  let columns = payload.columns
  let components = payload.components || []

  if (!columns || !columns.length) {
    columns = [
      {
        name: activeColumn,
        description: `${activeColumn} 默认 App 版本基线`,
        createdAt: now,
        updatedAt: now,
        components,
      },
    ]
  } else {
    // If columns provided, ensure activeColumn points to one
    const found = columns.find(c => c.name === activeColumn)
    if (!found) {
      columns.unshift({
        name: activeColumn,
        description: `${activeColumn} 默认 App 版本基线`,
        createdAt: now,
        updatedAt: now,
        components,
      })
    } else if (components.length === 0 && found.components) {
      components = found.components
    }
  }

  const newDoc = {
    project: projectName,
    version: payload.version || 1,
    environment: payload.environment || 'dev',
    defaultMode: payload.defaultMode || 'binary',
    activeColumn,
    columns,
    components,
    createdAt: now,
    updatedAt: now,
  }

  let saved
  if (isDbConnected()) {
    saved = await ConfigTable.create(newDoc)
  } else {
    ConfigTable._inMemoryTables.set(projectName, newDoc)
    saved = newDoc
  }

  if (isDbConnected()) {
    await AuditEvent.create({
      actor,
      action: 'config_table.create',
      subject: projectName,
      details: { activeColumn, columnsCount: columns.length, componentsCount: components.length },
    }).catch(() => {})
  }

  return normalizeDoc(saved)
}

async function updateConfigTable(project, payload, actor = 'admin') {
  const current = await getConfigTable(project)
  if (!current) {
    const err = new Error(`Configuration table for project '${project}' not found`)
    err.status = 404
    throw err
  }

  const now = new Date()
  const activeColumn = payload.activeColumn !== undefined ? payload.activeColumn : current.activeColumn
  const defaultMode = payload.defaultMode !== undefined ? payload.defaultMode : current.defaultMode
  const environment = payload.environment !== undefined ? payload.environment : current.environment
  let columns = payload.columns !== undefined ? payload.columns : current.columns
  let components = payload.components !== undefined ? payload.components : current.components

  // Keep activeColumn and components synchronized
  if (payload.columns !== undefined) {
    const activeCol = columns.find(c => c.name === activeColumn)
    if (activeCol) {
      components = activeCol.components || []
    }
  } else if (payload.components !== undefined) {
    const colIdx = columns.findIndex(c => c.name === activeColumn)
    if (colIdx >= 0) {
      columns[colIdx].components = components
      columns[colIdx].updatedAt = now
    }
  }

  const updatedDoc = {
    ...current,
    activeColumn,
    defaultMode,
    environment,
    columns,
    components,
    updatedAt: now,
  }

  let saved
  if (isDbConnected()) {
    saved = await ConfigTable.findOneAndUpdate(
      { project },
      { $set: { activeColumn, defaultMode, environment, columns, components, updatedAt: now } },
      { new: true, runValidators: true }
    ).lean().exec()
  } else {
    ConfigTable._inMemoryTables.set(project, updatedDoc)
    saved = updatedDoc
  }

  if (isDbConnected()) {
    await AuditEvent.create({
      actor,
      action: 'config_table.update',
      subject: project,
      details: { activeColumn, defaultMode, environment, columnsCount: columns.length },
    }).catch(() => {})
  }

  return normalizeDoc(saved)
}

async function duplicateConfigTable(project, options = {}, actor = 'admin') {
  const source = await getConfigTable(project)
  if (!source) {
    const err = new Error(`Configuration table for project '${project}' not found`)
    err.status = 404
    throw err
  }

  // Case 1: Duplicate entire table into a new project
  if (options.targetProject && options.targetProject.trim() && options.targetProject.trim() !== project) {
    const targetProject = options.targetProject.trim()
    const existing = await getConfigTable(targetProject)
    if (existing) {
      const err = new Error(`Target project '${targetProject}' already exists`)
      err.status = 409
      throw err
    }

    const payload = {
      project: targetProject,
      version: source.version,
      environment: source.environment,
      defaultMode: source.defaultMode,
      activeColumn: source.activeColumn,
      columns: JSON.parse(JSON.stringify(source.columns)),
      components: JSON.parse(JSON.stringify(source.components)),
    }
    const created = await createConfigTable(payload, actor)

    if (isDbConnected()) {
      await AuditEvent.create({
        actor,
        action: 'config_table.duplicate',
        subject: targetProject,
        details: { fromProject: project },
      }).catch(() => {})
    }
    return created
  }

  // Case 2: Duplicate an App version column within the same project
  if (options.targetColumn && options.targetColumn.trim()) {
    const targetColName = options.targetColumn.trim()
    const sourceColName = options.sourceColumn || source.activeColumn
    const sourceCol = source.columns.find(c => c.name === sourceColName)
    if (!sourceCol) {
      const err = new Error(`Source column '${sourceColName}' not found in project '${project}'`)
      err.status = 404
      throw err
    }

    if (source.columns.some(c => c.name === targetColName)) {
      const err = new Error(`Column '${targetColName}' already exists in project '${project}'`)
      err.status = 409
      throw err
    }

    const now = new Date()
    const clonedComponents = JSON.parse(JSON.stringify(sourceCol.components || []))
    const newColumn = {
      name: targetColName,
      description: options.description || `由 ${sourceColName} 复制创建的 App 版本基线`,
      createdAt: now,
      updatedAt: now,
      components: clonedComponents,
    }

    const updatedColumns = [...source.columns, newColumn]
    const updated = await updateConfigTable(project, {
      columns: updatedColumns,
      activeColumn: options.setActive ? targetColName : source.activeColumn,
    }, actor)

    if (isDbConnected()) {
      await AuditEvent.create({
        actor,
        action: 'config_table.duplicate_column',
        subject: project,
        details: { sourceColumn: sourceColName, targetColumn: targetColName },
      }).catch(() => {})
    }
    return updated
  }

  const err = new Error('Either targetProject or targetColumn must be specified for duplication')
  err.status = 400
  throw err
}

async function deleteConfigTable(project, actor = 'admin') {
  const current = await getConfigTable(project)
  if (!current) {
    const err = new Error(`Configuration table for project '${project}' not found`)
    err.status = 404
    throw err
  }

  if (isDbConnected()) {
    await ConfigTable.deleteOne({ project }).exec()
    await AuditEvent.create({
      actor,
      action: 'config_table.delete',
      subject: project,
      details: {},
    }).catch(() => {})
  } else {
    ConfigTable._inMemoryTables.delete(project)
  }

  return { success: true, project }
}

module.exports = {
  listConfigTables,
  getConfigTable,
  createConfigTable,
  updateConfigTable,
  duplicateConfigTable,
  deleteConfigTable,
  normalizeDoc,
}
