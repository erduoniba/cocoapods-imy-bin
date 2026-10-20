'use strict'

const mongoose = require('mongoose')

const { Schema } = mongoose

const ComponentSchema = new Schema({
  name: {
    type: String,
    required: true,
    trim: true,
  },
  version: {
    type: String,
    required: true,
    trim: true,
  },
  annotate: {
    type: String,
    default: '',
    trim: true,
    maxlength: 1_000,
  },
  sha256: {
    type: String,
    required: true,
    match: /^[a-f0-9]{64}$/,
  },
  size: {
    type: Number,
    required: true,
    min: 1,
  },
  managedReleaseId: { type: Schema.Types.ObjectId, default: null, ref: 'Release' },
  status: {
    type: String,
    enum: ['pending', 'staged', 'ready', 'deleting'],
    default: 'pending',
  },
}, {
  strict: 'throw',
  timestamps: true,
  versionKey: false,
})

ComponentSchema.index({ name: 1, version: 1 }, { unique: true })

module.exports = mongoose.models.Component || mongoose.model('Component', ComponentSchema)
