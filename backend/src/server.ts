import dotenv from 'dotenv';
import { createApp } from './app';
import { createLogger } from './utils/logger';
import { prisma } from './utils/prisma';

dotenv.config();

const logger = createLogger('server');
const PORT = process.env.PORT || 5000;

const startServer = async () => {
  try {
    // Test Prisma connection
    await prisma.$connect();
    logger.info('Connected to PostgreSQL via Prisma');

    const app = createApp();

    const server = app.listen(PORT, () => {
      logger.info(`TypeScript backend server running on port ${PORT}`);
    });

    // Graceful shutdown
    const shutdown = async () => {
      logger.info('Shutting down gracefully...');
      server.close(async () => {
        await prisma.$disconnect();
        logger.info('Server closed');
        process.exit(0);
      });
    };

    process.on('SIGTERM', shutdown);
    process.on('SIGINT', shutdown);
  } catch (error) {
    logger.error({ error }, 'Failed to start server');
    process.exit(1);
  }
};

startServer();
