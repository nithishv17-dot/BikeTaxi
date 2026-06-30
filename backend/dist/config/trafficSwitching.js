"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TrafficSwitchingManager = void 0;
exports.getTrafficSwitchingManager = getTrafficSwitchingManager;
const logger_1 = require("../utils/logger");
class TrafficSwitchingManager {
    constructor() {
        this.stats = {
            requestsToPostgres: 0,
            requestsToMongodb: 0,
            startTime: new Date(),
        };
        this.config = {
            postgresPercentage: parseInt(process.env.POSTGRES_TRAFFIC_PERCENT || '0'),
            mongodbPercentage: parseInt(process.env.MONGODB_TRAFFIC_PERCENT || '100'),
            dualWriteEnabled: process.env.DUAL_WRITE_ENABLED === 'true',
            primaryDatabase: process.env.DATABASE_TYPE || 'mongodb',
            fallbackDatabase: process.env.FALLBACK_DATABASE || 'mongodb',
            logTrafficDecisions: process.env.LOG_TRAFFIC_DECISIONS === 'true',
        };
        this.validateConfig();
        this.logStartup();
    }
    /**
     * Validate traffic percentages sum to 100
     */
    validateConfig() {
        const total = this.config.postgresPercentage + this.config.mongodbPercentage;
        if (total !== 100) {
            logger_1.logger.warn('Traffic percentages do not sum to 100', {
                postgres: this.config.postgresPercentage,
                mongodb: this.config.mongodbPercentage,
                total,
            });
        }
    }
    /**
     * Log startup configuration
     */
    logStartup() {
        logger_1.logger.info('Traffic Switching Manager initialized', {
            postgresPercentage: this.config.postgresPercentage,
            mongodbPercentage: this.config.mongodbPercentage,
            dualWriteEnabled: this.config.dualWriteEnabled,
            primaryDatabase: this.config.primaryDatabase,
        });
    }
    /**
     * Determine which database to route request to
     */
    routeRead() {
        const random = Math.random() * 100;
        if (random < this.config.postgresPercentage) {
            this.stats.requestsToPostgres++;
            if (this.config.logTrafficDecisions) {
                logger_1.logger.debug('Routing read to PostgreSQL', {
                    random,
                    threshold: this.config.postgresPercentage,
                });
            }
            return 'postgres';
        }
        else {
            this.stats.requestsToMongodb++;
            if (this.config.logTrafficDecisions) {
                logger_1.logger.debug('Routing read to MongoDB', {
                    random,
                    threshold: this.config.postgresPercentage,
                });
            }
            return 'mongodb';
        }
    }
    /**
     * Get current traffic configuration
     */
    getConfig() {
        return { ...this.config };
    }
    /**
     * Update traffic configuration at runtime
     */
    setTrafficPercentage(postgresPercent, mongoPercent) {
        if (postgresPercent + mongoPercent !== 100) {
            throw new Error('Traffic percentages must sum to 100');
        }
        this.config.postgresPercentage = postgresPercent;
        this.config.mongodbPercentage = mongoPercent;
        logger_1.logger.info('Traffic percentages updated', {
            postgres: postgresPercent,
            mongodb: mongoPercent,
        });
    }
    /**
     * Switch to full PostgreSQL (100% traffic)
     */
    switchToPostgres() {
        this.setTrafficPercentage(100, 0);
        this.config.primaryDatabase = 'postgres';
        logger_1.logger.info('Switched to PostgreSQL (100% traffic)');
    }
    /**
     * Switch back to MongoDB (100% traffic)
     */
    switchToMongodb() {
        this.setTrafficPercentage(0, 100);
        this.config.primaryDatabase = 'mongodb';
        logger_1.logger.info('Switched to MongoDB (100% traffic)');
    }
    /**
     * Gradual traffic switch stages
     */
    setStage(stage) {
        switch (stage) {
            case 'stage1':
                this.setTrafficPercentage(10, 90);
                logger_1.logger.info('Traffic Switch: Stage 1 (10% PostgreSQL)');
                break;
            case 'stage2':
                this.setTrafficPercentage(50, 50);
                logger_1.logger.info('Traffic Switch: Stage 2 (50% PostgreSQL)');
                break;
            case 'stage3':
                this.setTrafficPercentage(100, 0);
                logger_1.logger.info('Traffic Switch: Stage 3 (100% PostgreSQL)');
                break;
            case 'rollback':
                this.setTrafficPercentage(0, 100);
                logger_1.logger.info('Traffic Switch: Rollback (100% MongoDB)');
                break;
        }
    }
    /**
     * Get traffic statistics
     */
    getStats() {
        const total = this.stats.requestsToPostgres + this.stats.requestsToMongodb;
        const postgresPerc = total > 0 ? (this.stats.requestsToPostgres / total) * 100 : 0;
        const mongoPerc = total > 0 ? (this.stats.requestsToMongodb / total) * 100 : 0;
        const uptime = new Date().getTime() - this.stats.startTime.getTime();
        return {
            postgresRequests: this.stats.requestsToPostgres,
            mongodbRequests: this.stats.requestsToMongodb,
            totalRequests: total,
            postgresPercentage: parseFloat(postgresPerc.toFixed(2)),
            mongodbPercentage: parseFloat(mongoPerc.toFixed(2)),
            uptime: `${Math.floor(uptime / 1000)}s`,
        };
    }
    /**
     * Reset statistics
     */
    resetStats() {
        this.stats = {
            requestsToPostgres: 0,
            requestsToMongodb: 0,
            startTime: new Date(),
        };
        logger_1.logger.info('Traffic statistics reset');
    }
    /**
     * Check if traffic switching is in progress
     */
    isSwitchingInProgress() {
        return (this.config.postgresPercentage > 0 &&
            this.config.postgresPercentage < 100);
    }
    /**
     * Get current phase status
     */
    getPhaseStatus() {
        let phase;
        let description;
        if (this.config.postgresPercentage === 0) {
            phase = 'setup';
            description = 'MongoDB primary, PostgreSQL as backup';
        }
        else if (this.config.postgresPercentage === 10) {
            phase = 'stage1';
            description = '10% traffic on PostgreSQL for initial validation';
        }
        else if (this.config.postgresPercentage === 50) {
            phase = 'stage2';
            description = '50% traffic split between databases';
        }
        else if (this.config.postgresPercentage === 100) {
            phase = 'complete';
            description = 'PostgreSQL primary, MongoDB as backup';
        }
        else if (this.config.postgresPercentage < this.config.mongodbPercentage) {
            phase = 'stage1';
            description = `${this.config.postgresPercentage}% traffic on PostgreSQL`;
        }
        else {
            phase = 'rollback';
            description = 'Rolled back to MongoDB primary';
        }
        return {
            phase,
            description,
            postgresTraffic: this.config.postgresPercentage,
            mongodbTraffic: this.config.mongodbPercentage,
        };
    }
}
exports.TrafficSwitchingManager = TrafficSwitchingManager;
// Singleton instance
let instance;
function getTrafficSwitchingManager() {
    if (!instance) {
        instance = new TrafficSwitchingManager();
    }
    return instance;
}
//# sourceMappingURL=trafficSwitching.js.map