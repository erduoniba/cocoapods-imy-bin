'use strict'

class TelemetryAndQualityService {
  constructor() {
    this.installEvents = []
    this.qualityReports = []
  }

  recordInstallEvent(event = {}) {
    const totalPods = Math.max(Number(event.totalPods || 0), 0)
    const binaryHitPods = Math.min(Math.max(Number(event.binaryHitPods || 0), 0), totalPods)
    const durationSeconds = Math.max(Number(event.durationSeconds || 0), 0)
    // Empirical baseline: each prebuilt XCFramework saves ~18 seconds of clean Xcode source compilation
    const estimatedSavedSeconds =
      event.estimatedSavedSeconds !== undefined
        ? Math.max(Number(event.estimatedSavedSeconds), 0)
        : binaryHitPods * 18

    const record = {
      project: String(event.project || 'DefaultApp'),
      developer: String(event.developer || 'anonymous'),
      totalPods,
      binaryHitPods,
      hitRate: totalPods > 0 ? Number(((binaryHitPods / totalPods) * 100).toFixed(1)) : 0,
      durationSeconds,
      estimatedSavedSeconds,
      at: new Date().toISOString(),
    }
    this.installEvents.push(record)
    if (this.installEvents.length > 5000) {
      this.installEvents.shift()
    }
    return record
  }

  getRoiSummary() {
    const totalInstalls = this.installEvents.length
    if (totalInstalls === 0) {
      return {
        totalInstalls: 0,
        averageHitRatePercent: 0,
        totalSavedSeconds: 0,
        totalSavedHours: 0,
        recentEvents: [],
      }
    }
    const totalSavedSeconds = this.installEvents.reduce((acc, item) => acc + item.estimatedSavedSeconds, 0)
    const avgHitRate =
      this.installEvents.reduce((acc, item) => acc + item.hitRate, 0) / totalInstalls

    return {
      totalInstalls,
      averageHitRatePercent: Number(avgHitRate.toFixed(1)),
      totalSavedSeconds,
      totalSavedHours: Number((totalSavedSeconds / 3600).toFixed(2)),
      recentEvents: this.installEvents.slice(-20).reverse(),
    }
  }

  evaluateArtifactQualityGate(input = {}) {
    const name = String(input.name || 'UnknownPod')
    const version = String(input.version || '0.1.0')
    const currentSizeBytes = Math.max(Number(input.currentSizeBytes || 0), 0)
    const previousSizeBytes = Math.max(Number(input.previousSizeBytes || 0), 0)
    const maxGrowthRatio = Number(input.maxGrowthRatio ?? 0.2)
    const symbols = Array.isArray(input.exportedSymbols) ? input.exportedSymbols : []
    const hasPrivacyManifest = input.hasPrivacyManifest !== false

    const issues = []
    let growthRatio = 0

    if (previousSizeBytes > 0 && currentSizeBytes > previousSizeBytes) {
      growthRatio = (currentSizeBytes - previousSizeBytes) / previousSizeBytes
      if (growthRatio > maxGrowthRatio) {
        issues.push({
          code: 'SIZE_REGRESSION',
          severity: 'error',
          message: `Artifact size grew by ${(growthRatio * 100).toFixed(1)}% (limit: ${(maxGrowthRatio * 100).toFixed(0)}%)`,
        })
      }
    }

    const seenSymbols = new Set()
    const duplicateSymbols = new Set()
    for (const sym of symbols) {
      if (seenSymbols.has(sym)) {
        duplicateSymbols.add(sym)
      }
      seenSymbols.add(sym)
    }
    if (duplicateSymbols.size > 0) {
      issues.push({
        code: 'DUPLICATE_SYMBOLS',
        severity: 'error',
        message: `Detected duplicate exported symbols: ${Array.from(duplicateSymbols).join(', ')}`,
      })
    }

    if (!hasPrivacyManifest) {
      issues.push({
        code: 'MISSING_PRIVACY_MANIFEST',
        severity: 'warning',
        message: 'Component XCFramework does not bundle PrivacyInfo.xcprivacy',
      })
    }

    const passed = !issues.some((item) => item.severity === 'error')
    const report = {
      name,
      version,
      passed,
      currentSizeBytes,
      previousSizeBytes,
      growthPercent: Number((growthRatio * 100).toFixed(1)),
      issues,
      evaluatedAt: new Date().toISOString(),
    }
    this.qualityReports.push(report)
    if (this.qualityReports.length > 1000) {
      this.qualityReports.shift()
    }
    return report
  }
}

module.exports = {
  TelemetryAndQualityService,
}
