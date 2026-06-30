# PostgreSQL Setup & Configuration
## Phase 3: Database Architecture

This document covers the complete PostgreSQL setup for BikeTaxi.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Schema Overview](#schema-overview)
3. [Migration Process](#migration-process)
4. [Validation & Testing](#validation--testing)
5. [Performance Optimization](#performance-optimization)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- Node.js 18+
- PostgreSQL 14+ (local or cloud)
- Prisma CLI installed globally: `npm install -g prisma`

### Local Development Setup

#### Option 1: Using Prisma Dev (Recommended)

```bash
cd backend
npx prisma dev
```

This automatically:
- Creates a local PostgreSQL instance
- Generates Prisma client
- Sets up environment variables

#### Option 2: Manual PostgreSQL Setup

```bash
# Linux/macOS
brew install postgresql
brew services start postgresql

# Or use Docker
docker run --name biketaxi-postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:16
```

#### Option 3: Cloud PostgreSQL

**Render** (Recommended):
```
Create free PostgreSQL instance at https://render.com
Copy connection string to DATABASE_URL
```

**Neon**:
```
Sign up at https://neon.tech
Create project
Copy connection string
```

### Environment Configuration

```bash
# .env file
DATABASE_URL="postgresql://user:password@localhost:5432/biketaxi_pg"
NODE_ENV="development"
PORT=5000
JWT_SECRET="your-secret-key"
MONGODB_URI="mongodb://127.0.0.1:27017/biketaxi"  # For dual-write during migration
```

### Generate Prisma Client

```bash
cd backend
npx prisma generate
```

---

## Schema Overview

### Tables

#### Users Table
Stores rider and driver profiles.

**Key Fields:**
- `id`: Unique identifier (UUID)
- `phone`: Unique phone number (indexed)
- `role`: USER or DRIVER
- `isAvailable`: Driver availability flag
- `averageRating`: Computed from ratings
- `createdAt`, `updatedAt`: Timestamps

**Indexes:**
- `(phone)` - UNIQUE, primary lookup
- `(role)` - Filter by user type
- `(isAvailable)` - Find available drivers
- `(createdAt)` - Time-based queries

#### Rides Table
Main transactional record for each ride.

**Key Fields:**
- `id`: Unique identifier
- `riderId`, `driverId`: Foreign keys to users
- `status`: REQUESTED → NEGOTIATING → ACCEPTED → STARTED → COMPLETED
- `pickupLatitude/Longitude`, `dropLatitude/Longitude`: Location coordinates
- `initialFare`, `estimatedFare`, `offeredFare`, `finalFare`: Pricing
- `paymentMethod`, `paymentStatus`: Payment tracking
- `negotiationStatus`: OPEN → LOCKED → EXPIRED

**Indexes:**
- `(riderId)` - Find rides by rider
- `(driverId)` - Find rides by driver
- `(status)` - Filter by ride status
- `(paymentStatus)` - Payment reconciliation
- `(createdAt)`, `(completedAt)` - Time-based queries

#### Offers Table
Driver bids during negotiation phase.

**Key Fields:**
- `rideId`: Foreign key to ride
- `driverId`: Foreign key to driver
- `offeredFare`: Driver's quoted price
- `offerStatus`: PENDING → SELECTED → ACCEPTED / REJECTED / EXPIRED

**Indexes:**
- `(rideId)` - Find offers for a ride
- `(driverId)` - Find driver's offers
- `(offerStatus)` - Filter by status

#### Ratings Table
Historical rating records.

**Key Fields:**
- `rideId`: Associated ride
- `ratedById`, `ratedUserId`: Who rated whom
- `rating`: 1-5 stars
- `comment`: Optional feedback

---

## Migration Process

### Step 1: Backup MongoDB

```bash
# Export all collections
mongoexport --collection users --out ./backups/users.json
mongoexport --collection rides --out ./backups/rides.json
mongoexport --collection offers --out ./backups/offers.json
```

### Step 2: Initialize PostgreSQL Schema

```bash
cd backend

# Generate Prisma client
npx prisma generate

# Create tables
psql -d biketaxi_pg -f ../database/postgres/migrations/001_initial_schema.sql

# Or using Prisma
npx prisma migrate dev --name initial
```

### Step 3: Run Data Migration

```bash
# Install dependencies
npm install

# Migrate data
node ../database/postgres/scripts/migrate_mongodb_to_postgres.js
```

**Output:**
```
2026-06-30T10:30:45.123Z [MIGRATION] [SUCCESS] Connected to MongoDB
2026-06-30T10:30:46.456Z [MIGRATION] [SUCCESS] Connected to PostgreSQL
2026-06-30T10:30:50.789Z [MIGRATION] [INFO] Starting user migration...
2026-06-30T10:30:52.345Z [MIGRATION] [INFO] Found 1234 users in MongoDB
...
2026-06-30T10:31:05.678Z [MIGRATION] [INFO] User migration complete: 1234 succeeded, 0 failed
```

### Step 4: Validate Migration

```bash
# Run validation checks
node ../database/postgres/scripts/validate_migration.js
```

**Expected Output:**
```
2026-06-30T10:31:10.123Z [VALIDATION] [SUCCESS] Connected to PostgreSQL
2026-06-30T10:31:11.456Z [VALIDATION] [INFO] Validating User data integrity...
2026-06-30T10:31:12.789Z [VALIDATION] [SUCCESS] User integrity check complete: 1234 users, 0 issues found
...
2026-06-30T10:31:20.345Z [VALIDATION] [SUCCESS] Validation complete: All checks passed!
```

### Step 5: Verify Data Completeness

```bash
# Connect to PostgreSQL
psql -d biketaxi_pg

# Check record counts
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM rides;
SELECT COUNT(*) FROM offers;
SELECT COUNT(*) FROM ratings;
```

---

## Validation & Testing

### Pre-Migration Checks

```javascript
// test/postgres-validation.test.js

describe("PostgreSQL Migration", () => {
  test("Users migrated correctly", async () => {
    const userCount = await prisma.user.count();
    expect(userCount).toBeGreaterThan(0);
  });

  test("Foreign key constraints work", async () => {
    const ride = await prisma.ride.findFirst({
      include: { rider: true, driver: true }
    });
    expect(ride.rider).toBeDefined();
  });

  test("Unique constraints enforced", async () => {
    await expect(
      prisma.user.create({
        data: {
          name: "Test",
          phone: "+919999999999",
          password: "hash",
          role: "USER"
        }
      })
    ).rejects.toThrow();
  });
});
```

### Common Queries

```sql
-- Find completed rides with driver and rider info
SELECT 
  r.id,
  r.status,
  u.name as rider_name,
  d.name as driver_name,
  r.final_fare
FROM rides r
JOIN users u ON r.rider_id = u.id
LEFT JOIN users d ON r.driver_id = d.id
WHERE r.status = 'COMPLETED'
ORDER BY r.completed_at DESC;

-- Calculate average earnings by driver
SELECT 
  d.id,
  d.name,
  COUNT(r.id) as ride_count,
  AVG(r.final_fare) as avg_fare,
  SUM(r.final_fare) as total_earnings
FROM users d
JOIN rides r ON d.id = r.driver_id
WHERE r.status = 'COMPLETED'
  AND r.completed_at >= NOW() - INTERVAL '30 days'
GROUP BY d.id, d.name
ORDER BY total_earnings DESC;

-- Find pending payments
SELECT 
  r.id,
  r.rider_id,
  r.final_fare,
  r.payment_method,
  r.completed_at
FROM rides r
WHERE r.payment_status = 'PENDING'
  AND r.status = 'COMPLETED'
ORDER BY r.completed_at ASC;
```

### Performance Testing

```javascript
// test/postgres-performance.test.js

describe("PostgreSQL Performance", () => {
  test("Find active rides < 100ms", async () => {
    const start = Date.now();
    await prisma.ride.findMany({
      where: { status: { in: ["REQUESTED", "ACCEPTED"] } },
      include: { rider: true, driver: true }
    });
    const elapsed = Date.now() - start;
    expect(elapsed).toBeLessThan(100);
  });

  test("Find available drivers < 50ms", async () => {
    const start = Date.now();
    await prisma.user.findMany({
      where: { role: "DRIVER", isAvailable: true }
    });
    const elapsed = Date.now() - start;
    expect(elapsed).toBeLessThan(50);
  });
});
```

---

## Performance Optimization

### Indexes Strategy

Already defined in schema:

1. **Hot Path Indexes** (used in every request)
   - `users(phone)` - Login lookups
   - `rides(riderId, status)` - Get user's rides
   - `rides(driverId, status)` - Get driver's rides

2. **Filtering Indexes**
   - `users(role, isAvailable)` - Driver search
   - `rides(status, createdAt)` - Dashboard
   - `offers(rideId, offerStatus)` - Negotiation

3. **Sorting Indexes**
   - `rides(completedAt)` - Recent rides
   - `rides(createdAt)` - Timeline

### Query Optimization Tips

```javascript
// GOOD: Use select to fetch only needed fields
const rides = await prisma.ride.findMany({
  where: { status: 'COMPLETED' },
  select: {
    id: true,
    finalFare: true,
    completedAt: true,
    rider: { select: { name: true } }
  },
  take: 10
});

// BAD: Fetching entire objects wastes bandwidth
const allRides = await prisma.ride.findMany({
  include: { ratings: true }  // Don't need this for list view
});
```

### Connection Pooling

```typescript
// database/postgres.config.ts uses built-in pooling

// For high-concurrency:
const prisma = new PrismaClient({
  datasources: {
    db: {
      url: env.DATABASE_URL + "?pool_size=20&statement_cache_size=250"
    }
  }
});
```

---

## Troubleshooting

### Connection Issues

```bash
# Test PostgreSQL connection
psql -h localhost -U postgres -d biketaxi_pg -c "SELECT 1"

# Check connection string
echo $DATABASE_URL

# View Prisma logs
DEBUG=prisma* npm start
```

### Migration Failures

```bash
# Rollback Prisma migration
npx prisma migrate resolve --rolled-back initial

# Reset database (WARNING: deletes all data)
npx prisma migrate reset

# Manually drop and recreate
psql -d postgres -c "DROP DATABASE biketaxi_pg;"
psql -d postgres -c "CREATE DATABASE biketaxi_pg;"
```

### Data Inconsistencies

```javascript
// Repair user statistics
await prisma.$executeRaw`
  UPDATE users
  SET total_rides = (
    SELECT COUNT(*) FROM rides WHERE rider_id = users.id AND status = 'COMPLETED'
  )
  WHERE role = 'USER'
`;

// Recalculate average ratings
await prisma.$executeRaw`
  UPDATE users
  SET average_rating = (
    SELECT AVG(rating) FROM ratings WHERE rated_user_id = users.id
  )
  WHERE id IN (SELECT DISTINCT rated_user_id FROM ratings)
`;
```

### Performance Problems

```sql
-- Check slow queries
SELECT query, calls, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Analyze table
ANALYZE users;
ANALYZE rides;

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

---

## Disaster Recovery

### Full Database Backup

```bash
# Backup entire database
pg_dump biketaxi_pg > backup-$(date +%Y%m%d-%H%M%S).sql

# Backup with compression
pg_dump biketaxi_pg | gzip > backup-$(date +%Y%m%d-%H%M%S).sql.gz
```

### Restore from Backup

```bash
# Restore full database
psql biketaxi_pg < backup-20260630-120000.sql

# Restore from compressed backup
gunzip < backup-20260630-120000.sql.gz | psql biketaxi_pg
```

---

## Next Steps

- **Phase 4**: TypeScript Backend Implementation
- **Phase 5**: React Frontend Migration
- **Phase 6**: Dual-write for Safety
- **Phase 7**: Testing & QA
- **Phase 8**: Production Cutover

---

**Created**: 2026-06-30  
**Status**: Phase 3 Complete  
**Next**: Await Phase 4 start signal
