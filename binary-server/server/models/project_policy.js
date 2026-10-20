'use strict'

const mongoose = require('mongoose')
const { Schema } = mongoose

const DependencySchema = new Schema({
  name: { type: String, required: true },
  version: { type: String, required: true },
  mode: { type: String, enum: ['source', 'binary'], required: true },
}, { _id: false, strict: 'throw' })

const TargetSchema = new Schema({
  name: { type: String, required: true },
  dependencies: [DependencySchema],
}, { _id: false, strict: 'throw' })

const PolicyRevisionSchema = new Schema({
  project: { type: String, required: true },
  revision: { type: String, required: true },
  targets: [TargetSchema],
}, { strict: 'throw', timestamps: true, versionKey: false })

PolicyRevisionSchema.index({ project: 1, revision: 1 }, { unique: true })

module.exports = mongoose.models.ProjectPolicyRevision || mongoose.model('ProjectPolicyRevision', PolicyRevisionSchema)
