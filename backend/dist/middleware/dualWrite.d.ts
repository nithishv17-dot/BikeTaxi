import { PrismaClient } from '@prisma/client';
import { Document, Model } from 'mongoose';
interface DualWriteConfig {
    enabled: boolean;
    mongoFirst: boolean;
    postgresFirst: boolean;
    failureMode: 'strict' | 'lenient';
    logDetails: boolean;
}
interface WriteOperation {
    entity: string;
    operation: 'create' | 'update' | 'delete';
    mongoStatus: 'pending' | 'success' | 'failed';
    postgresStatus: 'pending' | 'success' | 'failed';
    mongoError?: string;
    postgresError?: string;
    timestamp: Date;
}
declare class DualWriteManager {
    private config;
    private prisma;
    private writeLog;
    private consistencyCheckInterval;
    constructor(prisma: PrismaClient);
    /**
     * Write a user to both databases
     */
    writeUser(mongoModel: Model<Document>, userData: any, operation?: 'create' | 'update'): Promise<{
        mongo: any;
        postgres: any;
    }>;
    /**
     * Write a ride to both databases
     */
    writeRide(mongoModel: Model<Document>, rideData: any, operation?: 'create' | 'update'): Promise<{
        mongo: any;
        postgres: any;
    }>;
    /**
     * Write to MongoDB
     */
    private writeToMongo;
    /**
     * Write user to PostgreSQL
     */
    private writeUserToPostgres;
    /**
     * Write ride to PostgreSQL
     */
    private writeRideToPostgres;
    /**
     * Get write operation log
     */
    getWriteLog(limit?: number): WriteOperation[];
    /**
     * Get migration statistics
     */
    getMigrationStats(): {
        totalOperations: number;
        successfulDualWrites: number;
        mongoOnlySuccesses: number;
        postgresOnlySuccesses: number;
        mongoFailures: number;
        postgresFailures: number;
        successRate: string;
        dualWriteEnabled: boolean;
    };
    /**
     * Enable/disable dual-write at runtime
     */
    setEnabled(enabled: boolean): void;
    /**
     * Clear write log
     */
    clearLog(): void;
}
export { DualWriteManager, DualWriteConfig, WriteOperation };
//# sourceMappingURL=dualWrite.d.ts.map