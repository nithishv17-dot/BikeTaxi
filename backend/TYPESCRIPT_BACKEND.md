# Phase 4: TypeScript Backend Implementation

## Overview

This directory contains the TypeScript/Express backend for BikeTaxi, built with Prisma ORM and PostgreSQL. This runs parallel to the existing JavaScript backend.

## Architecture

```
src/
├── app.ts                 # Express app factory
├── server.ts             # Server entry point
├── types/                # TypeScript type definitions
├── schemas/              # Zod validation schemas
├── routes/               # API route handlers
│   ├── users.ts         # User auth and profile endpoints
│   ├── rides.ts         # Ride management endpoints
│   └── drivers.ts       # Driver and negotiation endpoints
├── middleware/          # Express middleware
│   ├── authMiddleware.ts   # JWT authentication
│   └── errorHandler.ts     # Centralized error handling
└── utils/               # Shared utilities
    ├── logger.ts        # Pino logger setup
    ├── prisma.ts        # Prisma client singleton
    └── ...
```

## Technologies

- **Language**: TypeScript 6.0
- **Runtime**: Node.js 18+
- **Framework**: Express 5.2
- **Database**: PostgreSQL via Prisma ORM
- **Validation**: Zod schemas
- **Logging**: Pino with pretty-printing
- **Authentication**: JWT tokens
- **Password**: bcryptjs hashing

## Setup Instructions

### 1. Install Dependencies

```bash
cd backend
npm install
npm install --legacy-peer-deps express-async-errors
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Update `.env` with your PostgreSQL connection string:

```env
DATABASE_URL="postgresql://user:password@localhost:5432/biketaxi_pg"
JWT_SECRET="$(openssl rand -base64 32)"
```

### 3. Run Database Migrations

```bash
npm run prisma:generate
npm run prisma:migrate
```

### 4. Start Development Server

```bash
npm run dev
```

Server runs on `http://localhost:5000`

## API Endpoints

### User Management

**POST /api/users/register**
```json
{
  "name": "John Doe",
  "phone": "9876543210",
  "password": "password123",
  "role": "USER"
}
```

**POST /api/users/login**
```json
{
  "phone": "9876543210",
  "password": "password123"
}
```

**GET /api/users/me** (Authenticated)
- Returns current user profile

**PATCH /api/users/me** (Authenticated)
```json
{
  "name": "Updated Name",
  "email": "user@example.com",
  "profileImage": "https://..."
}
```

**POST /api/users/location** (Authenticated)
```json
{
  "latitude": 40.7128,
  "longitude": -74.0060
}
```

### Ride Management

**POST /api/rides/request** (Authenticated)
```json
{
  "pickupLocation": {
    "latitude": 40.7128,
    "longitude": -74.0060,
    "address": "123 Main St, New York, NY"
  },
  "dropoffLocation": {
    "latitude": 40.7580,
    "longitude": -73.9855,
    "address": "Times Square, New York, NY"
  },
  "paymentMethod": "CASH"
}
```

**GET /api/rides/active/current** (Authenticated)
- Returns current active ride or null

**POST /api/rides/:id/accept** (Authenticated - Driver)
- Accept a ride as driver

**POST /api/rides/:id/start** (Authenticated - Driver)
```json
{
  "otpVerified": true
}
```

**POST /api/rides/:id/complete** (Authenticated - Driver)
```json
{
  "finalFare": 250,
  "paymentStatus": "COMPLETED"
}
```

**POST /api/rides/:id/rate** (Authenticated)
```json
{
  "rating": 5,
  "comment": "Great ride!"
}
```

**GET /api/rides/user/:userId/history** (Authenticated)
- Query params: `page=1&limit=10`
- Returns ride history with pagination

**GET /api/rides/dashboard** (Authenticated)
- Returns dashboard statistics

### Driver Management

**POST /api/drivers/list**
```json
{
  "latitude": 40.7128,
  "longitude": -74.0060,
  "radiusKm": 5
}
```

**POST /api/drivers/toggle/:id** (Authenticated)
- Toggle driver availability

**POST /api/drivers/:rideId/offer** (Authenticated - Driver)
```json
{
  "offeredFare": 250
}
```

**POST /api/drivers/offers/:offerId/accept** (Authenticated - Rider)
- Accept a driver's offer

**GET /api/drivers/:rideId/offers** (Authenticated - Rider)
- Get all offers for a ride

**GET /api/drivers/stats/:driverId**
- Get driver statistics and earnings

## Authentication

All protected endpoints require a JWT token in the Authorization header:

```
Authorization: Bearer <token>
```

Tokens expire after 24 hours.

## Error Handling

Errors are returned in standard format:

```json
{
  "error": "Error message",
  "details": [/* validation errors if applicable */]
}
```

HTTP Status Codes:
- `200` - Success
- `201` - Created
- `400` - Bad Request (validation error)
- `401` - Unauthorized (no token or invalid token)
- `403` - Forbidden (insufficient permissions)
- `404` - Not Found
- `409` - Conflict (resource already exists)
- `500` - Internal Server Error

## Logging

Logs are written to stdout with Pino. In development, logs are pretty-printed. In production, logs are JSON.

Set log level with `LOG_LEVEL` environment variable:
- `debug` - Development
- `info` - Production

## Database

### Schema

The PostgreSQL schema is defined in `/prisma/schema.prisma`. Key tables:

- **users** - Rider and driver accounts
- **rides** - Ride records with negotiation tracking
- **offers** - Driver bids during negotiation
- **ratings** - Historical rating records

### Migrations

Create new migration:
```bash
npm run prisma:migrate
```

View database:
```bash
npm run prisma:studio
```

## Development

### Type Checking

```bash
npx tsc --noEmit
```

### Build

```bash
npm run build:ts
```

Output goes to `dist/` directory.

### Production Start

```bash
npm run start:ts
```

## Performance Considerations

1. **Database Indexes**: All hot-path queries are indexed (phone lookup, active rides, etc.)
2. **Connection Pooling**: Prisma handles connection pooling automatically
3. **Query Optimization**: Use Prisma's `select` and `include` carefully
4. **Caching**: Consider adding Redis for rate limiting and session caching

## Dual-Stack Architecture (Phase 6)

During migration, both backends run simultaneously:

1. **Original Backend** (`/backend/server.js`) - MongoDB
2. **TypeScript Backend** (`/backend/src/server.ts`) - PostgreSQL

They serve different API endpoints or can be load-balanced.

## Troubleshooting

### Connection Issues

```bash
# Test PostgreSQL connection
psql postgresql://user:password@localhost:5432/biketaxi_pg

# Check Prisma configuration
npm run prisma:studio
```

### Type Errors

```bash
# Regenerate Prisma types
npm run prisma:generate

# Type check entire project
npx tsc --noEmit
```

### Build Errors

```bash
# Clear generated files
rm -rf dist/
rm -rf node_modules/.prisma

# Rebuild
npm run build:ts
```

## Next Steps

1. **Phase 5**: Migrate React frontend
2. **Phase 6**: Implement dual-write pattern
3. **Phase 7**: Complete testing and QA
4. **Phase 8**: Production cutover

## Resources

- [Prisma Documentation](https://www.prisma.io/docs/)
- [Express.js Guide](https://expressjs.com/)
- [Zod Validation](https://zod.dev/)
- [Pino Logger](https://getpino.io/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
