"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const prisma_1 = require("../utils/prisma");
const authMiddleware_1 = require("../middleware/authMiddleware");
const errorHandler_1 = require("../middleware/errorHandler");
const schemas_1 = require("../schemas");
const logger_1 = require("../utils/logger");
const router = (0, express_1.Router)();
const logger = (0, logger_1.createLogger)('drivers');
// Get available drivers near a location
router.post('/list', async (req, res) => {
    try {
        const { latitude, longitude, radiusKm = 5 } = req.body;
        if (typeof latitude !== 'number' || typeof longitude !== 'number') {
            throw new errorHandler_1.ApiError(400, 'Invalid location data');
        }
        // Simple distance calculation (rough approximation)
        // In production, use PostGIS for accurate geospatial queries
        const drivers = await prisma_1.prisma.user.findMany({
            where: {
                role: 'DRIVER',
                isAvailable: true,
                isBanned: false,
                latitude: {
                    gte: latitude - radiusKm / 111,
                    lte: latitude + radiusKm / 111,
                },
                longitude: {
                    gte: longitude - radiusKm / (111 * Math.cos((latitude * Math.PI) / 180)),
                    lte: longitude + radiusKm / (111 * Math.cos((latitude * Math.PI) / 180)),
                },
            },
            select: {
                id: true,
                name: true,
                phone: true,
                latitude: true,
                longitude: true,
                averageRating: true,
                totalRides: true,
                totalRatings: true,
            },
            take: 50,
        });
        res.json({ data: drivers });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'List drivers error');
        throw new errorHandler_1.ApiError(500, 'Failed to list drivers');
    }
});
// Toggle driver availability
router.post('/toggle/:id', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        if (req.userId !== id) {
            throw new errorHandler_1.ApiError(403, 'Can only toggle your own availability');
        }
        const user = await prisma_1.prisma.user.findUnique({
            where: { id },
        });
        if (!user || user.role !== 'DRIVER') {
            throw new errorHandler_1.ApiError(404, 'Driver not found');
        }
        const updatedDriver = await prisma_1.prisma.user.update({
            where: { id },
            data: {
                isAvailable: !user.isAvailable,
            },
            select: {
                id: true,
                name: true,
                isAvailable: true,
                totalRides: true,
                averageRating: true,
            },
        });
        logger.info({ driverId: id, isAvailable: updatedDriver.isAvailable }, 'Driver availability toggled');
        res.json({ data: updatedDriver });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Toggle availability error');
        throw new errorHandler_1.ApiError(500, 'Failed to toggle availability');
    }
});
// Submit offer for a ride
router.post('/:rideId/offer', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { rideId } = req.params;
        const input = schemas_1.OfferSchema.parse(req.body);
        const ride = await prisma_1.prisma.ride.findUnique({
            where: { id: rideId },
        });
        if (!ride) {
            throw new errorHandler_1.ApiError(404, 'Ride not found');
        }
        // Check if ride is still accepting offers
        if (ride.negotiationExpiresAt && ride.negotiationExpiresAt < new Date()) {
            throw new errorHandler_1.ApiError(400, 'Negotiation window has expired');
        }
        // Check if driver already made an offer
        const existingOffer = await prisma_1.prisma.offer.findFirst({
            where: {
                rideId,
                driverId: req.userId,
            },
        });
        if (existingOffer) {
            throw new errorHandler_1.ApiError(400, 'You already have an offer for this ride');
        }
        const offer = await prisma_1.prisma.offer.create({
            data: {
                rideId,
                driverId: req.userId,
                offeredFare: input.offeredFare,
                expiresAt: new Date(Date.now() + 30000), // 30 seconds
            },
            include: {
                driver: {
                    select: {
                        id: true,
                        name: true,
                        averageRating: true,
                        totalRides: true,
                    },
                },
            },
        });
        logger.info({ rideId, driverId: req.userId, fare: input.offeredFare }, 'Offer submitted');
        res.status(201).json({ data: offer });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Submit offer error');
        throw new errorHandler_1.ApiError(500, 'Failed to submit offer');
    }
});
// Accept an offer (rider action)
router.post('/offers/:offerId/accept', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { offerId } = req.params;
        const offer = await prisma_1.prisma.offer.findUnique({
            where: { id: offerId },
            include: { ride: true },
        });
        if (!offer) {
            throw new errorHandler_1.ApiError(404, 'Offer not found');
        }
        // Verify the user is the ride requester
        if (offer.ride.riderId !== req.userId) {
            throw new errorHandler_1.ApiError(403, 'Only the ride requester can accept offers');
        }
        // Lock in the offer
        const updatedOffer = await prisma_1.prisma.offer.update({
            where: { id: offerId },
            data: {
                offerStatus: 'ACCEPTED',
                respondedAt: new Date(),
            },
            include: {
                ride: true,
                driver: {
                    select: {
                        id: true,
                        name: true,
                        phone: true,
                        averageRating: true,
                    },
                },
            },
        });
        // Update the ride with the confirmed offer
        await prisma_1.prisma.ride.update({
            where: { id: offer.rideId },
            data: {
                driverId: offer.driverId,
                offeredFare: offer.offeredFare,
                finalFare: offer.offeredFare,
                negotiationStatus: 'LOCKED',
                status: 'ACCEPTED',
            },
        });
        // Reject other offers for this ride
        await prisma_1.prisma.offer.updateMany({
            where: {
                rideId: offer.rideId,
                id: { not: offerId },
            },
            data: {
                offerStatus: 'REJECTED',
                respondedAt: new Date(),
            },
        });
        logger.info({ offerId, rideId: offer.rideId }, 'Offer accepted');
        res.json({ data: updatedOffer });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Accept offer error');
        throw new errorHandler_1.ApiError(500, 'Failed to accept offer');
    }
});
// Get offers for a ride
router.get('/:rideId/offers', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { rideId } = req.params;
        const ride = await prisma_1.prisma.ride.findUnique({
            where: { id: rideId },
        });
        if (!ride) {
            throw new errorHandler_1.ApiError(404, 'Ride not found');
        }
        // Verify user is the ride requester
        if (ride.riderId !== req.userId) {
            throw new errorHandler_1.ApiError(403, 'Only the ride requester can view offers');
        }
        const offers = await prisma_1.prisma.offer.findMany({
            where: { rideId },
            include: {
                driver: {
                    select: {
                        id: true,
                        name: true,
                        phone: true,
                        averageRating: true,
                        totalRides: true,
                        totalRatings: true,
                    },
                },
            },
            orderBy: { offeredFare: 'asc' },
        });
        res.json({ data: offers });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Get offers error');
        throw new errorHandler_1.ApiError(500, 'Failed to get offers');
    }
});
// Get driver statistics
router.get('/stats/:driverId', async (req, res) => {
    try {
        const { driverId } = req.params;
        const driver = await prisma_1.prisma.user.findUnique({
            where: { id: driverId },
            select: {
                id: true,
                name: true,
                averageRating: true,
                totalRides: true,
                totalRatings: true,
                isAvailable: true,
            },
        });
        if (!driver) {
            throw new errorHandler_1.ApiError(404, 'Driver not found');
        }
        // Get recent completed rides
        const recentRides = await prisma_1.prisma.ride.findMany({
            where: {
                driverId,
                status: 'COMPLETED',
            },
            select: {
                id: true,
                finalFare: true,
                completedAt: true,
                driverRating: true,
            },
            orderBy: { completedAt: 'desc' },
            take: 10,
        });
        const totalEarnings = recentRides.reduce((sum, ride) => sum + (ride.finalFare || 0), 0);
        res.json({
            data: {
                ...driver,
                recentRides,
                totalEarnings,
            },
        });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Get stats error');
        throw new errorHandler_1.ApiError(500, 'Failed to get driver statistics');
    }
});
exports.default = router;
//# sourceMappingURL=drivers.js.map