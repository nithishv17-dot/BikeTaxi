import { PrismaClient } from '@prisma/client';
interface MigrationRecord {
    id: string;
    entityType: 'User' | 'Ride';
    mongoId: string;
    postgresId: string;
    status: 'pending' | 'in_progress' | 'completed' | 'failed';
    errorMessage?: string;
    createdAt: Date;
    completedAt?: Date;
}
interface MigrationProgress {
    totalRecords: number;
    completed: number;
    failed: number;
    pending: number;
    inProgress: number;
    percentComplete: number;
    estimatedTimeRemaining: string;
}
declare class MigrationTrackerService {
    private prisma;
    private migrationRecords;
    private batchSize;
    private startTime;
    constructor(prisma: PrismaClient);
    /**
     * Start tracking a new migration batch
     */
    startMigration(entityType: 'User' | 'Ride', totalRecords: number): void;
    /**
     * Record a migration attempt
     */
    recordMigration(mongoId: string, postgresId: string, entityType: 'User' | 'Ride', status: 'completed' | 'failed', error?: string): void;
    /**
     * Get migration progress
     */
    getProgress(entityType?: 'User' | 'Ride'): MigrationProgress;
    /**
     * Get detailed migration report
     */
    getDetailedReport(): {
        summary: MigrationProgress;
        byEntityType: {
            User: MigrationProgress;
            Ride: MigrationProgress;
        };
        failedRecords: MigrationRecord[];
        successRate: string;
    };
    /**
     * Get migration records by status
     */
    getRecordsByStatus(status: 'pending' | 'in_progress' | 'completed' | 'failed'): MigrationRecord[];
    /**
     * Export migration log for audit
     */
    exportLog(): string;
    /**
     * Clear migration history
     */
    clearHistory(): void;
    /**
     * Format duration in readable format
     */
    private formatDuration;
}
export { MigrationTrackerService, MigrationRecord, MigrationProgress };
//# sourceMappingURL=migrationTracker.d.ts.map