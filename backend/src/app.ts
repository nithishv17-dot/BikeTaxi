import express, { Express, Request, Response, NextFunction } from 'express';
import cors from 'cors';
import 'express-async-errors';
import { createLogger } from './utils/logger';
import { errorHandler } from './middleware/errorHandler';
import userRoutes from './routes/users';
import rideRoutes from './routes/rides';
import driverRoutes from './routes/drivers';

const logger = createLogger('app');

export const createApp = (): Express => {
  const app = express();

  // Middleware
  app.use(cors());
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  // Request logging middleware
  app.use((req: Request, res: Response, next: NextFunction) => {
    logger.info({
      method: req.method,
      path: req.path,
      ip: req.ip,
    });
    next();
  });

  // Health check endpoint
  app.get('/health', (req: Request, res: Response) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  // API Routes
  app.use('/api/users', userRoutes);
  app.use('/api/rides', rideRoutes);
  app.use('/api/drivers', driverRoutes);

  // 404 handler
  app.use((req: Request, res: Response) => {
    res.status(404).json({ error: 'Route not found' });
  });

  // Error handler (must be last)
  app.use(errorHandler);

  return app;
};
