"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const prisma_1 = require("../utils/prisma");
const authMiddleware_1 = require("../middleware/authMiddleware");
const errorHandler_1 = require("../middleware/errorHandler");
const schemas_1 = require("../schemas");
const logger_1 = require("../utils/logger");
const router = (0, express_1.Router)();
const logger = (0, logger_1.createLogger)('users');
router.post('/register', async (req, res) => {
    try {
        const input = schemas_1.RegisterSchema.parse(req.body);
        // Check if user already exists
        const existing = await prisma_1.prisma.user.findUnique({
            where: { phone: input.phone },
        });
        if (existing) {
            throw new errorHandler_1.ApiError(409, 'User with this phone already exists');
        }
        // Hash password
        const hashedPassword = await bcryptjs_1.default.hash(input.password, 10);
        // Create user
        const user = await prisma_1.prisma.user.create({
            data: {
                name: input.name,
                phone: input.phone,
                password: hashedPassword,
                role: input.role,
                isVerified: true,
            },
        });
        const token = (0, authMiddleware_1.generateToken)(user.id, user.role);
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
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Registration error');
        throw new errorHandler_1.ApiError(500, 'Registration failed');
    }
});
router.post('/login', async (req, res) => {
    try {
        const input = schemas_1.LoginSchema.parse(req.body);
        const user = await prisma_1.prisma.user.findUnique({
            where: { phone: input.phone },
        });
        if (!user) {
            throw new errorHandler_1.ApiError(401, 'Invalid phone or password');
        }
        const passwordMatch = await bcryptjs_1.default.compare(input.password, user.password);
        if (!passwordMatch) {
            throw new errorHandler_1.ApiError(401, 'Invalid phone or password');
        }
        const token = (0, authMiddleware_1.generateToken)(user.id, user.role);
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
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Login error');
        throw new errorHandler_1.ApiError(500, 'Login failed');
    }
});
router.get('/me', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const user = await prisma_1.prisma.user.findUnique({
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
            throw new errorHandler_1.ApiError(404, 'User not found');
        }
        res.json({ data: user });
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Get user error');
        throw new errorHandler_1.ApiError(500, 'Failed to get user');
    }
});
router.patch('/me', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { name, email, profileImage } = req.body;
        const user = await prisma_1.prisma.user.update({
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
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Update user error');
        throw new errorHandler_1.ApiError(500, 'Failed to update user');
    }
});
router.post('/location', authMiddleware_1.authMiddleware, async (req, res) => {
    try {
        const { latitude, longitude } = req.body;
        if (typeof latitude !== 'number' || typeof longitude !== 'number') {
            throw new errorHandler_1.ApiError(400, 'Invalid location data');
        }
        const user = await prisma_1.prisma.user.update({
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
    }
    catch (error) {
        if (error instanceof errorHandler_1.ApiError)
            throw error;
        logger.error({ error }, 'Update location error');
        throw new errorHandler_1.ApiError(500, 'Failed to update location');
    }
});
exports.default = router;
//# sourceMappingURL=users.js.map