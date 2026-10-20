'use strict'

const mongoose = require('mongoose')
const { Schema } = mongoose

const ReleaseSchema = new Schema({
  name: { type: String, required: true },
  version: { type: String, required: true },
  sourceCommit: { type: String, required: true, match: /^[a-f0-9]{40}$/ },
  sourceSpecCommit: { type: String, default: null, match: /^[a-f0-9]{40}$/ },
  binarySpecCommit: { type: String, default: null, match: /^[a-f0-9]{40}$/ },
  status: { type: String, enum: ['requested', 'failed', 'active'], default: 'requested' },
  failureSummary: { type: String, default: null },
}, { strict: 'throw', timestamps: true, versionKey: false })

ReleaseSchema.index({ name: 1, version: 1 }, { unique: true })

module.exports = mongoose.models.Release || mongoose.model('Release', ReleaseSchema)
