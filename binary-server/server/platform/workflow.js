'use strict'

const { conflict } = require('./validation')

function verifyActivation(release, artifact, checksum) {
  if (!release || release.status !== 'requested') conflict('Release is not awaiting completion')
  if (!release.sourceSpecCommit || !release.binarySpecCommit) conflict('Both spec repositories must be attested')
  if (!artifact || artifact.status !== 'staged' ||
      String(artifact.managedReleaseId) !== String(release._id)) conflict('Staged artifact is required')
  if (!checksum || checksum !== artifact.sha256) conflict('Staged artifact checksum mismatch')
  return { name: release.name, version: release.version, sha256: checksum }
}

function visibleManagedArtifact(release, artifact) {
  return Boolean(release?.status === 'active' && artifact?.status === 'staged' &&
    String(artifact.managedReleaseId) === String(release._id))
}

module.exports = { verifyActivation, visibleManagedArtifact }
