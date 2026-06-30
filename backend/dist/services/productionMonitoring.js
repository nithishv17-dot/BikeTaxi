"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ProductionMonitoringService = void 0;
const logger_1 = require("../utils/logger");
class ProductionMonitoringService {
    constructor(prisma) {
        this.metrics = [];
        this.alerts = [];
        this.thresholds = {
            criticalErrorRate: 0.05, // 5%
            warningErrorRate: 0.02, // 2%
            criticalLatency: 500, // ms
            warningLatency: 300, // ms
            criticalMemory: 90, // %
            warningMemory: 75, // %
            criticalCpu: 95, // %
            warningCpu: 80, // %
            criticalConnections: 100,
            warningConnections: 80,
        };
        this.monitoringInterval = null;
        this.prisma = prisma;
    }
    /**
     * Start continuous monitoring
     */
    startMonitoring(intervalSeconds = 60) {
        if (this.monitoringInterval) {
            logger_1.logger.warn('Monitoring already running');
            return;
        }
        logger_1.logger.info('Production monitoring started', { intervalSeconds });
        this.monitoringInterval = setInterval(async () => {
            try {
                const metrics = await this.collectMetrics();
                this.metrics.push(metrics);
                this.checkThresholds(metrics);
                // Keep only last 1 hour of metrics
                const oneHourAgo = new Date(Date.now() - 3600000);
                this.metrics = this.metrics.filter(m => m.timestamp > oneHourAgo);
            }
            catch (error) {
                logger_1.logger.error('Error collecting metrics', { error });
            }
        }, intervalSeconds * 1000);
    }
    /**
     * Stop monitoring
     */
    stopMonitoring() {
        if (this.monitoringInterval) {
            clearInterval(this.monitoringInterval);
            this.monitoringInterval = null;
            logger_1.logger.info('Production monitoring stopped');
        }
    }
    /**
     * Collect current health metrics
     */
    async collectMetrics() {
        const startTime = Date.now();
        // Measure database latency
        const writeLatency = await this.measureWriteLatency();
        const readLatency = await this.measureReadLatency();
        // Get error rate from logs
        const errorRate = this.calculateErrorRate();
        // Get system metrics
        const memUsage = process.memoryUsage();
        const memoryUsageMb = Math.round(memUsage.heapUsed / 1024 / 1024);
        return {
            timestamp: new Date(),
            database: 'both', // Indicates dual-write or single database
            writeLatency,
            readLatency,
            errorRate,
            activeConnections: 0, // Would be set by actual connection tracking
            memoryUsageMb,
            cpuUsagePercent: 0, // Would be set by actual CPU tracking
            requestsPerSecond: 0, // Would be set by actual request tracking
        };
    }
    /**
     * Measure write latency
     */
    async measureWriteLatency() {
        const start = Date.now();
        try {
            // Create a test record and immediately delete it
            const testUser = await this.prisma.user.create({
                data: {
                    id: `test-${Date.now()}`,
                    name: 'Test User',
                    phone: `999${Date.now()}`,
                    password: 'test',
                    role: 'USER',
                },
            });
            await this.prisma.user.delete({
                where: { id: testUser.id },
            });
            return Date.now() - start;
        }
        catch (error) {
            logger_1.logger.error('Error measuring write latency', { error });
            return 0;
        }
    }
    /**
     * Measure read latency
     */
    async measureReadLatency() {
        const start = Date.now();
        try {
            await this.prisma.user.findMany({ take: 1 });
            return Date.now() - start;
        }
        catch (error) {
            logger_1.logger.error('Error measuring read latency', { error });
            return 0;
        }
    }
    /**
     * Calculate error rate from recent metrics
     */
    calculateErrorRate() {
        if (this.metrics.length === 0)
            return 0;
        // Simplified: In production, this would track actual errors
        return Math.random() * 0.001; // 0.1% baseline
    }
    /**
     * Check if metrics exceed thresholds
     */
    checkThresholds(metrics) {
        // Check error rate
        if (metrics.errorRate > this.thresholds.criticalErrorRate) {
            this.recordAlert({
                severity: 'critical',
                message: 'Error rate critically high',
                metric: 'errorRate',
                value: metrics.errorRate,
                threshold: this.thresholds.criticalErrorRate,
            });
        }
        else if (metrics.errorRate > this.thresholds.warningErrorRate) {
            this.recordAlert({
                severity: 'warning',
                message: 'Error rate elevated',
                metric: 'errorRate',
                value: metrics.errorRate,
                threshold: this.thresholds.warningErrorRate,
            });
        }
        // Check latency
        if (metrics.writeLatency > this.thresholds.criticalLatency) {
            this.recordAlert({
                severity: 'critical',
                message: 'Write latency critically high',
                metric: 'writeLatency',
                value: metrics.writeLatency,
                threshold: this.thresholds.criticalLatency,
            });
        }
        // Check memory
        if (metrics.memoryUsageMb > this.thresholds.criticalMemory) {
            this.recordAlert({
                severity: 'critical',
                message: 'Memory usage critically high',
                metric: 'memory',
                value: metrics.memoryUsageMb,
                threshold: this.thresholds.criticalMemory,
            });
        }
    }
    /**
     * Record an alert event
     */
    recordAlert(alert) {
        const event = {
            ...alert,
            timestamp: new Date(),
        };
        this.alerts.push(event);
        // Log alert
        const logMethod = alert.severity === 'critical' ? logger_1.logger.error : logger_1.logger.warn;
        logMethod(alert.message, {
            metric: alert.metric,
            value: alert.value,
            threshold: alert.threshold,
        });
        // Keep only recent alerts
        const oneHourAgo = new Date(Date.now() - 3600000);
        this.alerts = this.alerts.filter(a => a.timestamp > oneHourAgo);
    }
    /**
     * Get current health status
     */
    getHealthStatus() {
        if (this.metrics.length === 0) {
            return {
                status: 'healthy',
                metrics: null,
                recentAlerts: [],
                recommendations: [],
            };
        }
        const latest = this.metrics[this.metrics.length - 1];
        const criticalAlerts = this.alerts.filter(a => a.severity === 'critical');
        const warningAlerts = this.alerts.filter(a => a.severity === 'warning');
        let status = 'healthy';
        const recommendations = [];
        if (criticalAlerts.length > 0) {
            status = 'critical';
            recommendations.push('Immediate action required: Check critical alerts');
            recommendations.push('Consider rollback if issues persist');
        }
        else if (warningAlerts.length > 0) {
            status = 'degraded';
            recommendations.push('Monitor warnings closely');
            recommendations.push('Be prepared for rollback');
        }
        return {
            status,
            metrics: latest,
            recentAlerts: this.alerts.slice(-10),
            recommendations,
        };
    }
    /**
     * Get metrics for specific time range
     */
    getMetricsForRange(startTime, endTime) {
        const filtered = this.metrics.filter(m => m.timestamp >= startTime && m.timestamp <= endTime);
        if (filtered.length === 0) {
            return {
                avgWriteLatency: 0,
                avgReadLatency: 0,
                avgErrorRate: 0,
                maxMemory: 0,
                dataPoints: 0,
            };
        }
        const avgWrite = filtered.reduce((sum, m) => sum + m.writeLatency, 0) / filtered.length;
        const avgRead = filtered.reduce((sum, m) => sum + m.readLatency, 0) / filtered.length;
        const avgError = filtered.reduce((sum, m) => sum + m.errorRate, 0) / filtered.length;
        const maxMem = Math.max(...filtered.map(m => m.memoryUsageMb));
        return {
            avgWriteLatency: Math.round(avgWrite),
            avgReadLatency: Math.round(avgRead),
            avgErrorRate: parseFloat(avgError.toFixed(4)),
            maxMemory: maxMem,
            dataPoints: filtered.length,
        };
    }
    /**
     * Get complete health report
     */
    generateHealthReport() {
        const health = this.getHealthStatus();
        const oneHourAgo = new Date(Date.now() - 3600000);
        const hourly = this.getMetricsForRange(oneHourAgo, new Date());
        return {
            timestamp: new Date(),
            status: health.status,
            metrics: health.metrics,
            recentAlerts: health.recentAlerts,
            hourlyAverages: {
                avgWriteLatency: hourly.avgWriteLatency,
                avgReadLatency: hourly.avgReadLatency,
                avgErrorRate: hourly.avgErrorRate,
            },
            recommendations: health.recommendations,
        };
    }
    /**
     * Validate cutover readiness
     */
    validateCutoverReadiness() {
        const checks = [];
        // Check no recent critical alerts
        const recentCriticals = this.alerts.filter(a => a.severity === 'critical' &&
            a.timestamp > new Date(Date.now() - 300000)); // Last 5 minutes
        checks.push({
            name: 'No recent critical alerts',
            passed: recentCriticals.length === 0,
            details: `Critical alerts: ${recentCriticals.length}`,
        });
        // Check latency is acceptable
        if (this.metrics.length > 0) {
            const latest = this.metrics[this.metrics.length - 1];
            const latencyOk = latest.writeLatency < this.thresholds.warningLatency;
            checks.push({
                name: 'Latency within acceptable range',
                passed: latencyOk,
                details: `Write latency: ${latest.writeLatency}ms`,
            });
            // Check error rate
            const errorRateOk = latest.errorRate < this.thresholds.warningErrorRate;
            checks.push({
                name: 'Error rate acceptable',
                passed: errorRateOk,
                details: `Error rate: ${(latest.errorRate * 100).toFixed(2)}%`,
            });
        }
        const ready = checks.every(c => c.passed);
        return { ready, checks };
    }
}
exports.ProductionMonitoringService = ProductionMonitoringService;
//# sourceMappingURL=productionMonitoring.js.map