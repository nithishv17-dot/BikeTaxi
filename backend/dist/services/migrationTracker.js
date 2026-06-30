"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MigrationTrackerService = void 0;
const logger_1 = require("../utils/logger");
class MigrationTrackerService {
    constructor(prisma) {
        this.prisma = prisma;
        this.migrationRecords = [];
        this.batchSize = 100;
        this.startTime = new Date();
    }
    /**
     * Start tracking a new migration batch
     */
    startMigration(entityType, totalRecords) {
        logger_1.logger.info(`Starting migration for ${entityType}`, { totalRecords });
        this.startTime = new Date();
        this.migrationRecords = [];
    }
    /**
     * Record a migration attempt
     */
    recordMigration(mongoId, postgresId, entityType, status, error) {
        const record = {
            id: `${mongoId}-${postgresId}`,
            entityType,
            mongoId,
            postgresId,
            status,
            errorMessage: error,
            createdAt: new Date(),
            completedAt: new Date(),
        };
        this.migrationRecords.push(record);
        if (status === 'failed') {
            logger_1.logger.warn(`Migration failed for ${entityType}`, {
                mongoId,
                postgresId,
                error,
            });
        }
    }
    /**
     * Get migration progress
     */
    getProgress(entityType) {
        let records = this.migrationRecords;
        if (entityType) {
            records = records.filter(r => r.entityType === entityType);
        }
        const completed = records.filter(r => r.status === 'completed').length;
        const failed = records.filter(r => r.status === 'failed').length;
        const pending = records.filter(r => r.status === 'pending').length;
        const inProgress = records.filter(r => r.status === 'in_progress').length;
        const total = records.length;
        const percentComplete = total > 0 ? (completed / total) * 100 : 0;
        const elapsed = new Date().getTime() - this.startTime.getTime();
        const avgTime = completed > 0 ? elapsed / completed : 0;
        const remaining = pending + inProgress;
        const estimatedMs = remaining * avgTime;
        const estimatedTimeRemaining = this.formatDuration(estimatedMs);
        return {
            totalRecords: total,
            completed,
            failed,
            pending,
            inProgress,
            percentComplete: Math.round(percentComplete * 100) / 100,
            estimatedTimeRemaining,
        };
    }
    /**
     * Get detailed migration report
     */
    getDetailedReport() {
        const summary = this.getProgress();
        const failedRecords = this.migrationRecords.filter(r => r.status === 'failed');
        const successRate = summary.completed + summary.failed > 0
            ? ((summary.completed / (summary.completed + summary.failed)) *
                100).toFixed(2) + '%'
            : 'N/A';
        return {
            summary,
            byEntityType: {
                User: this.getProgress('User'),
                Ride: this.getProgress('Ride'),
            },
            failedRecords,
            successRate,
        };
    }
    /**
     * Get migration records by status
     */
    getRecordsByStatus(status) {
        return this.migrationRecords.filter(r => r.status === status);
    }
    /**
     * Export migration log for audit
     */
    exportLog() {
        const headers = [
            'Timestamp',
            'Entity Type',
            'Mongo ID',
            'Postgres ID',
            'Status',
            'Error',
        ];
        const rows = this.migrationRecords.map(r => [
            r.createdAt.toISOString(),
            r.entityType,
            r.mongoId,
            r.postgresId,
            r.status,
            r.errorMessage || 'N/A',
        ]);
        const csv = [
            headers.join(','),
            ...rows.map(row => row.map(cell => `"${cell}"`).join(',')),
        ].join('\n');
        return csv;
    }
    /**
     * Clear migration history
     */
    clearHistory() {
        this.migrationRecords = [];
        logger_1.logger.info('Migration history cleared');
    }
    /**
     * Format duration in readable format
     */
    formatDuration(ms) {
        if (ms < 1000)
            return `${Math.round(ms)}ms`;
        if (ms < 60000)
            return `${Math.round(ms / 1000)}s`;
        if (ms < 3600000)
            return `${Math.round(ms / 60000)}m`;
        return `${Math.round(ms / 3600000)}h`;
    }
}
exports.MigrationTrackerService = MigrationTrackerService;
//# sourceMappingURL=migrationTracker.js.map