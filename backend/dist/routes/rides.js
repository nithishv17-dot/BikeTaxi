"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const prisma_1 = require("../utils/prisma");
const authMiddleware_1 = require("../middleware/authMiddleware");
const errorHandler_1 = require("../middleware/errorHandler");
const schemas_1 = require("../schemas");
const logger_1 = require("../utils/logger");
const client_1 = require("@prisma/client");
const router = (0, express_1.Router)();
const logger = (0, logger_1.createLogger)('rides');
// Request a new ride
router.post('/request', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const input = schemas_1.RideRequestSchema.parse(req.body);
        const ride = await prisma_1.prisma.ride.create({
            data: {
                riderId: req.userId,
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
                status: client_1.RideStatus.REQUESTED,
                negotiationStatus: 'OPEN',
                negotiationExpiresAt: new Date(Date.now() + 30000), // 30 seconds
            },
            include: { rider: true },
        });
        logger.info({ rideId: ride.id }, 'Ride requested');
        res.status(201).json({ data: ride });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Ride request error');
        throw new errorHandler_1.ApiError(500, 'Failed to request ride');
    }
});
// Get active ride for user
router.get('/active/current', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const ride = await prisma_1.prisma.ride.findFirst({
            where: {
                riderId: req.userId,
                status: {
                    in: [client_1.RideStatus.REQUESTED, client_1.RideStatus.NEGOTIATING, client_1.RideStatus.ACCEPTED, client_1.RideStatus.STARTED],
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
    }
    catch (error) {
        logger.error({ error }, 'Get active ride error');
        throw new errorHandler_1.ApiError(500, 'Failed to get active ride');
    }
});
// Accept a ride (driver action)
router.post('/:id/accept', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        const ride = await prisma_1.prisma.ride.findUnique({
            where: { id },
            include: { driver: true },
        });
        if (!ride) {
            throw new errorHandler_1.ApiError(404, 'Ride not found');
        }
        if (ride.driverId) {
            throw new errorHandler_1.ApiError(400, 'Ride already has a driver');
        }
        const updatedRide = await prisma_1.prisma.ride.update({
            where: { id },
            data: {
                driverId: req.userId,
                status: client_1.RideStatus.ACCEPTED,
                acceptedAt: new Date(),
            },
            include: { rider: true, driver: true, offers: true },
        });
        logger.info({ rideId: id, driverId: req.userId }, 'Ride accepted');
        res.json({ data: updatedRide });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Accept ride error');
        throw new errorHandler_1.ApiError(500, 'Failed to accept ride');
    }
});
// Start ride (driver action)
router.post('/:id/start', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        const { otpVerified } = req.body;
        const ride = await prisma_1.prisma.ride.findUnique({
            where: { id },
        });
        if (!ride) {
            throw new errorHandler_1.ApiError(404, 'Ride not found');
        }
        if (ride.driverId !== req.userId) {
            throw new errorHandler_1.ApiError(403, 'Only the assigned driver can start this ride');
        }
        const updatedRide = await prisma_1.prisma.ride.update({
            where: { id },
            data: {
                status: client_1.RideStatus.STARTED,
                otpVerified: otpVerified || false,
                startedAt: new Date(),
            },
            include: { rider: true, driver: true },
        });
        logger.info({ rideId: id }, 'Ride started');
        res.json({ data: updatedRide });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Start ride error');
        throw new errorHandler_1.ApiError(500, 'Failed to start ride');
    }
});
// Complete ride (driver action)
router.post('/:id/complete', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        const { finalFare, paymentStatus } = req.body;
        const ride = await prisma_1.prisma.ride.findUnique({
            where: { id },
        });
        if (!ride) {
            throw new errorHandler_1.ApiError(404, 'Ride not found');
        }
        if (ride.driverId !== req.userId) {
            throw new errorHandler_1.ApiError(403, 'Only the assigned driver can complete this ride');
        }
        const updatedRide = await prisma_1.prisma.ride.update({
            where: { id },
            data: {
                status: client_1.RideStatus.COMPLETED,
                finalFare: finalFare || ride.estimatedFare,
                paymentStatus: paymentStatus || 'PENDING',
                completedAt: new Date(),
            },
            include: { rider: true, driver: true },
        });
        logger.info({ rideId: id }, 'Ride completed');
        res.json({ data: updatedRide });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Complete ride error');
        throw new errorHandler_1.ApiError(500, 'Failed to complete ride');
    }
});
// Rate ride
router.post('/:id/rate', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        const input = schemas_1.RatingSchema.parse(req.body);
        const ride = await prisma_1.prisma.ride.findUnique({
            where: { id },
        });
        if (!ride) {
            throw new errorHandler_1.ApiError(404, 'Ride not found');
        }
        // Determine who is rating whom
        const isRider = ride.riderId === req.userId;
        const isDriver = ride.driverId === req.userId;
        if (!isRider && !isDriver) {
            throw new errorHandler_1.ApiError(403, 'Only ride participants can rate');
        }
        // Create rating record
        await prisma_1.prisma.rating.create({
            data: {
                rideId: id,
                ratedById: req.userId,
                ratedUserId: isRider ? ride.driverId : ride.riderId,
                rating: input.rating,
                comment: input.comment,
            },
        });
        // Update ride rating
        const updatedRide = await prisma_1.prisma.ride.update({
            where: { id },
            data: isRider
                ? { driverRating: input.rating }
                : { riderRating: input.rating },
            include: { rider: true, driver: true },
        });
        logger.info({ rideId: id, rating: input.rating }, 'Ride rated');
        res.json({ data: updatedRide });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Rate ride error');
        throw new errorHandler_1.ApiError(500, 'Failed to rate ride');
    }
});
// Get ride history
router.get('/user/:userId/history', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { userId } = req.params;
        const { page = 1, limit = 10 } = req.query;
        const skip = (Number(page) - 1) * Number(limit);
        const rides = await prisma_1.prisma.ride.findMany({
            where: {
                OR: [{ riderId: userId }, { driverId: userId }],
                status: client_1.RideStatus.COMPLETED,
            },
            include: { rider: true, driver: true },
            orderBy: { completedAt: 'desc' },
            skip,
            take: Number(limit),
        });
        const total = await prisma_1.prisma.ride.count({
            where: {
                OR: [{ riderId: userId }, { driverId: userId }],
                status: client_1.RideStatus.COMPLETED,
            },
        });
        res.json({
            data: rides,
            pagination: { page: Number(page), limit: Number(limit), total },
        });
    }
    catch (error) {
        logger.error({ error }, 'Get history error');
        throw new errorHandler_1.ApiError(500, 'Failed to get ride history');
    }
});
// Get dashboard stats
router.get('/dashboard', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const user = await prisma_1.prisma.user.findUnique({
            where: { id: req.userId },
        });
        if (!user) {
            throw new errorHandler_1.ApiError(404, 'User not found');
        }
        // Get stats for drivers
        if (user.role === 'DRIVER') {
            const completedRides = await prisma_1.prisma.ride.findMany({
                where: {
                    driverId: req.userId,
                    status: client_1.RideStatus.COMPLETED,
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
        }
        else {
            // Get stats for riders
            res.json({
                data: {
                    totalRides: user.totalRides,
                    averageRating: user.averageRating,
                },
            });
        }
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Dashboard error');
        throw new errorHandler_1.ApiError(500, 'Failed to get dashboard data');
    }
});
exports.default = router;
//# sourceMappingURL=rides.js.map