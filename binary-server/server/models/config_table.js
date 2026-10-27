'use strict'

const mongoose = require('mongoose')
const { Schema } = mongoose

const ComponentEntrySchema = new Schema({
  name: { type: String, required: true, trim: true },
  version: { type: String, default: '', trim: true },
  mode: {
    type: String,
    enum: ['local', 'source', 'binary', 'branch'],
    default: 'binary',
    required: true,
  },
  path: { type: String, default: null },
  git: { type: String, default: null },
  branch: { type: String, default: null },
  tag: { type: String, default: null },
  commit: { type: String, default: null },
  targets: { type: [String], default: undefined },
  enabled: { type: Boolean, default: true },
  supportsLocal: { type: Boolean, default: false },
}, { _id: false, strict: 'throw' })

const ConfigColumnSchema = new Schema({
  name: { type: String, required: true, trim: true },
  description: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
  components: [ComponentEntrySchema],
}, { _id: false, strict: 'throw' })

const ConfigTableSchema = new Schema({
  project: { type: String, required: true, unique: true, trim: true },
  version: { type: Number, default: 1 },
  environment: { type: String, default: 'dev', trim: true },
  defaultMode: {
    type: String,
    enum: ['local', 'source', 'binary', 'branch'],
    default: 'binary',
  },
  activeColumn: { type: String, default: '1.0.0' },
  columns: [ConfigColumnSchema],
  components: [ComponentEntrySchema],
}, { strict: 'throw', timestamps: true, versionKey: false })

ConfigTableSchema.index({ project: 1 }, { unique: true })

// In-memory fallback map for offline dev or unit testing without MongoDB
const inMemoryTables = new Map()

// Default seed configuration based on standard project baseline
const defaultSeed = {
  project: 'HDImyBinApp',
  version: 1,
  environment: 'dev',
  defaultMode: 'binary',
  activeColumn: '1.2.0',
  columns: [
    {
      name: '1.0.0',
      description: 'App 1.0.0 正式发版基线',
      createdAt: new Date('2026-10-20T00:00:00Z'),
      updatedAt: new Date('2026-10-20T00:00:00Z'),
      components: [
        { name: 'HDDynamicPod', version: '0.1.6', mode: 'binary', path: '../HDDynamicPod', enabled: true, supportsLocal: true },
        { name: 'HDStaticPod', version: '0.1.11', mode: 'binary', path: '../HDStaticPod', enabled: true, supportsLocal: true },
      ],
    },
    {
      name: '1.1.0',
      description: 'App 1.1.0 迭代测试基线',
      createdAt: new Date('2026-10-21T00:00:00Z'),
      updatedAt: new Date('2026-10-21T00:00:00Z'),
      components: [
        { name: 'HDDynamicPod', version: '0.1.6-beta.7', mode: 'source', path: '../HDDynamicPod', enabled: true, supportsLocal: true },
        { name: 'HDStaticPod', version: '0.1.11-beta.3', mode: 'binary', path: '../HDStaticPod', enabled: true, supportsLocal: true },
      ],
    },
    {
      name: '1.2.0',
      description: 'App 1.2.0 主干当前开发基线',
      createdAt: new Date('2026-10-22T00:00:00Z'),
      updatedAt: new Date('2026-10-22T02:24:22Z'),
      components: [
        { name: 'HDDynamicPod', version: '0.1.6-beta.8', mode: 'local', path: '../HDDynamicPod', enabled: true, supportsLocal: true },
        { name: 'HDStaticPod', version: '0.1.11-beta.4', mode: 'local', path: '../HDStaticPod', enabled: true, supportsLocal: true },
      ],
    },
  ],
  components: [
    { name: 'HDDynamicPod', version: '0.1.6-beta.8', mode: 'local', path: '../HDDynamicPod', enabled: true, supportsLocal: true },
    { name: 'HDStaticPod', version: '0.1.11-beta.4', mode: 'local', path: '../HDStaticPod', enabled: true, supportsLocal: true },
  ],
  createdAt: new Date('2026-10-20T00:00:00Z'),
  updatedAt: new Date('2026-10-22T13:50:00Z'),
}

inMemoryTables.set(defaultSeed.project, defaultSeed)

const ConfigTableModel = mongoose.models.ConfigTable || mongoose.model('ConfigTable', ConfigTableSchema)

ConfigTableModel._inMemoryTables = inMemoryTables
ConfigTableModel._defaultSeed = defaultSeed

module.exports = ConfigTableModel
