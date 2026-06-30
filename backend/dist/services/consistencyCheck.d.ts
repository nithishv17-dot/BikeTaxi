import { PrismaClient } from '@prisma/client';
interface ConsistencyReport {
    timestamp: Date;
    entityType: string;
    totalMongoRecords: number;
    totalPostgresRecords: number;
    matching: number;
    mongoOnly: number;
    postgresOnly: number;
    inconsistencies: InconsistencyRecord[];
    overallStatus: 'consistent' | 'partial' | 'inconsistent';
}
interface InconsistencyRecord {
    id: string;
    field: string;
    mongoValue: any;
    postgresValue: any;
}
declare class ConsistencyCheckService {
    private prisma;
    private mongoUserModel;
    private mongoRideModel;
    constructor(prisma: PrismaClient, mongoUserModel: any, mongoRideModel: any);
    checkUserConsistency(): Promise<ConsistencyReport>;
    checkRideConsistency(): Promise<ConsistencyReport>;
    private compareCollections;
    private findFieldDifferences;
    private getComparisonFields;
    private normalizeValue;
    generateFullReport(): Promise<{
        users: ConsistencyReport;
        rides: ConsistencyReport;
        overall: string;
    }>;
    getMigrationCandidates(): Promise<{
        userIds: string[];
        rideIds: string[];
    }>;
}
export { ConsistencyCheckService, ConsistencyReport, InconsistencyRecord };
//# sourceMappingURL=consistencyCheck.d.ts.map