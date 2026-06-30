import { z } from 'zod';

export const LoginSchema = z.object({
  phone: z.string().min(10, 'Invalid phone number'),
  password: z.string().min(6, 'Password must be at least 6 characters'),
});

export const RegisterSchema = LoginSchema.extend({
  name: z.string().min(2, 'Name must be at least 2 characters'),
  role: z.enum(['USER', 'DRIVER']).default('USER'),
});

export const LocationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  address: z.string().min(1),
  placeId: z.string().optional(),
});

export const RideRequestSchema = z.object({
  pickupLocation: LocationSchema,
  dropoffLocation: LocationSchema,
  paymentMethod: z.enum(['CASH', 'UPI', 'CARD']).default('CASH'),
  initialFare: z.number().positive().optional(),
});

export const OfferSchema = z.object({
  offeredFare: z.number().positive('Fare must be positive'),
});

export const AcceptOfferSchema = z.object({
  offerId: z.string().uuid(),
});

export const UpdateRideSchema = z.object({
  status: z.string().optional(),
  finalFare: z.number().positive().optional(),
  paymentStatus: z.string().optional(),
  otpVerified: z.boolean().optional(),
});

export const RatingSchema = z.object({
  rating: z.number().min(1).max(5),
  comment: z.string().optional(),
});

export type LoginInput = z.infer<typeof LoginSchema>;
export type RegisterInput = z.infer<typeof RegisterSchema>;
export type RideRequestInput = z.infer<typeof RideRequestSchema>;
export type OfferInput = z.infer<typeof OfferSchema>;
export type RatingInput = z.infer<typeof RatingSchema>;
