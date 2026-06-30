import { Router, Response } from 'express';
import { AuthRequest } from '../types';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/authMiddleware';
import { ApiError } from '../middleware/errorHandler';
import { RideRequestSchema, UpdateRideSchema, RatingSchema } from '../schemas';
import { createLogger } from '../utils/logger';
import { RideStatus } from '@prisma/client';

const router = Router();
const logger = createLogger('rides');

// Request a new ride
router.post('/request', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const input = RideRequestSchema.parse(req.body);

    const ride = await prisma.ride.create({
      data: {
        riderId: req.userId!,
        pickupAddress: input.pickupLocation.address,
        pickupLatitude: input.pickupLocation.latitude,
        pickupLongitude: input.pickupLocation.longitude,
        pickupPlaceId: input.pickupLocation.placeId,
        dropAddress: input.dropoffLocation.address,
        dropLatitude: input.dropoffLocation.latitude,
        dropLongitude: input.dropoffLocation.longitude,
        dropPlaceId: input.dropoffLocation.placeId,
        paymentMethod: input.paymentMethod || 'CASH',
        initialFare: input.initialFare || 0,
        estimatedFare: input.initialFare || 0,
        status: RideStatus.REQUESTED,
        negotiationStatus: 'OPEN',
        negotiationExpiresAt: new Date(Date.now() + 30000), // 30 seconds
      },
      include: { rider: true },
    });

    logger.info({ rideId: ride.id }, 'Ride requested');

    res.status(201).json({ data: ride });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Ride request error');
    throw new ApiError(500, 'Failed to request ride');
  }
});

// Get active ride for user
router.get('/active/current', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const ride = await prisma.ride.findFirst({
      where: {
        riderId: req.userId,
        status: {
          in: [RideStatus.REQUESTED, RideStatus.NEGOTIATING, RideStatus.ACCEPTED, RideStatus.STARTED],
        },
      },
      include: {
        rider: true,
        driver: true,
        offers: true,
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({ data: ride || null });
  } catch (error) {
    logger.error({ error }, 'Get active ride error');
    throw new ApiError(500, 'Failed to get active ride');
  }
});

// Accept a ride (driver action)
router.post('/:id/accept', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;

    const ride = await prisma.ride.findUnique({
      where: { id },
      include: { driver: true },
    });

    if (!ride) {
      throw new ApiError(404, 'Ride not found');
    }

    if (ride.driverId) {
      throw new ApiError(400, 'Ride already has a driver');
    }

    const updatedRide = await prisma.ride.update({
      where: { id },
      data: {
        driverId: req.userId,
        status: RideStatus.ACCEPTED,
        acceptedAt: new Date(),
      },
      include: { rider: true, driver: true, offers: true },
    });

    logger.info({ rideId: id, driverId: req.userId }, 'Ride accepted');

    res.json({ data: updatedRide });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Accept ride error');
    throw new ApiError(500, 'Failed to accept ride');
  }
});

// Start ride (driver action)
router.post('/:id/start', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const { otpVerified } = req.body;

    const ride = await prisma.ride.findUnique({
      where: { id },
    });

    if (!ride) {
      throw new ApiError(404, 'Ride not found');
    }

    if (ride.driverId !== req.userId) {
      throw new ApiError(403, 'Only the assigned driver can start this ride');
    }

    const updatedRide = await prisma.ride.update({
      where: { id },
      data: {
        status: RideStatus.STARTED,
        otpVerified: otpVerified || false,
        startedAt: new Date(),
      },
      include: { rider: true, driver: true },
    });

    logger.info({ rideId: id }, 'Ride started');

    res.json({ data: updatedRide });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Start ride error');
    throw new ApiError(500, 'Failed to start ride');
  }
});

// Complete ride (driver action)
router.post('/:id/complete', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const { finalFare, paymentStatus } = req.body;

    const ride = await prisma.ride.findUnique({
      where: { id },
    });

    if (!ride) {
      throw new ApiError(404, 'Ride not found');
    }

    if (ride.driverId !== req.userId) {
      throw new ApiError(403, 'Only the assigned driver can complete this ride');
    }

    const updatedRide = await prisma.ride.update({
      where: { id },
      data: {
        status: RideStatus.COMPLETED,
        finalFare: finalFare || ride.estimatedFare,
        paymentStatus: paymentStatus || 'PENDING',
        completedAt: new Date(),
      },
      include: { rider: true, driver: true },
    });

    logger.info({ rideId: id }, 'Ride completed');

    res.json({ data: updatedRide });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Complete ride error');
    throw new ApiError(500, 'Failed to complete ride');
  }
});

// Rate ride
router.post('/:id/rate', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const input = RatingSchema.parse(req.body);

    const ride = await prisma.ride.findUnique({
      where: { id },
    });

    if (!ride) {
      throw new ApiError(404, 'Ride not found');
    }

    // Determine who is rating whom
    const isRider = ride.riderId === req.userId;
    const isDriver = ride.driverId === req.userId;

    if (!isRider && !isDriver) {
      throw new ApiError(403, 'Only ride participants can rate');
    }

    // Create rating record
    await prisma.rating.create({
      data: {
        rideId: id,
        ratedById: req.userId!,
        ratedUserId: isRider ? ride.driverId! : ride.riderId,
        rating: input.rating,
        comment: input.comment,
      },
    });

    // Update ride rating
    const updatedRide = await prisma.ride.update({
      where: { id },
      data: isRider
        ? { driverRating: input.rating }
        : { riderRating: input.rating },
      include: { rider: true, driver: true },
    });

    logger.info({ rideId: id, rating: input.rating }, 'Ride rated');

    res.json({ data: updatedRide });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Rate ride error');
    throw new ApiError(500, 'Failed to rate ride');
  }
});

// Get ride history
router.get('/user/:userId/history', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const { userId } = req.params;
    const { page = 1, limit = 10 } = req.query;

    const skip = (Number(page) - 1) * Number(limit);

    const rides = await prisma.ride.findMany({
      where: {
        OR: [{ riderId: userId }, { driverId: userId }],
        status: RideStatus.COMPLETED,
      },
      include: { rider: true, driver: true },
      orderBy: { completedAt: 'desc' },
      skip,
      take: Number(limit),
    });

    const total = await prisma.ride.count({
      where: {
        OR: [{ riderId: userId }, { driverId: userId }],
        status: RideStatus.COMPLETED,
      },
    });

    res.json({
      data: rides,
      pagination: { page: Number(page), limit: Number(limit), total },
    });
  } catch (error) {
    logger.error({ error }, 'Get history error');
    throw new ApiError(500, 'Failed to get ride history');
  }
});

// Get dashboard stats
router.get('/dashboard', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.userId },
    });

    if (!user) {
      throw new ApiError(404, 'User not found');
    }

    // Get stats for drivers
    if (user.role === 'DRIVER') {
      const completedRides = await prisma.ride.findMany({
        where: {
          driverId: req.userId,
          status: RideStatus.COMPLETED,
        },
      });

      const totalEarnings = completedRides.reduce((sum, ride) => sum + (ride.finalFare || 0), 0);

      res.json({
        data: {
          totalRides: completedRides.length,
          totalEarnings,
          averageRating: user.averageRating,
          activeRide: null,
        },
      });
    } else {
      // Get stats for riders
      res.json({
        data: {
          totalRides: user.totalRides,
          averageRating: user.averageRating,
        },
      });
    }
  } catch (error) {
    if (error instanceof ApiError) throw error;
    logger.error({ error }, 'Dashboard error');
    throw new ApiError(500, 'Failed to get dashboard data');
  }
});

export default router;
