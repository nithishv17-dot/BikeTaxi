import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AuthRequest } from '../types';
import { ApiError } from './errorHandler';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

export interface JwtPayload {
  userId: string;
  role: string;
}

export const authMiddleware = (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  const token = req.headers.authorization?.split(' ')[1];

  if (!token) {
    throw new ApiError(401, 'No token provided');
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as JwtPayload;
    req.userId = decoded.userId;
    next();
  } catch (error) {
    throw new ApiError(401, 'Invalid token');
  }
};

export const generateToken = (userId: string, role: string): string => {
  return jwt.sign({ userId, role }, JWT_SECRET, { expiresIn: '24h' });
};
