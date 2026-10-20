'use strict'

const mongoose = require('mongoose')
const { Schema } = mongoose

const AuditEventSchema = new Schema({
  actor: { type: String, required: true },
  action: { type: String, required: true },
  subject: { type: String, required: true },
  details: { type: Schema.Types.Mixed, default: {} },
}, { strict: 'throw', timestamps: true, versionKey: false })

module.exports = mongoose.models.AuditEvent || mongoose.model('AuditEvent', AuditEventSchema)
