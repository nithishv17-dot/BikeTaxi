import { PrismaClient } from '@prisma/client';
import { createLogger } from './logger';

const logger = createLogger('prisma');

const globalForPrisma = global as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ||
  new PrismaClient({
    log: [
      { emit: 'event', level: 'query' },
      { emit: 'stdout', level: 'error' },
      { emit: 'stdout', level: 'warn' },
    ],
  });

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}

// Log queries in development
prisma.$on('query', (e) => {
  logger.debug({
    query: e.query,
    duration: e.duration,
  });
});
