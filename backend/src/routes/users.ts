import { Router, Response } from 'express';
import bcrypt from 'bcryptjs';
import { AuthRequest } from '../types';
import { prisma } from '../utils/prisma';
import { authMiddleware, generateToken } from '../middleware/authMiddleware';
import { ApiError } from '../middleware/errorHandler';
import { LoginSchema, RegisterSchema } from '../schemas';
import { createLogger } from '../utils/logger';

const router = Router();
const logger = createLogger('users');

router.post('/register', async (req: AuthRequest, res: Response) => {
  try {
    const input = RegisterSchema.parse(req.body);

    // Check if user already exists
    const existing = await prisma.user.findUnique({
      where: { phone: input.phone },
    });

    if (existing) {
      throw new ApiError(409, 'User with this phone already exists');
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(input.password, 10);

    // Create user
    const user = await prisma.user.create({
      data: {
        name: input.name,
        phone: input.phone,
        password: hashedPassword,
        role: input.role,
        isVerified: true,
      },
    });

    const token = generateToken(user.id, user.role);

    res.status(201).json({
      data: {
        user: {
          id: user.id,
          name: user.name,
          phone: user.phone,
          role: user.role,
        },
        token,
      },
    });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Registration error');
    throw new ApiError(500, 'Registration failed');
  }
});

router.post('/login', async (req: AuthRequest, res: Response) => {
  try {
    const input = LoginSchema.parse(req.body);

    const user = await prisma.user.findUnique({
      where: { phone: input.phone },
    });

    if (!user) {
      throw new ApiError(401, 'Invalid phone or password');
    }

    const passwordMatch = await bcrypt.compare(input.password, user.password);

    if (!passwordMatch) {
      throw new ApiError(401, 'Invalid phone or password');
    }

    const token = generateToken(user.id, user.role);

    res.json({
      data: {
        user: {
          id: user.id,
          name: user.name,
          phone: user.phone,
          role: user.role,
        },
        token,
      },
    });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Login error');
    throw new ApiError(500, 'Login failed');
  }
});

router.get('/me', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: {
        id: true,
        name: true,
        phone: true,
        role: true,
        email: true,
        averageRating: true,
        totalRides: true,
        isAvailable: true,
      },
    });

    if (!user) {
      throw new ApiError(404, 'User not found');
    }

    res.json({ data: user });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Get user error');
    throw new ApiError(500, 'Failed to get user');
  }
});

router.patch('/me', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { name, email, profileImage } = req.body;

    const user = await prisma.user.update({
      where: { id: req.userId },
      data: {
        ...(name && { name }),
        ...(email && { email }),
        ...(profileImage && { profileImage }),
      },
      select: {
        id: true,
        name: true,
        phone: true,
        email: true,
        profileImage: true,
      },
    });

    res.json({ data: user });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Update user error');
    throw new ApiError(500, 'Failed to update user');
  }
});

router.post('/location', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { latitude, longitude } = req.body;

    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      throw new ApiError(400, 'Invalid location data');
    }

    const user = await prisma.user.update({
      where: { id: req.userId },
      data: {
        latitude,
        longitude,
        lastLocationUpdate: new Date(),
      },
      select: {
        id: true,
        latitude: true,
        longitude: true,
        lastLocationUpdate: true,
      },
    });

    res.json({ data: user });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Update location error');
    throw new ApiError(500, 'Failed to update location');
  }
});

export default router;
