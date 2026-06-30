# BikeTaxi: MongoDB → PostgreSQL Schema Mapping

## Overview

This document details the complete transformation of BikeTaxi's MongoDB schema to PostgreSQL with normalization, referential integrity, and optimization for ride-sharing queries.

---

## MongoDB to PostgreSQL Migration Guide

### Key Changes

1. **Normalization**: Nested objects become separate tables
2. **Type Safety**: String fields → typed columns
3. **Referential Integrity**: Subdocuments → foreign keys
4. **Indexes**: Explicit indexes for performance
5. **Transactions**: Support for multi-statement consistency

---

## 1. Users Collection → users Table

### MongoDB Schema
```javascript
db.users.insertOne({
  _id: ObjectId("..."),
  name: "John Doe",
  phone: "+91...",
  password: "hashed...",
  role: "user" | "driver",
  isAvailable: true,
  location: {
    lat: 28.6139,
    lng: 77.2090
  },
  createdAt: ISODate("..."),
  updatedAt: ISODate("...")
})
```

### PostgreSQL Migration
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'driver')),
  is_available BOOLEAN DEFAULT false,
  
  -- Location (normalized from subdoc)
  location_lat DECIMAL(10, 8),
  location_lng DECIMAL(11, 8),
  location_updated_at TIMESTAMP,
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Constraints
  CONSTRAINT valid_phone CHECK (phone ~ ^\+?[0-9]{10,}$),
  CONSTRAINT valid_name CHECK (LENGTH(name) > 0)
);

-- Indexes for common queries
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_available ON users(is_available);
CREATE INDEX idx_users_role_available ON users(role, is_available);
CREATE INDEX idx_users_location ON users USING GIST (
  ll_to_earth(location_lat, location_lng)
);  -- PostGIS for nearest driver queries
```

### Migration Script Mapping
```javascript
// Transform: db.users → INSERT INTO users
const mongoUser = {
  _id: "507f...",
  name: "John",
  phone: "+919876543210",
  password: "hashed",
  role: "driver",
  isAvailable: true,
  location: { lat: 28.6139, lng: 77.2090 },
  createdAt: new Date(),
  updatedAt: new Date()
};

// Becomes:
INSERT INTO users (
  id, phone, name, password_hash, role, is_available,
  location_lat, location_lng, location_updated_at,
  created_at, updated_at
) VALUES (
  'uuid-v4', '+919876543210', 'John', 'hashed', 'driver', true,
  28.6139, 77.2090, now(),
  '2026-06-30', '2026-06-30'
);
```

---

## 2. Rides Collection → rides Table + offers Table

### MongoDB Schema
```javascript
db.rides.insertOne({
  _id: ObjectId("..."),
  userId: ObjectId("..."),
  driverId: ObjectId("..."),
  
  pickupLocation: {
    address: "123 MG Road",
    lat: 28.6139,
    lng: 77.2090,
    placeId: "place_..."
  },
  dropLocation: {
    address: "456 Connaught Place",
    lat: 28.6331,
    lng: 77.2197,
    placeId: "place_..."
  },
  
  fare: {
    estimatedFare: 150,
    initialFare: 150,
    offeredFare: 140,
    finalFare: 140
  },
  
  status: "completed",  // requested, negotiating, accepted, ongoing, completed
  
  negotiation: {
    negotiationStatus: "closed",
    negotiationExpiresAt: ISODate("..."),
    offers: [
      {
        driverId: ObjectId("..."),
        offeredFare: 150,
        status: "accepted_base"
      },
      {
        driverId: ObjectId("..."),
        offeredFare: 140,
        status: "selected"
      }
    ]
  },
  
  payment: {
    paymentMethod: "cash",
    paymentStatus: "completed"
  },
  
  startedAt: ISODate("..."),
  completedAt: ISODate("..."),
  createdAt: ISODate("..."),
  updatedAt: ISODate("...")
})
```

### PostgreSQL Migration

#### Main Rides Table
```sql
CREATE TABLE rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Users (required)
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES users(id) ON DELETE SET NULL,
  
  -- Pickup Location (normalized)
  pickup_address VARCHAR(500),
  pickup_lat DECIMAL(10, 8),
  pickup_lng DECIMAL(11, 8),
  pickup_place_id VARCHAR(255),
  
  -- Drop Location (normalized)
  drop_address VARCHAR(500),
  drop_lat DECIMAL(10, 8),
  drop_lng DECIMAL(11, 8),
  drop_place_id VARCHAR(255),
  
  -- Fare (normalized)
  estimated_fare DECIMAL(10, 2),
  initial_fare DECIMAL(10, 2),
  offered_fare DECIMAL(10, 2),
  final_fare DECIMAL(10, 2),
  
  -- Status
  status VARCHAR(50) NOT NULL DEFAULT 'requested',
  CHECK (status IN ('requested', 'negotiating', 'accepted', 'ongoing', 'completed', 'cancelled')),
  
  -- Negotiation (fields from negotiation subdoc)
  negotiation_status VARCHAR(50),
  negotiation_expires_at TIMESTAMP,
  
  -- Payment (normalized)
  payment_method VARCHAR(50) CHECK (payment_method IN ('cash', 'upi', 'card', NULL)),
  payment_status VARCHAR(50) CHECK (payment_status IN ('pending', 'completed', 'failed', NULL)),
  
  -- Timestamps
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Constraints
  CONSTRAINT valid_pickup CHECK (pickup_lat IS NULL OR (pickup_lat >= -90 AND pickup_lat <= 90)),
  CONSTRAINT valid_drop CHECK (drop_lat IS NULL OR (drop_lat >= -90 AND drop_lat <= 90)),
  CONSTRAINT valid_pickup_lng CHECK (pickup_lng IS NULL OR (pickup_lng >= -180 AND pickup_lng <= 180)),
  CONSTRAINT valid_drop_lng CHECK (drop_lng IS NULL OR (drop_lng >= -180 AND drop_lng <= 180)),
  CONSTRAINT valid_fares CHECK (
    (estimated_fare IS NULL OR estimated_fare > 0) AND
    (initial_fare IS NULL OR initial_fare > 0) AND
    (offered_fare IS NULL OR offered_fare > 0) AND
    (final_fare IS NULL OR final_fare > 0)
  )
);

-- Indexes for common queries
CREATE INDEX idx_rides_user_id ON rides(user_id);
CREATE INDEX idx_rides_driver_id ON rides(driver_id);
CREATE INDEX idx_rides_status ON rides(status);
CREATE INDEX idx_rides_created_at ON rides(created_at DESC);
CREATE INDEX idx_rides_negotiation_expires ON rides(negotiation_expires_at) 
  WHERE negotiation_expires_at IS NOT NULL;

-- Spatial indexes for nearby driver queries
CREATE INDEX idx_rides_pickup_location ON rides USING GIST (
  ll_to_earth(pickup_lat, pickup_lng)
) WHERE status = 'requested';

CREATE INDEX idx_rides_drop_location ON rides USING GIST (
  ll_to_earth(drop_lat, drop_lng)
);
```

#### Offers Table (Normalized from Rides.negotiation.offers array)
```sql
CREATE TABLE offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  offered_fare DECIMAL(10, 2) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  CHECK (status IN ('pending', 'selected', 'rejected', 'accepted_base')),
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Unique constraint: one offer per driver per ride
  CONSTRAINT unique_offer_per_driver UNIQUE (ride_id, driver_id)
);

-- Indexes
CREATE INDEX idx_offers_ride_id ON offers(ride_id);
CREATE INDEX idx_offers_driver_id ON offers(driver_id);
CREATE INDEX idx_offers_status ON offers(status);
CREATE INDEX idx_offers_created_at ON offers(created_at DESC);
```

### Migration Script Mapping

#### Rides Document
```javascript
const mongoRide = {
  _id: ObjectId("ride123"),
  userId: ObjectId("user123"),
  driverId: ObjectId("driver456"),
  pickupLocation: {
    address: "123 MG Road",
    lat: 28.6139,
    lng: 77.2090,
    placeId: "place_abc"
  },
  dropLocation: {
    address: "456 CP",
    lat: 28.6331,
    lng: 77.2197,
    placeId: "place_xyz"
  },
  fare: {
    estimatedFare: 150,
    initialFare: 150,
    offeredFare: 140,
    finalFare: 140
  },
  status: "completed",
  negotiation: {
    negotiationStatus: "closed",
    negotiationExpiresAt: new Date("2026-06-30T12:00:00Z"),
    offers: [
      { driverId: ObjectId("d1"), offeredFare: 150, status: "accepted_base" },
      { driverId: ObjectId("d2"), offeredFare: 140, status: "selected" }
    ]
  },
  payment: { paymentMethod: "cash", paymentStatus: "completed" },
  startedAt: new Date(),
  completedAt: new Date(),
  createdAt: new Date(),
  updatedAt: new Date()
};

// Transform to PostgreSQL:

// 1. Insert main ride
INSERT INTO rides (
  id, user_id, driver_id,
  pickup_address, pickup_lat, pickup_lng, pickup_place_id,
  drop_address, drop_lat, drop_lng, drop_place_id,
  estimated_fare, initial_fare, offered_fare, final_fare,
  status,
  negotiation_status, negotiation_expires_at,
  payment_method, payment_status,
  started_at, completed_at,
  created_at, updated_at
) VALUES (
  'uuid-v4', 'user123-uuid', 'driver456-uuid',
  '123 MG Road', 28.6139, 77.2090, 'place_abc',
  '456 CP', 28.6331, 77.2197, 'place_xyz',
  150.00, 150.00, 140.00, 140.00,
  'completed',
  'closed', '2026-06-30T12:00:00Z',
  'cash', 'completed',
  now(), now(),
  now(), now()
);

// 2. Insert offers (from negotiation.offers array)
INSERT INTO offers (ride_id, driver_id, offered_fare, status, created_at) VALUES
('ride-uuid', 'd1-uuid', 150.00, 'accepted_base', now()),
('ride-uuid', 'd2-uuid', 140.00, 'selected', now());
```

---

## 3. Additional Considerations

### Soft Deletes vs Hard Deletes
- **MongoDB**: Documents often marked inactive
- **PostgreSQL**: Add `deleted_at` column for soft deletes

```sql
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;
CREATE INDEX idx_users_deleted ON users(deleted_at) 
  WHERE deleted_at IS NULL;
```

### Audit Trail
- Track data changes for compliance

```sql
CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name VARCHAR(50),
  operation VARCHAR(10), -- INSERT, UPDATE, DELETE
  record_id UUID,
  old_values JSONB,
  new_values JSONB,
  changed_by UUID REFERENCES users(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Temporal Data
- Store historical location and fare data

```sql
CREATE TABLE driver_location_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES users(id),
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Partition by time for performance
CREATE TABLE driver_location_history_202606 PARTITION OF driver_location_history
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
```

---

## 4. Performance Optimizations

### PostGIS for Spatial Queries
```sql
-- Install PostGIS
CREATE EXTENSION IF NOT EXISTS earthdistance;
CREATE EXTENSION IF NOT EXISTS cube;

-- Find nearest available drivers (within 5km)
SELECT u.id, u.name, u.phone,
       earth_distance(
         ll_to_earth(u.location_lat, u.location_lng),
         ll_to_earth($1::float, $2::float)
       ) AS distance_meters
FROM users u
WHERE u.role = 'driver' 
  AND u.is_available = true
  AND earth_distance(
    ll_to_earth(u.location_lat, u.location_lng),
    ll_to_earth($1::float, $2::float)
  ) < 5000  -- 5km
ORDER BY distance_meters
LIMIT 20;
```

### Connection Pooling
```sql
-- pgBouncer config for connection pooling
[databases]
biketaxi = host=postgres.example.com port=5432 dbname=biketaxi

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

### Query Optimization
```sql
-- Materialized view for ride statistics
CREATE MATERIALIZED VIEW ride_statistics AS
SELECT
  DATE_TRUNC('hour', created_at) AS hour,
  status,
  COUNT(*) AS ride_count,
  AVG(final_fare) AS avg_fare,
  AVG(EXTRACT(EPOCH FROM (completed_at - started_at)) / 60) AS avg_duration_minutes
FROM rides
GROUP BY DATE_TRUNC('hour', created_at), status;

-- Refresh periodically
REFRESH MATERIALIZED VIEW CONCURRENTLY ride_statistics;
```

---

## 5. Data Validation Rules

### Phone Number
- MongoDB: Stored as string
- PostgreSQL: Validated with regex + UNIQUE constraint

```sql
ALTER TABLE users 
  ADD CONSTRAINT valid_phone CHECK (phone ~ '^\+?[0-9]{10,15}$');
```

### Email (if added)
```sql
ALTER TABLE users 
  ADD CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$');
```

### Decimal Precision for Money
- Use `DECIMAL(10, 2)` for currency (never FLOAT)
- Precision: 10 digits total, 2 after decimal

---

## 6. Migration Checklist

- [ ] All MongoDB documents mapped to PostgreSQL tables
- [ ] All nested objects normalized to separate tables
- [ ] Foreign key relationships defined
- [ ] Unique constraints for identifiers
- [ ] Check constraints for valid values
- [ ] Indexes created for all common queries
- [ ] Spatial indexes for location queries (PostGIS)
- [ ] Data types match application requirements
- [ ] Default values set appropriately
- [ ] Timestamp columns have defaults
- [ ] Soft delete columns added (if needed)
- [ ] Audit trail table created
- [ ] Connection pooling configured
- [ ] Backup and rollback scripts tested

---

## 7. Migration Flow

```
Phase 1: Analyze MongoDB Schema ✅
         └─ Document all collections and fields

Phase 2: Design PostgreSQL Schema ✅
         └─ Create normalized, typed tables with constraints

Phase 3: Generate Migration Scripts
         └─ Write ETL: MongoDB → PostgreSQL

Phase 4: Test Data Migration
         └─ Validate data integrity and record counts

Phase 5: Deploy PostgreSQL
         └─ Create database and schema

Phase 6: Run Migration
         └─ Transform and load data

Phase 7: Validate Migration
         └─ Check for data loss and consistency

Phase 8: Switch Applications
         └─ Update connection strings
         └─ Run compatibility tests

Phase 9: Archive MongoDB
         └─ Keep as backup for 30 days
```

---

## References

- PostgreSQL Docs: https://www.postgresql.org/docs/
- PostGIS: https://postgis.net/
- Prisma Docs: https://www.prisma.io/docs/
- JSON/JSONB: https://www.postgresql.org/docs/current/datatype-json.html
- Indexing Strategy: https://www.postgresql.org/docs/current/indexes.html

---

**Version**: 1.0  
**Created**: 2026-06-30  
**Status**: Phase 2 - Schema Design Complete
