#!/usr/bin/env node
'use strict'

const os = require('os')
const { spawn } = require('child_process')

class ImyBuildAgent {
  constructor(options = {}) {
    this.serverUrl = (options.serverUrl || process.env.IMYBIN_SERVER_URL || 'http://127.0.0.1:8080').replace(/\/+$/, '')
    this.agentToken = options.agentToken || process.env.PLATFORM_AGENT_TOKEN || ''
    this.agentId = options.agentId || process.env.IMYBIN_AGENT_ID || `${os.hostname()}-${process.pid}`
    this.workspaceRoot = options.workspaceRoot || process.env.IMYBIN_WORKSPACE_ROOT || process.cwd()
    this.pollIntervalMs = Number(options.pollIntervalMs || 5000)
    this.fetchImpl = options.fetchImpl || globalThis.fetch
    this.running = false
  }

  headers(leaseId = null) {
    const h = {
      'content-type': 'application/json',
      authorization: `Bearer ${this.agentToken}`,
    }
    if (leaseId) {
      h['x-job-lease'] = leaseId
    }
    return h
  }

  async claimNextJob() {
    const res = await this.fetchImpl(`${this.serverUrl}/api/v1/jobs/claim`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({ agentId: this.agentId }),
    })
    if (res.status === 204) {
      return null
    }
    if (!res.ok) {
      throw new Error(`Claim failed with HTTP ${res.status}`)
    }
    return res.json()
  }

  async sendHeartbeat(jobId, leaseId) {
    const res = await this.fetchImpl(`${this.serverUrl}/api/v1/jobs/${jobId}/heartbeat`, {
      method: 'POST',
      headers: this.headers(leaseId),
    })
    if (!res.ok) {
      throw new Error(`Heartbeat failed with HTTP ${res.status}`)
    }
    return res.json()
  }

  async sendEvent(jobId, leaseId, kind, message) {
    await this.fetchImpl(`${this.serverUrl}/api/v1/jobs/${jobId}/events`, {
      method: 'POST',
      headers: this.headers(leaseId),
      body: JSON.stringify({ kind, message: String(message).slice(0, 4096) }),
    })
  }

  async finishJob(jobId, leaseId, success, failureSummary = null) {
    const res = await this.fetchImpl(`${this.serverUrl}/api/v1/jobs/${jobId}/finish`, {
      method: 'POST',
      headers: this.headers(leaseId),
      body: JSON.stringify({ success, failureSummary }),
    })
    if (!res.ok) {
      throw new Error(`Finish job failed with HTTP ${res.status}`)
    }
    return res.json()
  }

  runArchiveCommand(componentName) {
    return new Promise((resolve, reject) => {
      const child = spawn('pod', ['bin', 'archive', `${componentName}.podspec`, '--no-clean'], {
        cwd: this.workspaceRoot,
        stdio: ['ignore', 'pipe', 'pipe'],
      })
      let output = ''
      child.stdout.on('data', (chunk) => { output += chunk.toString() })
      child.stderr.on('data', (chunk) => { output += chunk.toString() })
      child.on('error', reject)
      child.on('close', (code) => {
        if (code === 0) {
          resolve(output)
        } else {
          reject(new Error(`pod bin archive exited with code ${code}: ${output.slice(-500)}`))
        }
      })
    })
  }
}

if (require.main === module) {
  const agent = new ImyBuildAgent()
  console.log(`[IMYBin Build Agent] Starting worker ${agent.agentId} polling ${agent.serverUrl}...`)
  const poll = async () => {
    try {
      const claimed = await agent.claimNextJob()
      if (claimed) {
        console.log(`[IMYBin Build Agent] Claimed job ${claimed.jobId} for ${claimed.release.name}@${claimed.release.version}`)
        await agent.sendEvent(claimed.jobId, claimed.leaseId, 'phase', `Agent ${agent.agentId} started archive`)
      }
    } catch (error) {
      console.error(`[IMYBin Build Agent] Poll error: ${error.message}`)
    }
  }
  setInterval(poll, agent.pollIntervalMs)
  poll()
}

module.exports = {
  ImyBuildAgent,
}
