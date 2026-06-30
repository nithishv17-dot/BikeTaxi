"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv_1 = __importDefault(require("dotenv"));
const app_1 = require("./app");
const logger_1 = require("./utils/logger");
const prisma_1 = require("./utils/prisma");
dotenv_1.default.config();
const logger = (0, logger_1.createLogger)('server');
const PORT = process.env.PORT || 5000;
const startServer = async () => {
    try {
        // Test Prisma connection
        await prisma_1.prisma.$connect();
        logger.info('Connected to PostgreSQL via Prisma');
        const app = (0, app_1.createApp)();
        const server = app.listen(PORT, () => {
            logger.info(`TypeScript backend server running on port ${PORT}`);
        });
        // Graceful shutdown
        const shutdown = async () => {
            logger.info('Shutting down gracefully...');
            server.close(async () => {
                await prisma_1.prisma.$disconnect();
                logger.info('Server closed');
                process.exit(0);
            });
        };
        process.on('SIGTERM', shutdown);
        process.on('SIGINT', shutdown);
    }
    catch (error) {
        logger.error({ error }, 'Failed to start server');
        process.exit(1);
    }
};
startServer();
//# sourceMappingURL=server.js.map