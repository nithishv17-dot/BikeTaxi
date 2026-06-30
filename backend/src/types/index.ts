import { Request } from 'express';
import { User } from '@prisma/client';

export interface AuthRequest extends Request {
  user?: User;
  userId?: string;
}

export interface ApiResponse<T> {
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginationQuery {
  page?: number;
  limit?: number;
}

export interface LocationData {
  latitude: number;
  longitude: number;
  address: string;
  placeId?: string;
}

export interface RideRequest {
  pickupLocation: LocationData;
  dropoffLocation: LocationData;
  paymentMethod?: string;
  initialFare?: number;
}

export interface OfferData {
  offeredFare: number;
  driverId: string;
}

export interface RideUpdate {
  status?: string;
  finalFare?: number;
  paymentStatus?: string;
  otpVerified?: boolean;
}
