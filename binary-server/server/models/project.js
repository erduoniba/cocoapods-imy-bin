'use strict'

const mongoose = require('mongoose')
const { Schema } = mongoose

const ProjectSchema = new Schema({
  key: { type: String, required: true, unique: true },
  activeRevision: { type: String, default: null },
}, { strict: 'throw', timestamps: true, versionKey: false })

module.exports = mongoose.models.ManagedProject || mongoose.model('ManagedProject', ProjectSchema)
