import { z } from 'zod';
export declare const LoginSchema: z.ZodObject<{
    phone: z.ZodString;
    password: z.ZodString;
}, z.core.$strip>;
export declare const RegisterSchema: z.ZodObject<{
    phone: z.ZodString;
    password: z.ZodString;
    name: z.ZodString;
    role: z.ZodDefault<z.ZodEnum<{
        USER: "USER";
        DRIVER: "DRIVER";
    }>>;
}, z.core.$strip>;
export declare const LocationSchema: z.ZodObject<{
    latitude: z.ZodNumber;
    longitude: z.ZodNumber;
    address: z.ZodString;
    placeId: z.ZodOptional<z.ZodString>;
}, z.core.$strip>;
export declare const RideRequestSchema: z.ZodObject<{
    pickupLocation: z.ZodObject<{
        latitude: z.ZodNumber;
        longitude: z.ZodNumber;
        address: z.ZodString;
        placeId: z.ZodOptional<z.ZodString>;
    }, z.core.$strip>;
    dropoffLocation: z.ZodObject<{
        latitude: z.ZodNumber;
        longitude: z.ZodNumber;
        address: z.ZodString;
        placeId: z.ZodOptional<z.ZodString>;
    }, z.core.$strip>;
    paymentMethod: z.ZodDefault<z.ZodEnum<{
        CASH: "CASH";
        UPI: "UPI";
        CARD: "CARD";
    }>>;
    initialFare: z.ZodOptional<z.ZodNumber>;
}, z.core.$strip>;
export declare const OfferSchema: z.ZodObject<{
    offeredFare: z.ZodNumber;
}, z.core.$strip>;
export declare const AcceptOfferSchema: z.ZodObject<{
    offerId: z.ZodString;
}, z.core.$strip>;
export declare const UpdateRideSchema: z.ZodObject<{
    status: z.ZodOptional<z.ZodString>;
    finalFare: z.ZodOptional<z.ZodNumber>;
    paymentStatus: z.ZodOptional<z.ZodString>;
    otpVerified: z.ZodOptional<z.ZodBoolean>;
}, z.core.$strip>;
export declare const RatingSchema: z.ZodObject<{
    rating: z.ZodNumber;
    comment: z.ZodOptional<z.ZodString>;
}, z.core.$strip>;
export type LoginInput = z.infer<typeof LoginSchema>;
export type RegisterInput = z.infer<typeof RegisterSchema>;
export type RideRequestInput = z.infer<typeof RideRequestSchema>;
export type OfferInput = z.infer<typeof OfferSchema>;
export type RatingInput = z.infer<typeof RatingSchema>;
//# sourceMappingURL=index.d.ts.map