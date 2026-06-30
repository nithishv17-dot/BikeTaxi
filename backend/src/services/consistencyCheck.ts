import { PrismaClient } from '@prisma/client';
import mongoose from 'mongoose';
import { logger } from '../utils/logger';

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

class ConsistencyCheckService {
  constructor(
    private prisma: PrismaClient,
    private mongoUserModel: any,
    private mongoRideModel: any
  ) {}

  async checkUserConsistency(): Promise<ConsistencyReport> {
    const mongoUsers = await this.mongoUserModel.find({}).lean();
    const postgresUsers = await this.prisma.user.findMany();
    return this.compareCollections(mongoUsers, postgresUsers, 'User');
  }

  async checkRideConsistency(): Promise<ConsistencyReport> {
    const mongoRides = await this.mongoRideModel.find({}).lean();
    const postgresRides = await this.prisma.ride.findMany();
    return this.compareCollections(mongoRides, postgresRides, 'Ride');
  }

  private compareCollections(
    mongoRecords: any[],
    postgresRecords: any[],
    entityType: string
  ): ConsistencyReport {
    const inconsistencies: InconsistencyRecord[] = [];

    const mongoMap = new Map(
      mongoRecords.map(r => [(r._id || r.id)?.toString(), r])
    );
    const postgresMap = new Map(
      postgresRecords.map(r => [r.id?.toString(), r])
    );

    let matchingCount = 0;
    for (const [id, mongoRecord] of mongoMap) {
      const postgresRecord = postgresMap.get(id);
      if (postgresRecord) {
        matchingCount++;
        const fieldDiffs = this.findFieldDifferences(
          mongoRecord,
          postgresRecord,
          entityType
        );
        if (fieldDiffs.length > 0) {
          fieldDiffs.forEach(diff => {
            inconsistencies.push({ id, ...diff });
          });
        }
      }
    }

    const mongoOnlyCount = mongoMap.size - matchingCount;
    const postgresOnlyCount = postgresMap.size - matchingCount;

    const overallStatus =
      mongoOnlyCount === 0 && postgresOnlyCount === 0 && inconsistencies.length === 0
        ? 'consistent'
        : mongoOnlyCount > 0 || postgresOnlyCount > 0
        ? 'partial'
        : 'inconsistent';

    return {
      timestamp: new Date(),
      entityType,
      totalMongoRecords: mongoRecords.length,
      totalPostgresRecords: postgresRecords.length,
      matching: matchingCount,
      mongoOnly: mongoOnlyCount,
      postgresOnly: postgresOnlyCount,
      inconsistencies,
      overallStatus,
    };
  }

  private findFieldDifferences(
    mongoRecord: any,
    postgresRecord: any,
    entityType: string
  ): Omit<InconsistencyRecord, 'id'>[] {
    const diffs: Omit<InconsistencyRecord, 'id'>[] = [];
    const fieldsToCompare = this.getComparisonFields(entityType);

    for (const field of fieldsToCompare) {
      const mongoValue = mongoRecord[field];
      const postgresValue = postgresRecord[field];

      const normalizedMongo = this.normalizeValue(mongoValue);
      const normalizedPostgres = this.normalizeValue(postgresValue);

      if (JSON.stringify(normalizedMongo) !== JSON.stringify(normalizedPostgres)) {
        diffs.push({
          field,
          mongoValue: normalizedMongo,
          postgresValue: normalizedPostgres,
        });
      }
    }

    return diffs;
  }

  private getComparisonFields(entityType: string): string[] {
    const fieldMap: { [key: string]: string[] } = {
      User: ['name', 'phone', 'role', 'email', 'isAvailable', 'isVerified'],
      Ride: [
        'riderId',
        'driverId',
        'pickupAddress',
        'dropAddress',
        'status',
        'paymentMethod',
        'paymentStatus',
      ],
    };
    return fieldMap[entityType] || [];
  }

  private normalizeValue(value: any): any {
    if (value === null || value === undefined) {
      return value;
    }
    if (mongoose.Types.ObjectId.isValid(value)) {
      return value.toString();
    }
    if (value instanceof Date) {
      return value.toISOString();
    }
    return value;
  }

  async generateFullReport(): Promise<{
    users: ConsistencyReport;
    rides: ConsistencyReport;
    overall: string;
  }> {
    const userReport = await this.checkUserConsistency();
    const rideReport = await this.checkRideConsistency();

    const overall =
      userReport.overallStatus === 'consistent' && rideReport.overallStatus === 'consistent'
        ? 'FULLY_CONSISTENT'
        : userReport.overallStatus === 'consistent' ||
          rideReport.overallStatus === 'consistent'
        ? 'PARTIALLY_CONSISTENT'
        : 'INCONSISTENT';

    return { users: userReport, rides: rideReport, overall };
  }

  async getMigrationCandidates(): Promise<{
    userIds: string[];
    rideIds: string[];
  }> {
    const userReport = await this.checkUserConsistency();
    const rideReport = await this.checkRideConsistency();

    const mongoUsers = await this.mongoUserModel.find({}).lean();
    const mongoRides = await this.mongoRideModel.find({}).lean();

    return {
      userIds: mongoUsers
        .filter(u => {
          const mongoId = (u._id || u.id)?.toString();
          return !userReport.inconsistencies.some(inc => inc.id === mongoId);
        })
        .map(u => (u._id || u.id)?.toString()),
      rideIds: mongoRides
        .filter(r => {
          const mongoId = (r._id || r.id)?.toString();
          return !rideReport.inconsistencies.some(inc => inc.id === mongoId);
        })
        .map(r => (r._id || r.id)?.toString()),
    };
  }
}

export { ConsistencyCheckService, ConsistencyReport, InconsistencyRecord };
