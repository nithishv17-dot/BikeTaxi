/**
 * Traffic Switching Configuration
 * Enables gradual migration from MongoDB to PostgreSQL
 * Supports percentage-based traffic routing
 */
interface TrafficConfig {
    postgresPercentage: number;
    mongodbPercentage: number;
    dualWriteEnabled: boolean;
    primaryDatabase: 'mongodb' | 'postgres';
    fallbackDatabase: 'mongodb' | 'postgres';
    logTrafficDecisions: boolean;
}
declare class TrafficSwitchingManager {
    private config;
    private stats;
    constructor();
    /**
     * Validate traffic percentages sum to 100
     */
    private validateConfig;
    /**
     * Log startup configuration
     */
    private logStartup;
    /**
     * Determine which database to route request to
     */
    routeRead(): 'postgres' | 'mongodb';
    /**
     * Get current traffic configuration
     */
    getConfig(): TrafficConfig;
    /**
     * Update traffic configuration at runtime
     */
    setTrafficPercentage(postgresPercent: number, mongoPercent: number): void;
    /**
     * Switch to full PostgreSQL (100% traffic)
     */
    switchToPostgres(): void;
    /**
     * Switch back to MongoDB (100% traffic)
     */
    switchToMongodb(): void;
    /**
     * Gradual traffic switch stages
     */
    setStage(stage: 'stage1' | 'stage2' | 'stage3' | 'rollback'): void;
    /**
     * Get traffic statistics
     */
    getStats(): {
        postgresRequests: number;
        mongodbRequests: number;
        totalRequests: number;
        postgresPercentage: number;
        mongodbPercentage: number;
        uptime: string;
    };
    /**
     * Reset statistics
     */
    resetStats(): void;
    /**
     * Check if traffic switching is in progress
     */
    isSwitchingInProgress(): boolean;
    /**
     * Get current phase status
     */
    getPhaseStatus(): {
        phase: 'setup' | 'stage1' | 'stage2' | 'stage3' | 'complete' | 'rollback';
        description: string;
        postgresTraffic: number;
        mongodbTraffic: number;
    };
}
export declare function getTrafficSwitchingManager(): TrafficSwitchingManager;
export { TrafficSwitchingManager, TrafficConfig };
//# sourceMappingURL=trafficSwitching.d.ts.map