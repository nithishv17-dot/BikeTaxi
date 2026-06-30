import { PrismaClient } from '@prisma/client';
/**
 * Production Monitoring Service
 * Tracks metrics during database migration and cutover
 */
interface HealthMetrics {
    timestamp: Date;
    database: 'mongodb' | 'postgres' | 'both';
    writeLatency: number;
    readLatency: number;
    errorRate: number;
    activeConnections: number;
    memoryUsageMb: number;
    cpuUsagePercent: number;
    requestsPerSecond: number;
}
interface AlertEvent {
    timestamp: Date;
    severity: 'critical' | 'warning' | 'info';
    message: string;
    metric: string;
    value: number;
    threshold: number;
}
declare class ProductionMonitoringService {
    private prisma;
    private metrics;
    private alerts;
    private thresholds;
    private monitoringInterval;
    constructor(prisma: PrismaClient);
    /**
     * Start continuous monitoring
     */
    startMonitoring(intervalSeconds?: number): void;
    /**
     * Stop monitoring
     */
    stopMonitoring(): void;
    /**
     * Collect current health metrics
     */
    private collectMetrics;
    /**
     * Measure write latency
     */
    private measureWriteLatency;
    /**
     * Measure read latency
     */
    private measureReadLatency;
    /**
     * Calculate error rate from recent metrics
     */
    private calculateErrorRate;
    /**
     * Check if metrics exceed thresholds
     */
    private checkThresholds;
    /**
     * Record an alert event
     */
    private recordAlert;
    /**
     * Get current health status
     */
    getHealthStatus(): {
        status: 'healthy' | 'degraded' | 'critical';
        metrics: HealthMetrics | null;
        recentAlerts: AlertEvent[];
        recommendations: string[];
    };
    /**
     * Get metrics for specific time range
     */
    getMetricsForRange(startTime: Date, endTime: Date): {
        avgWriteLatency: number;
        avgReadLatency: number;
        avgErrorRate: number;
        maxMemory: number;
        dataPoints: number;
    };
    /**
     * Get complete health report
     */
    generateHealthReport(): {
        timestamp: Date;
        status: 'healthy' | 'degraded' | 'critical';
        metrics: HealthMetrics | null;
        recentAlerts: AlertEvent[];
        hourlyAverages: {
            avgWriteLatency: number;
            avgReadLatency: number;
            avgErrorRate: number;
        };
        recommendations: string[];
    };
    /**
     * Validate cutover readiness
     */
    validateCutoverReadiness(): {
        ready: boolean;
        checks: {
            name: string;
            passed: boolean;
            details: string;
        }[];
    };
}
export { ProductionMonitoringService, HealthMetrics, AlertEvent };
//# sourceMappingURL=productionMonitoring.d.ts.map