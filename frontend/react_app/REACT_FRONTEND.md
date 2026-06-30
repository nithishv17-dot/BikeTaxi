# BikeTaxi React Frontend - Phase 5

## Overview

Modern React 18 + TypeScript frontend for BikeTaxi platform with Tailwind CSS styling and Zustand state management.

## Architecture

### Directory Structure

```
src/
├── pages/               # Page components
│   ├── Login.tsx        # User login
│   ├── Register.tsx     # User registration
│   ├── Home.tsx         # Ride booking dashboard
│   └── RideStatus.tsx   # Active ride tracking
├── store/               # State management with Zustand
│   ├── authStore.ts     # Authentication state
│   └── rideStore.ts     # Ride operations state
├── lib/
│   └── api.ts          # Axios API client with JWT interceptor
├── App.tsx             # Router configuration
├── index.tsx           # React entry point
└── index.css           # Global styles with Tailwind
```

### Key Technologies

- **Framework**: React 18 with TypeScript
- **Styling**: Tailwind CSS v3
- **Routing**: React Router v6
- **State Management**: Zustand
- **HTTP Client**: Axios with JWT interceptor
- **Icons**: Lucide React

## Features

### Authentication
- Phone + password based login
- Registration with role selection (Rider/Driver)
- JWT token storage in localStorage
- Automatic token injection in API requests
- Protected routes

### Ride Booking
- Enter pickup and dropoff locations
- Select payment method (Cash/UPI/Card)
- Real-time ride status tracking
- Auto-refresh every 3 seconds during active ride
- Fare estimation display

### Ride Management
- View active ride details
- Track ride status changes
- Ride history (paginated)
- Accept/reject driver offers
- Rate completed rides

## Setup

### Prerequisites
- Node.js 16+
- npm or yarn
- TypeScript backend running on http://localhost:5000

### Installation

```bash
cd frontend/react_app

# Install dependencies
npm install

# Create environment file
cp .env.example .env

# Update API URL if needed
# REACT_APP_API_URL=http://localhost:5000/api
```

### Development

```bash
# Start dev server (port 3000)
npm start

# The app will auto-reload on file changes
# Open http://localhost:3000 in your browser
```

### Building

```bash
# Create production build
npm run build

# Outputs to ./build directory
```

## Component Overview

### Pages

#### Login (src/pages/Login.tsx)
- Phone and password fields
- Validation and error handling
- Link to registration page
- Redirects to home on success

#### Register (src/pages/Register.tsx)
- Name, phone, password fields
- Role selection (Rider/Driver)
- Form validation
- Link to login page
- Automatic login after registration

#### Home (src/pages/Home.tsx)
- Active ride display or booking form
- Pickup/dropoff address input
- Payment method selection
- User profile in header
- Logout button

#### RideStatus (src/pages/RideStatus.tsx)
- Full ride details with visual journey
- Status indicators with color coding
- Real-time polling (auto-refresh every 3 seconds)
- Manual refresh toggle
- Back navigation

### State Management

#### AuthStore (src/store/authStore.ts)
```typescript
interface AuthStore {
  user: User | null;
  token: string | null;
  loading: boolean;
  error: string | null;
  login(phone: string, password: string): Promise<void>;
  register(name: string, phone: string, password: string, role: UserRole): Promise<void>;
  logout(): void;
  setUser(user: User | null): void;
}
```

Methods:
- `login()` - Authenticate user
- `register()` - Create new account
- `logout()` - Clear auth state
- `setUser()` - Update user profile

#### RideStore (src/store/rideStore.ts)
```typescript
interface RideStore {
  activeRide: Ride | null;
  offers: Offer[];
  rideHistory: Ride[];
  loading: boolean;
  error: string | null;
  requestRide(pickup: LocationData, drop: LocationData, method: string): Promise<Ride>;
  getActiveRide(): Promise<void>;
  getRideHistory(): Promise<void>;
  acceptRide(rideId: string): Promise<void>;
  startRide(rideId: string): Promise<void>;
  completeRide(rideId: string): Promise<void>;
  submitOffer(rideId: string, fare: number): Promise<void>;
  acceptOffer(offerId: string): Promise<void>;
  setActiveRide(ride: Ride | null): void;
}
```

### API Client (src/lib/api.ts)

Axios instance with:
- Automatic JWT token injection
- Error handling
- Base URL configuration via environment variable

```typescript
// API automatically adds Bearer token
const token = localStorage.getItem('authToken');
if (token) {
  config.headers.Authorization = `Bearer ${token}`;
}
```

## Styling

### Theme Colors
- **Primary**: `#00FFCC` (neon cyan) - Main accent
- **Dark**: `#121212` - Primary background
- **DarkAlt**: `#1E1E1E` - Secondary background
- **Danger**: `#FF3366` - Destructive actions

### Typography
- **Display**: Inter font - Headings and important text
- **Body**: Outfit font - Regular content

### Layout
- Mobile-first responsive design
- Flexbox for component layouts
- Tailwind utility classes
- Smooth transitions and hover states

## Environment Variables

```env
# API Configuration
REACT_APP_API_URL=http://localhost:5000/api

# Environment (development/production)
REACT_APP_ENV=development
```

## Deployment

### Vercel (Recommended)

```bash
# Connect git repository
vercel link

# Deploy
vercel deploy

# Deploy to production
vercel deploy --prod
```

### Docker

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY . .
RUN npm install
RUN npm run build
RUN npm install -g serve
EXPOSE 3000
CMD ["serve", "-s", "build"]
```

```bash
docker build -t biketaxi-react .
docker run -p 3000:3000 biketaxi-react
```

### Manual Deployment

1. Build: `npm run build`
2. Upload `build/` directory to your hosting
3. Configure server to serve `build/index.html` for all routes
4. Set environment variables on hosting platform

## Performance Optimizations

- Lazy loading with React.lazy
- Code splitting via React Router
- Zustand for efficient state updates
- Local storage for persistence
- Polled updates (3-second intervals)

## Type Safety

Full TypeScript coverage:
- Interfaces for all API responses
- Type-inferred Zustand stores
- React component prop types
- Event handler types

## Error Handling

- Try-catch blocks in async functions
- User-friendly error messages
- Error boundary for React errors
- Network error handling via Axios

## Browser Support

- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Mobile browsers (iOS Safari, Chrome Mobile)

## Development Workflow

```bash
# Start TypeScript backend
cd backend
npm run dev

# In another terminal, start React frontend
cd frontend/react_app
npm start

# App runs on http://localhost:3000
# Backend on http://localhost:5000
```

## Troubleshooting

### CORS Errors
Ensure backend has CORS enabled for http://localhost:3000

### API Connection Failed
Check that backend is running on port 5000 and REACT_APP_API_URL is correct

### Styles Not Loading
Run `npm run build` and check that CSS is compiled

### State Persists Across Logout
Clear localStorage manually or check logout() is clearing auth state

## Next Steps

- Add map integration for location selection
- Implement WebSocket for real-time ride updates
- Add payment gateway integration
- Implement rating/review system
- Add driver matching algorithm UI
- Profile management page
- Ride history with filters
- Push notifications

---

**Version**: 1.0  
**Last Updated**: 2026-06-30  
**Status**: Phase 5 Complete
