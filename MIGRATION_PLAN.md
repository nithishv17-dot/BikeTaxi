# BikeTaxi Production Migration Plan

## Executive Summary

This document provides a comprehensive, reversible migration strategy for transforming BikeTaxi from Flutter Web + Node.js/Express/JavaScript/MongoDB to React + Node.js/Express/TypeScript/PostgreSQL while maintaining 100% backward compatibility and zero downtime.

**Status**: Phase 2 - Backup & Planning (No Code Changes)  
**Created**: 2026-06-30  
**Last Updated**: 2026-06-30

---

## PHASE 1: Project Analysis ✅ COMPLETE

### Current Architecture Mapped
- **Frontend**: Flutter Web (Dart) - Vercel deployed
- **Backend**: Node.js + Express + Socket.io - Render deployed
- **Database**: MongoDB with Mongoose ORM
- **Auth**: JWT tokens in headers
- **Real-time**: Socket.io for negotiations and tracking

### Key Dependencies Identified
**Backend (Node.js)**:
- express@5.2.1, socket.io@4.8.3, mongoose@8.23.0
- bcryptjs, jsonwebtoken, cors

**Frontend (Flutter)**:
- flutter_map, socket_io_client, http

### Critical Business Logic
1. **Negotiation System**: Driver offers, user acceptance, auto-expiration (10s sweep)
2. **Ride Lifecycle**: requested → negotiating → accepted → ongoing → completed
3. **Real-time Sync**: Socket.io broadcasts for driver availability and ride updates
4. **Payment Processing**: Fare negotiation with multiple payment methods

### Identified Risks
- Socket.io event naming is tightly coupled to client
- JWT secret hardcoded (security issue to fix)
- No input validation (need schema validation)
- MongoDB collections must be preserved during transition

---

## PHASE 2: Backup & Migration Strategy (CURRENT)

### 2.1 Git Backup Strategy

#### Backup Branch Created ✅
```bash
git checkout -b backup/prototype
git tag v1-before-migration
git push origin backup/prototype
git push origin v1-before-migration
```

**Backup Locations**:
- `backup/prototype` branch - Full working prototype snapshot
- `v1-before-migration` tag - Immutable reference point

#### Recovery Command
```bash
# If migration breaks: reset to backup
git checkout backup/prototype
git reset --hard v1-before-migration
git push origin backup/prototype --force
```

---

### 2.2 Parallel Project Structure

**NEVER** replace existing code. Instead:

```
BikeTaxi/
├── backend/
│   ├── server.js (KEEP - Original Node.js/Express)
│   ├── package.json
│   ├── routes/
│   ├── controllers/
│   ├── models/ (MongoDB)
│   ├── middleware/
│   │
│   └── [NEW] typescript/
│       ├── server.ts (New TypeScript Express)
│       ├── package.json (New deps)
│       ├── src/
│       │   ├── controllers/
│       │   ├── services/
│       │   ├── repositories/
│       │   ├── middleware/
│       │   ├── dto/
│       │   ├── interfaces/
│       │   └── utils/
│       ├── prisma/
│       │   └── schema.prisma
│       └── tsconfig.json
│
├── frontend/
│   ├── bike_taxi_app/ (KEEP - Original Flutter)
│   │   ├── lib/
│   │   ├── pubspec.yaml
│   │   └── web/
│   │
│   └── [NEW] react_app/
│       ├── src/
│       │   ├── features/
│       │   ├── components/
│       │   ├── hooks/
│       │   ├── services/
│       │   ├── types/
│       │   ├── styles/
│       │   └── App.tsx
│       ├── package.json
│       ├── tsconfig.json
│       ├── tailwind.config.js
│       └── vite.config.ts
│
├── database/
│   ├── mongodb/
│   │   └── backups/ (Snapshots before migration)
│   │
│   └── [NEW] postgres/
│       ├── schema.sql (PostgreSQL DDL)
│       ├── migrations/ (Prisma migrations)
│       ├── seeds/ (Test data)
│       └── migration-scripts/
│           ├── mongodb-to-postgres.js
│           ├── index-creation.sql
│           └── rollback.sql
│
├── docs/
│   ├── API.md
│   ├── MIGRATION_PLAN.md (This file)
│   ├── ROLLBACK_PROCEDURES.md
│   ├── SCHEMA_MAPPING.md
│   └── TESTING_CHECKLIST.md
│
├── scripts/
│   ├── backup-mongodb.sh
│   ├── backup-project.sh
│   ├── migrate-data.sh
│   └── rollback.sh
│
└── .gitignore (Updated to exclude build artifacts)
```

---

### 2.3 Database Migration Strategy

#### MongoDB Backup
Before any PostgreSQL work:
```bash
# Create timestamped backup
mongodump --out ./database/mongodb/backup/backup-$(date +%Y%m%d-%H%M%S)/

# Archive critical collections
mongoexport --collection users --out ./database/mongodb/backups/users.json
mongoexport --collection rides --out ./database/mongodb/backups/rides.json
```

**Backup Retention**: 30 days minimum  
**Storage**: `/database/mongodb/backups/`  

---

### 2.4 Dependency Migration Path

#### Backend Dependencies (Phase 4)

**Current (JavaScript)**:
```json
{
  "express": "5.2.1",
  "mongoose": "8.23.0",
  "socket.io": "4.8.3",
  "bcryptjs": "2.4.3",
  "jsonwebtoken": "9.0.2"
}
```

**Target (TypeScript)**:
```json
{
  "express": "5.2.1",
  "prisma": "^5.x",
  "@prisma/client": "^5.x",
  "socket.io": "4.8.3",
  "bcryptjs": "2.4.3",
  "jsonwebtoken": "9.0.2",
  "typescript": "^5.x",
  "ts-node": "^10.x",
  "@types/express": "^4.x",
  "@types/node": "^20.x",
  "helmet": "^7.x",
  "express-rate-limit": "^7.x",
  "zod": "^3.x",
  "axios": "^1.x"
}
```

**Installation Order**:
1. Create `backend/typescript/package.json` (separate from root)
2. Install type definitions first
3. Install Prisma toolchain
4. NO changes to root `backend/package.json` during migration

---

### 2.5 Frontend Dependencies (Phase 5)

**Target Stack**:
```json
{
  "react": "^18.x",
  "react-dom": "^18.x",
  "typescript": "^5.x",
  "tailwindcss": "^3.x",
  "react-query": "^3.x",
  "@tanstack/react-query": "^4.x",
  "react-hook-form": "^7.x",
  "zod": "^3.x",
  "axios": "^1.x",
  "socket.io-client": "^4.x",
  "react-router-dom": "^6.x",
  "@radix-ui/react-*": "latest",
  "class-variance-authority": "^0.x",
  "clsx": "^2.x"
}
```

**Installation**: Completely separate `frontend/react_app/` directory

---

## PHASE 3: PostgreSQL Schema Design

### 3.1 Schema Mapping (MongoDB → PostgreSQL)

#### Users Table
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('user', 'driver') NOT NULL,
  is_available BOOLEAN DEFAULT false,
  
  -- Location (normalized from MongoDB subdoc)
  location_lat DECIMAL(10, 8),
  location_lng DECIMAL(11, 8),
  location_updated_at TIMESTAMP,
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Index for availability queries
  CONSTRAINT users_phone_unique UNIQUE (phone)
);

CREATE INDEX idx_users_role_available ON users(role, is_available);
CREATE INDEX idx_users_location ON users(location_lat, location_lng);
```

#### Rides Table
```sql
CREATE TABLE rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  driver_id UUID REFERENCES users(id),
  
  -- Pickup location (normalized)
  pickup_address VARCHAR(500),
  pickup_lat DECIMAL(10, 8),
  pickup_lng DECIMAL(11, 8),
  pickup_place_id VARCHAR(255),
  
  -- Drop location (normalized)
  drop_address VARCHAR(500),
  drop_lat DECIMAL(10, 8),
  drop_lng DECIMAL(11, 8),
  drop_place_id VARCHAR(255),
  
  -- Fare management
  estimated_fare DECIMAL(10, 2),
  offered_fare DECIMAL(10, 2),
  initial_fare DECIMAL(10, 2),
  final_fare DECIMAL(10, 2),
  
  -- Status
  status VARCHAR(50) NOT NULL DEFAULT 'requested',
  -- Values: requested, negotiating, accepted, ongoing, completed, cancelled
  
  -- Negotiation
  negotiation_status VARCHAR(50),
  negotiation_expires_at TIMESTAMP,
  
  -- Payment
  payment_method VARCHAR(50), -- cash, upi, card
  payment_status VARCHAR(50), -- pending, completed, failed
  
  -- Tracking
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT rides_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT rides_driver_id_fk FOREIGN KEY (driver_id) REFERENCES users(id)
);

CREATE INDEX idx_rides_user ON rides(user_id);
CREATE INDEX idx_rides_driver ON rides(driver_id);
CREATE INDEX idx_rides_status ON rides(status);
CREATE INDEX idx_rides_created ON rides(created_at DESC);
```

#### Offers Table (Many-to-many rides to drivers)
```sql
CREATE TABLE offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES users(id),
  
  offered_fare DECIMAL(10, 2) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  -- Values: pending, selected, rejected, accepted_base
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT offers_ride_driver UNIQUE (ride_id, driver_id)
);

CREATE INDEX idx_offers_ride ON offers(ride_id);
CREATE INDEX idx_offers_driver ON offers(driver_id);
CREATE INDEX idx_offers_status ON offers(status);
```

---

### 3.2 Prisma Schema

```prisma
// backend/typescript/prisma/schema.prisma

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}

model User {
  id        String   @id @default(cuid())
  phone     String   @unique
  name      String
  passwordHash String
  role      String   // "user" or "driver"
  isAvailable Boolean @default(false)
  
  locationLat Float?
  locationLng Float?
  locationUpdatedAt DateTime?
  
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  
  // Relations
  ridesAsUser   Ride[] @relation("userRides")
  ridesAsDriver Ride[] @relation("driverRides")
  offers        Offer[]
  
  @@index([role, isAvailable])
  @@index([locationLat, locationLng])
}

model Ride {
  id String @id @default(cuid())
  
  userId String
  user   User   @relation("userRides", fields: [userId], references: [id])
  
  driverId String?
  driver   User?  @relation("driverRides", fields: [driverId], references: [id])
  
  // Locations
  pickupAddress String?
  pickupLat     Float?
  pickupLng     Float?
  pickupPlaceId String?
  
  dropAddress String?
  dropLat     Float?
  dropLng     Float?
  dropPlaceId String?
  
  // Fares
  estimatedFare  Float?
  offeredFare    Float?
  initialFare    Float?
  finalFare      Float?
  
  // Status
  status String @default("requested")
  
  // Negotiation
  negotiationStatus   String?
  negotiationExpiresAt DateTime?
  
  // Payment
  paymentMethod String? // cash, upi, card
  paymentStatus String?
  
  // Timestamps
  startedAt    DateTime?
  completedAt  DateTime?
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
  
  // Relations
  offers Offer[]
  
  @@index([userId])
  @@index([driverId])
  @@index([status])
  @@index([createdAt])
}

model Offer {
  id String @id @default(cuid())
  
  rideId   String
  ride     Ride   @relation(fields: [rideId], references: [id], onDelete: Cascade)
  
  driverId String
  driver   User   @relation(fields: [driverId], references: [id])
  
  offeredFare Float
  status      String @default("pending") // pending, selected, rejected, accepted_base
  
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  
  @@unique([rideId, driverId])
  @@index([rideId])
  @@index([driverId])
  @@index([status])
}
```

---

### 3.3 Data Migration Scripts

**Path**: `/database/postgres/migration-scripts/mongodb-to-postgres.js`

```javascript
// Pseudo-code - will be generated in Phase 3
// Purpose: Transform MongoDB documents to PostgreSQL inserts

// 1. Users: Map MongoDB users to PostgreSQL
// 2. Rides: Normalize nested objects to separate columns
// 3. Offers: Flatten offers array into separate table
// 4. Validate data integrity
// 5. Create rollback SQL
```

---

## PHASE 4: TypeScript Backend Conversion

### 4.1 Services Created in Parallel
- User Service (AuthService + UserService)
- Ride Service
- Offer Service
- Notification Service (Socket.io)
- Payment Service

### 4.2 Repository Pattern
Each service has corresponding repository layer for database abstraction.

---

## PHASE 5: React Frontend Creation

### 5.1 Feature-based Structure
```
frontend/react_app/src/
├── features/
│   ├── auth/
│   ├── booking/
│   ├── tracking/
│   ├── negotiation/
│   ├── dashboard/
│   └── payment/
├── components/
│   ├── common/
│   ├── ui/
│   └── layout/
├── hooks/
├── services/
├── types/
├── styles/
└── App.tsx
```

---

## PHASE 6: Socket.io Migration

### 6.1 Compatibility Layer
New backend maintains same event names:
- `ride:request` → `ride:request`
- `ride:offer` → `ride:offer`
- `driver:status` → `driver:status`

Both clients (Flutter, React) connect to same namespace.

---

## PHASE 7: Comprehensive Testing

### 7.1 Test Strategy
- Unit tests (Services, Repositories)
- Integration tests (API endpoints)
- API contract tests (Ensure backward compatibility)
- Socket.io tests
- Data migration validation tests

---

## PHASE 8: Cutover & Legacy Code Removal

### 8.1 Decision Points
- Only after ALL tests pass
- Manual approval required
- Preserve backup indefinitely
- Archive Flutter/JavaScript code to /archive/ rather than delete

---

## Rollback Procedures

### Emergency Rollback

#### Option 1: Immediate Revert (< 1 hour)
```bash
git checkout backup/prototype
git reset --hard v1-before-migration
git push origin main --force
# Re-deploy old frontend to Vercel
# Re-deploy old backend to Render
```

#### Option 2: Data Rollback
```bash
# If PostgreSQL data is corrupt:
mongorestore ./database/mongodb/backups/backup-TIMESTAMP/
# Both backends can coexist, revert frontend routing
```

---

## Environment Variables Strategy

### Current (Keep Working)
```
MONGODB_URI=mongodb://...
JWT_SECRET=... (to be rotated)
```

### New Services (Separate)
```
DATABASE_URL=postgresql://...
JWT_SECRET_NEW=...
POSTGRES_PASSWORD=...
```

**No mixing** during migration. Each stack has own credentials.

---

## Testing Checklist (Phase 7)

### Before Production Cutover
- [ ] All TypeScript files compile without errors
- [ ] All MongoDB backup tests pass
- [ ] All PostgreSQL data migration tests pass
- [ ] API contract tests pass (old ↔ new endpoints)
- [ ] Socket.io events work identically
- [ ] Load tests on PostgreSQL vs MongoDB
- [ ] React frontend feature parity with Flutter
- [ ] Emergency rollback tested end-to-end
- [ ] Data consistency verified

---

## Timeline & Dependencies

| Phase | Task | Duration | Blocker |
|-------|------|----------|---------|
| 1 | Project Analysis | DONE | - |
| 2 | Backup & Planning | DONE | - |
| 3 | PostgreSQL Schema | TBD | Phase 2 ✅ |
| 4 | TypeScript Backend | TBD | Phase 3 ✅ |
| 5 | React Frontend | TBD | Phase 4 ✅ |
| 6 | Socket.io Compat | TBD | Phase 5 ✅ |
| 7 | Testing | TBD | Phase 6 ✅ |
| 8 | Cutover | TBD | Phase 7 ✅ |

---

## Risk Matrix

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Socket.io events incompatible | HIGH | Compatibility layer + extensive testing |
| Data loss during migration | HIGH | Multiple backups + dry-run tests |
| Performance regression | MEDIUM | Load testing PostgreSQL before cutover |
| Authentication issues | MEDIUM | Dual token support during transition |
| Deployment failure | LOW | Automated rollback procedure |

---

## Success Criteria

✅ **Phase 2 Complete When**:
- Backup branch created and verified
- Tag `v1-before-migration` published
- Migration plan documented (this file)
- Rollback procedures tested
- No code changes to existing project
- Existing application still fully functional

**Ready to Proceed to Phase 3**: YES ✅

---

## Next Steps

1. Confirm this plan
2. Proceed to Phase 3: PostgreSQL Schema Design
3. Generate migration scripts (non-destructive)
4. Set up data backup automation

**Awaiting confirmation before Phase 3 begins.**
