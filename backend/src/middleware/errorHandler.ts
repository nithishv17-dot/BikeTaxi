import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { createLogger } from '../utils/logger';

const logger = createLogger('errorHandler');

export class ApiError extends Error {
  constructor(
    public statusCode: number,
    message: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  logger.error({ error: err }, 'Unhandled error');

  if (err instanceof ApiError) {
    return res.status(err.statusCode).json({ error: err.message });
  }

  if (err instanceof ZodError) {
    return res.status(400).json({
      error: 'Validation error',
      details: err.errors,
    });
  }

  // Default error
  res.status(500).json({
    error: 'Internal server error',
  });
};
