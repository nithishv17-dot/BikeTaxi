import { create } from 'zustand';
import api from '../lib/api';

interface User {
  id: string;
  name: string;
  phone: string;
  role: 'USER' | 'DRIVER';
  email?: string;
  profileImage?: string;
  averageRating?: number;
  totalRides?: number;
}

interface AuthStore {
  user: User | null;
  token: string | null;
  loading: boolean;
  error: string | null;
  login: (phone: string, password: string) => Promise<void>;
  register: (name: string, phone: string, password: string, role: 'USER' | 'DRIVER') => Promise<void>;
  logout: () => void;
  setUser: (user: User | null) => void;
}

export const useAuthStore = create<AuthStore>((set) => ({
  user: localStorage.getItem('user') ? JSON.parse(localStorage.getItem('user') as string) : null,
  token: localStorage.getItem('authToken'),
  loading: false,
  error: null,

  login: async (phone: string, password: string) => {
    try {
      set({ loading: true, error: null });
      const response = await api.post('/users/login', { phone, password });
      const { user, token } = response.data.data;
      
      localStorage.setItem('authToken', token);
      localStorage.setItem('user', JSON.stringify(user));
      
      set({ user, token, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Login failed';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  register: async (name: string, phone: string, password: string, role: 'USER' | 'DRIVER') => {
    try {
      set({ loading: true, error: null });
      const response = await api.post('/users/register', { name, phone, password, role });
      const { user, token } = response.data.data;
      
      localStorage.setItem('authToken', token);
      localStorage.setItem('user', JSON.stringify(user));
      
      set({ user, token, loading: false });
    } catch (error: any) {
      const errorMsg = error.response?.data?.message || 'Registration failed';
      set({ error: errorMsg, loading: false });
      throw error;
    }
  },

  logout: () => {
    localStorage.removeItem('authToken');
    localStorage.removeItem('user');
    set({ user: null, token: null, error: null });
  },

  setUser: (user: User | null) => {
    if (user) {
      localStorage.setItem('user', JSON.stringify(user));
    } else {
      localStorage.removeItem('user');
    }
    set({ user });
  },
}));
