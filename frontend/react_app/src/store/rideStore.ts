import { create } from 'zustand';
import api from '../lib/api';

export interface LocationData {
  address: string;
  latitude: number;
  longitude: number;
  placeId?: string;
}

export interface Ride {
  id: string;
  riderId: string;
  driverId?: string;
  pickup: LocationData;
  drop: LocationData;
  status: 'REQUESTED' | 'NEGOTIATING' | 'ACCEPTED' | 'STARTED' | 'COMPLETED' | 'CANCELLED';
  estimatedFare: number;
  finalFare?: number;
  paymentMethod: 'CASH' | 'UPI' | 'CARD';
  createdAt: string;
  acceptedAt?: string;
  completedAt?: string;
}

export interface Offer {
  id: string;
  rideId: string;
  driverId: string;
  offeredFare: number;
  offerStatus: 'PENDING' | 'SELECTED' | 'ACCEPTED' | 'REJECTED' | 'EXPIRED';
  createdAt: string;
  expiresAt: string;
}

interface RideStore {
  activeRide: Ride | null;
  offers: Offer[];
  rideHistory: Ride[];
  loading: boolean;
  error: string | null;
  requestRide: (pickup: LocationData, drop: LocationData, paymentMethod: string) => Promise<Ride>;
  getActiveRide: () => Promise<void>;
  getRideHistory: () => Promise<void>;
  acceptRide: (rideId: string, driverId: string) => Promise<void>;
  startRide: (rideId: string) => Promise<void>;
  completeRide: (rideId: string) => Promise<void>;
  submitOffer: (rideId: string, offeredFare: number) => Promise<void>;
  acceptOffer: (offerId: string) => Promise<void>;
  setActiveRide: (ride: Ride | null) => void;
}

export const useRideStore = create<RideStore>((set, get) => ({
  activeRide: null,
  offers: [],
  rideHistory: [],
  loading: false,
  error: null,

  requestRide: async (pickup: LocationData, drop: LocationData, paymentMethod: string) => {
    try {
      set({ loading: true, error: null });
      const response = await api.post('/rides/request', {
        pickupAddress: pickup.address,
        pickupLatitude: pickup.latitude,
        pickupLongitude: pickup.longitude,
        pickupPlaceId: pickup.placeId,
        dropAddress: drop.address,
        dropLatitude: drop.latitude,
        dropLongitude: drop.longitude,
        dropPlaceId: drop.placeId,
        paymentMethod,
      });
      const ride = response.data.data;
      set({ activeRide: ride, loading: false });
      return ride;
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to request ride';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  getActiveRide: async () => {
    try {
      set({ loading: true, error: null });
      const response = await api.get('/rides/active/current');
      set({ activeRide: response.data.data, loading: false });
    } catch (error: any) {
      if (error.response?.status === 404) {
        set({ activeRide: null, loading: false });
      } else {
        const errorMsg = error.response?.data?.message || 'Failed to fetch active ride';
        set({ error: errorMsg, loading: false });
      }
    }
  },

  getRideHistory: async () => {
    try {
      set({ loading: true, error: null });
      const response = await api.get('/rides/history?limit=10&offset=0');
      set({ rideHistory: response.data.data.rides, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to fetch ride history';
      set({ error: errorMsg, loading: false });
    }
  },

  acceptRide: async (rideId: string) => {
    try {
      set({ loading: true, error: null });
      const response = await api.post(`/rides/accept/${rideId}`);
      set({ activeRide: response.data.data, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to accept ride';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  startRide: async (rideId: string) => {
    try {
      set({ loading: true, error: null });
      const response = await api.post(`/rides/start/${rideId}`);
      set({ activeRide: response.data.data, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to start ride';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  completeRide: async (rideId: string) => {
    try {
      set({ loading: true, error: null });
      const response = await api.post(`/rides/complete/${rideId}`);
      set({ activeRide: response.data.data, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to complete ride';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  submitOffer: async (rideId: string, offeredFare: number) => {
    try {
      set({ loading: true, error: null });
      await api.post(`/drivers/${rideId}/offer`, { offeredFare });
      set({ loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to submit offer';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  acceptOffer: async (offerId: string) => {
    try {
      set({ loading: true, error: null });
      const response = await api.post(`/drivers/offers/${offerId}/accept`);
      set({ activeRide: response.data.data, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Failed to accept offer';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  setActiveRide: (ride: Ride | null) => {
    set({ activeRide: ride });
  },
}));
