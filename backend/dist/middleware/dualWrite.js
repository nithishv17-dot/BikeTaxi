"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DualWriteManager = void 0;
const logger_1 = require("../utils/logger");
class DualWriteManager {
    constructor(prisma) {
        this.writeLog = [];
        this.consistencyCheckInterval = null;
        this.prisma = prisma;
        this.config = {
            enabled: process.env.DUAL_WRITE_ENABLED === 'true',
            mongoFirst: process.env.MONGO_FIRST_WRITE === 'true',
            postgresFirst: process.env.POSTGRES_FIRST_WRITE === 'true',
            failureMode: process.env.DUAL_WRITE_FAILURE_MODE || 'lenient',
            logDetails: process.env.DUAL_WRITE_LOG_DETAILS === 'true',
        };
    }
    /**
     * Write a user to both databases
     */
    async writeUser(mongoModel, userData, operation = 'create') {
        if (!this.config.enabled) {
            // MongoDB only (Phase 1-5 behavior)
            const mongoResult = await this.writeToMongo(mongoModel, userData, operation);
            return { mongo: mongoResult, postgres: null };
        }
        const writeOp = {
            entity: 'User',
            operation,
            mongoStatus: 'pending',
            postgresStatus: 'pending',
            timestamp: new Date(),
        };
        let mongoResult, postgresResult;
        let mongoError, postgresError;
        try {
            // Write to MongoDB
            writeOp.mongoStatus = 'pending';
            mongoResult = await this.writeToMongo(mongoModel, userData, operation);
            writeOp.mongoStatus = 'success';
            // Write to PostgreSQL
            writeOp.postgresStatus = 'pending';
            postgresResult = await this.writeUserToPostgres(userData, operation);
            writeOp.postgresStatus = 'success';
            if (this.config.logDetails) {
                logger_1.logger.info('Dual-write successful for user', {
                    operation,
                    mongoId: mongoResult?._id,
                    postgresId: postgresResult?.id,
                });
            }
        }
        catch (error) {
            if (error.source === 'mongo') {
                mongoError = error.message;
                writeOp.mongoStatus = 'failed';
                writeOp.mongoError = error.message;
            }
            else if (error.source === 'postgres') {
                postgresError = error.message;
                writeOp.postgresStatus = 'failed';
                writeOp.postgresError = error.message;
            }
            if (this.config.failureMode === 'strict') {
                writeOp.postgresStatus = 'failed';
                throw new Error(`Dual-write failed: ${mongoError || postgresError}`);
            }
        }
        this.writeLog.push(writeOp);
        return { mongo: mongoResult, postgres: postgresResult };
    }
    /**
     * Write a ride to both databases
     */
    async writeRide(mongoModel, rideData, operation = 'create') {
        if (!this.config.enabled) {
            const mongoResult = await this.writeToMongo(mongoModel, rideData, operation);
            return { mongo: mongoResult, postgres: null };
        }
        const writeOp = {
            entity: 'Ride',
            operation,
            mongoStatus: 'pending',
            postgresStatus: 'pending',
            timestamp: new Date(),
        };
        let mongoResult, postgresResult;
        try {
            writeOp.mongoStatus = 'pending';
            mongoResult = await this.writeToMongo(mongoModel, rideData, operation);
            writeOp.mongoStatus = 'success';
            writeOp.postgresStatus = 'pending';
            postgresResult = await this.writeRideToPostgres(rideData, operation);
            writeOp.postgresStatus = 'success';
            if (this.config.logDetails) {
                logger_1.logger.info('Dual-write successful for ride', {
                    operation,
                    mongoId: mongoResult?._id,
                    postgresId: postgresResult?.id,
                });
            }
        }
        catch (error) {
            if (this.config.failureMode === 'strict') {
                throw error;
            }
            logger_1.logger.warn('Dual-write partial failure', { error: error.message });
        }
        this.writeLog.push(writeOp);
        return { mongo: mongoResult, postgres: postgresResult };
    }
    /**
     * Write to MongoDB
     */
    async writeToMongo(model, data, operation) {
        try {
            if (operation === 'create') {
                const document = new model(data);
                return await document.save();
            }
            else {
                const { _id, ...updateData } = data;
                return await model.findByIdAndUpdate(_id, updateData, { new: true });
            }
        }
        catch (error) {
            error.source = 'mongo';
            throw error;
        }
    }
    /**
     * Write user to PostgreSQL
     */
    async writeUserToPostgres(userData, operation) {
        try {
            if (operation === 'create') {
                return await this.prisma.user.create({
                    data: {
                        id: userData._id?.toString() || undefined,
                        name: userData.name,
                        phone: userData.phone,
                        password: userData.password,
                        role: userData.role || 'USER',
                        email: userData.email,
                        latitude: userData.latitude,
                        longitude: userData.longitude,
                        isAvailable: userData.isAvailable || false,
                        isVerified: userData.isVerified || false,
                        averageRating: userData.averageRating || 0,
                        totalRatings: userData.totalRatings || 0,
                        totalRides: userData.totalRides || 0,
                    },
                });
            }
            else {
                return await this.prisma.user.update({
                    where: { id: userData._id?.toString() },
                    data: {
                        name: userData.name,
                        email: userData.email,
                        latitude: userData.latitude,
                        longitude: userData.longitude,
                        isAvailable: userData.isAvailable,
                        isVerified: userData.isVerified,
                    },
                });
            }
        }
        catch (error) {
            error.source = 'postgres';
            throw error;
        }
    }
    /**
     * Write ride to PostgreSQL
     */
    async writeRideToPostgres(rideData, operation) {
        try {
            if (operation === 'create') {
                return await this.prisma.ride.create({
                    data: {
                        id: rideData._id?.toString() || undefined,
                        riderId: rideData.riderId?.toString(),
                        driverId: rideData.driverId?.toString(),
                        pickupAddress: rideData.pickupAddress,
                        pickupLatitude: rideData.pickupLatitude,
                        pickupLongitude: rideData.pickupLongitude,
                        dropAddress: rideData.dropAddress,
                        dropLatitude: rideData.dropLatitude,
                        dropLongitude: rideData.dropLongitude,
                        estimatedFare: rideData.estimatedFare || 0,
                        initialFare: rideData.initialFare || 0,
                        status: rideData.status || 'REQUESTED',
                        paymentMethod: rideData.paymentMethod || 'CASH',
                        paymentStatus: 'PENDING',
                    },
                });
            }
            else {
                return await this.prisma.ride.update({
                    where: { id: rideData._id?.toString() },
                    data: {
                        status: rideData.status,
                        driverId: rideData.driverId?.toString(),
                        finalFare: rideData.finalFare,
                        paymentStatus: rideData.paymentStatus,
                    },
                });
            }
        }
        catch (error) {
            error.source = 'postgres';
            throw error;
        }
    }
    /**
     * Get write operation log
     */
    getWriteLog(limit = 100) {
        return this.writeLog.slice(-limit);
    }
    /**
     * Get migration statistics
     */
    getMigrationStats() {
        const total = this.writeLog.length;
        const successCount = this.writeLog.filter(w => w.mongoStatus === 'success' && w.postgresStatus === 'success').length;
        const mongoFailures = this.writeLog.filter(w => w.mongoStatus === 'failed').length;
        const postgresFailures = this.writeLog.filter(w => w.postgresStatus === 'failed').length;
        return {
            totalOperations: total,
            successfulDualWrites: successCount,
            mongoOnlySuccesses: this.writeLog.filter(w => w.mongoStatus === 'success' && w.postgresStatus !== 'success').length,
            postgresOnlySuccesses: this.writeLog.filter(w => w.postgresStatus === 'success' && w.mongoStatus !== 'success').length,
            mongoFailures,
            postgresFailures,
            successRate: total > 0 ? ((successCount / total) * 100).toFixed(2) + '%' : 'N/A',
            dualWriteEnabled: this.config.enabled,
        };
    }
    /**
     * Enable/disable dual-write at runtime
     */
    setEnabled(enabled) {
        this.config.enabled = enabled;
        logger_1.logger.info('Dual-write setting changed', { enabled });
    }
    /**
     * Clear write log
     */
    clearLog() {
        this.writeLog = [];
    }
}
exports.DualWriteManager = DualWriteManager;
//# sourceMappingURL=dualWrite.js.map