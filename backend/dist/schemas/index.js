"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RatingSchema = exports.UpdateRideSchema = exports.AcceptOfferSchema = exports.OfferSchema = exports.RideRequestSchema = exports.LocationSchema = exports.RegisterSchema = exports.LoginSchema = void 0;
const zod_1 = require("zod");
exports.LoginSchema = zod_1.z.object({
    phone: zod_1.z.string().min(10, 'Invalid phone number'),
    password: zod_1.z.string().min(6, 'Password must be at least 6 characters'),
});
exports.RegisterSchema = exports.LoginSchema.extend({
    name: zod_1.z.string().min(2, 'Name must be at least 2 characters'),
    role: zod_1.z.enum(['USER', 'DRIVER']).default('USER'),
});
exports.LocationSchema = zod_1.z.object({
    latitude: zod_1.z.number().min(-90).max(90),
    longitude: zod_1.z.number().min(-180).max(180),
    address: zod_1.z.string().min(1),
    placeId: zod_1.z.string().optional(),
});
exports.RideRequestSchema = zod_1.z.object({
    pickupLocation: exports.LocationSchema,
    dropoffLocation: exports.LocationSchema,
    paymentMethod: zod_1.z.enum(['CASH', 'UPI', 'CARD']).default('CASH'),
    initialFare: zod_1.z.number().positive().optional(),
});
exports.OfferSchema = zod_1.z.object({
    offeredFare: zod_1.z.number().positive('Fare must be positive'),
});
exports.AcceptOfferSchema = zod_1.z.object({
    offerId: zod_1.z.string().uuid(),
});
exports.UpdateRideSchema = zod_1.z.object({
    status: zod_1.z.string().optional(),
    finalFare: zod_1.z.number().positive().optional(),
    paymentStatus: zod_1.z.string().optional(),
    otpVerified: zod_1.z.boolean().optional(),
});
exports.RatingSchema = zod_1.z.object({
    rating: zod_1.z.number().min(1).max(5),
    comment: zod_1.z.string().optional(),
});
//# sourceMappingURL=index.js.map