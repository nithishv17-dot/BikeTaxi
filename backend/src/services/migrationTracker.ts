import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger';

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

class MigrationTrackerService {
  private migrationRecords: MigrationRecord[] = [];
  private batchSize = 100;
  private startTime: Date = new Date();

  constructor(private prisma: PrismaClient) {}

  /**
   * Start tracking a new migration batch
   */
  startMigration(entityType: 'User' | 'Ride', totalRecords: number): void {
    logger.info(`Starting migration for ${entityType}`, { totalRecords });
    this.startTime = new Date();
    this.migrationRecords = [];
  }

  /**
   * Record a migration attempt
   */
  recordMigration(
    mongoId: string,
    postgresId: string,
    entityType: 'User' | 'Ride',
    status: 'completed' | 'failed',
    error?: string
  ): void {
    const record: MigrationRecord = {
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
      logger.warn(`Migration failed for ${entityType}`, {
        mongoId,
        postgresId,
        error,
      });
    }
  }

  /**
   * Get migration progress
   */
  getProgress(entityType?: 'User' | 'Ride'): MigrationProgress {
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
  getDetailedReport(): {
    summary: MigrationProgress;
    byEntityType: { User: MigrationProgress; Ride: MigrationProgress };
    failedRecords: MigrationRecord[];
    successRate: string;
  } {
    const summary = this.getProgress();
    const failedRecords = this.migrationRecords.filter(r => r.status === 'failed');
    const successRate =
      summary.completed + summary.failed > 0
        ? (
            (summary.completed / (summary.completed + summary.failed)) *
            100
          ).toFixed(2) + '%'
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
  getRecordsByStatus(
    status: 'pending' | 'in_progress' | 'completed' | 'failed'
  ): MigrationRecord[] {
    return this.migrationRecords.filter(r => r.status === status);
  }

  /**
   * Export migration log for audit
   */
  exportLog(): string {
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
  clearHistory(): void {
    this.migrationRecords = [];
    logger.info('Migration history cleared');
  }

  /**
   * Format duration in readable format
   */
  private formatDuration(ms: number): string {
    if (ms < 1000) return `${Math.round(ms)}ms`;
    if (ms < 60000) return `${Math.round(ms / 1000)}s`;
    if (ms < 3600000) return `${Math.round(ms / 60000)}m`;
    return `${Math.round(ms / 3600000)}h`;
  }
}

export { MigrationTrackerService, MigrationRecord, MigrationProgress };
