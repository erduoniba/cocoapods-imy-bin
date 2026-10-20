'use strict'

const mongoose = require('mongoose')
const { Schema } = mongoose

const BuildJobSchema = new Schema({
  releaseId: { type: Schema.Types.ObjectId, required: true, ref: 'Release', unique: true },
  status: { type: String, enum: ['queued', 'leased', 'failed', 'succeeded'], default: 'queued' },
  leaseId: { type: String, default: null },
  leaseOwner: { type: String, default: null },
  leaseExpiresAt: { type: Date, default: null },
  attempts: { type: Number, default: 0 },
  events: [{ kind: { type: String, enum: ['output', 'phase', 'warning', 'error'] }, message: String, at: Date }],
}, { strict: 'throw', timestamps: true, versionKey: false })

module.exports = mongoose.models.BuildJob || mongoose.model('BuildJob', BuildJobSchema)
