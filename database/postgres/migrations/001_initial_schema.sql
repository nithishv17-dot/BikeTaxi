-- BikeTaxi PostgreSQL Initial Schema
-- Phase 3: Database Migration
-- Created: 2026-06-30

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- Users Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL DEFAULT 'USER' CHECK (role IN ('USER', 'DRIVER', 'ADMIN')),
  email VARCHAR(255) UNIQUE,
  profile_image TEXT,
  
  -- Location tracking
  latitude FLOAT,
  longitude FLOAT,
  last_location_update TIMESTAMP,
  
  -- Availability (for drivers)
  is_available BOOLEAN DEFAULT false,
  
  -- Account status
  is_verified BOOLEAN DEFAULT false,
  is_banned BOOLEAN DEFAULT false,
  
  -- Ratings and statistics
  average_rating FLOAT DEFAULT 0,
  total_ratings INTEGER DEFAULT 0,
  total_rides INTEGER DEFAULT 0,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP,
  
  -- Indexes for common queries
  CONSTRAINT users_phone_idx UNIQUE (phone) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_is_available ON users(is_available);
CREATE INDEX idx_users_created_at ON users(created_at);

-- ============================================================================
-- Rides Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS rides (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  
  -- Rider info
  rider_id TEXT NOT NULL,
  
  -- Driver info (populated when driver accepts)
  driver_id TEXT,
  
  -- Location data - Pickup
  pickup_address VARCHAR(500) NOT NULL,
  pickup_latitude FLOAT NOT NULL,
  pickup_longitude FLOAT NOT NULL,
  pickup_place_id VARCHAR(255),
  
  -- Location data - Dropoff
  drop_address VARCHAR(500) NOT NULL,
  drop_latitude FLOAT NOT NULL,
  drop_longitude FLOAT NOT NULL,
  drop_place_id VARCHAR(255),
  
  -- Distance and route
  distance_km FLOAT,
  estimated_duration INTEGER, -- seconds
  polyline TEXT, -- encoded polyline
  
  -- Fare management
  initial_fare FLOAT DEFAULT 0,
  estimated_fare FLOAT DEFAULT 0,
  offered_fare FLOAT,
  final_fare FLOAT,
  
  -- Payment
  payment_method VARCHAR(50) DEFAULT 'CASH' CHECK (payment_method IN ('CASH', 'UPI', 'CARD')),
  payment_status VARCHAR(50) DEFAULT 'PENDING' CHECK (payment_status IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED')),
  
  -- Negotiation
  status VARCHAR(50) DEFAULT 'REQUESTED' CHECK (
    status IN ('REQUESTED', 'NEGOTIATING', 'ACCEPTED', 'STARTED', 'COMPLETED', 'CANCELLED')
  ),
  negotiation_status VARCHAR(50) DEFAULT 'OPEN' CHECK (negotiation_status IN ('OPEN', 'LOCKED', 'EXPIRED')),
  negotiation_expires_at TIMESTAMP,
  
  -- OTP for verification
  otp VARCHAR(10),
  otp_verified BOOLEAN DEFAULT false,
  
  -- Ratings
  rider_rating SMALLINT,
  driver_rating SMALLINT,
  rider_feedback TEXT,
  driver_feedback TEXT,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  requested_at TIMESTAMP,
  accepted_at TIMESTAMP,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  
  FOREIGN KEY (rider_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_rides_rider_id ON rides(rider_id);
CREATE INDEX idx_rides_driver_id ON rides(driver_id);
CREATE INDEX idx_rides_status ON rides(status);
CREATE INDEX idx_rides_payment_status ON rides(payment_status);
CREATE INDEX idx_rides_created_at ON rides(created_at);
CREATE INDEX idx_rides_completed_at ON rides(completed_at);

-- ============================================================================
-- Offers Table (Driver Bids)
-- ============================================================================
CREATE TABLE IF NOT EXISTS offers (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  ride_id TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  
  -- Offer details
  offered_fare FLOAT NOT NULL,
  offer_status VARCHAR(50) DEFAULT 'PENDING' CHECK (
    offer_status IN ('PENDING', 'SELECTED', 'ACCEPTED', 'REJECTED', 'EXPIRED')
  ),
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP NOT NULL,
  responded_at TIMESTAMP,
  
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_offers_ride_id ON offers(ride_id);
CREATE INDEX idx_offers_driver_id ON offers(driver_id);
CREATE INDEX idx_offers_status ON offers(offer_status);
CREATE INDEX idx_offers_created_at ON offers(created_at);

-- ============================================================================
-- Ratings Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS ratings (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  ride_id TEXT NOT NULL,
  rated_by_id TEXT NOT NULL,
  rated_user_id TEXT NOT NULL,
  
  -- Rating info
  rating SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (rated_by_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (rated_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_ratings_ride_id ON ratings(ride_id);
CREATE INDEX idx_ratings_rated_by_id ON ratings(rated_by_id);
CREATE INDEX idx_ratings_rated_user_id ON ratings(rated_user_id);

-- ============================================================================
-- Views for Common Queries
-- ============================================================================

-- View: Active Rides (for dashboards)
CREATE OR REPLACE VIEW active_rides AS
SELECT 
  r.*,
  u.name as rider_name,
  u.phone as rider_phone,
  d.name as driver_name,
  d.phone as driver_phone
FROM rides r
LEFT JOIN users u ON r.rider_id = u.id
LEFT JOIN users d ON r.driver_id = d.id
WHERE r.status IN ('REQUESTED', 'NEGOTIATING', 'ACCEPTED', 'STARTED');

-- View: Driver Statistics
CREATE OR REPLACE VIEW driver_statistics AS
SELECT 
  u.id,
  u.name,
  u.phone,
  u.is_available,
  u.average_rating,
  u.total_rides,
  COUNT(DISTINCT r.id) as completed_rides_total,
  COALESCE(AVG(r1.driver_rating), 0) as avg_driver_rating,
  MAX(r.completed_at) as last_ride_date
FROM users u
LEFT JOIN rides r ON u.id = r.driver_id AND r.status = 'COMPLETED'
LEFT JOIN ratings r1 ON r.id = r1.ride_id AND r1.rated_by_id = r.rider_id
WHERE u.role = 'DRIVER'
GROUP BY u.id;

-- View: Rider Statistics
CREATE OR REPLACE VIEW rider_statistics AS
SELECT 
  u.id,
  u.name,
  u.phone,
  u.average_rating,
  u.total_rides,
  COUNT(DISTINCT r.id) as total_rides_completed,
  COALESCE(AVG(r1.rider_rating), 0) as avg_rider_rating,
  MAX(r.completed_at) as last_ride_date
FROM users u
LEFT JOIN rides r ON u.id = r.rider_id AND r.status = 'COMPLETED'
LEFT JOIN ratings r1 ON r.id = r1.ride_id AND r1.rated_by_id = r.driver_id
WHERE u.role = 'USER'
GROUP BY u.id;

-- ============================================================================
-- Triggers for Updated_At Timestamps
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER rides_updated_at
BEFORE UPDATE ON rides
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- Constraints for Data Integrity
-- ============================================================================

-- Ensure pickup and drop are different
ALTER TABLE rides ADD CONSTRAINT check_different_locations CHECK (
  NOT (pickup_latitude = drop_latitude AND pickup_longitude = drop_longitude)
);

-- Ensure valid fare amounts
ALTER TABLE rides ADD CONSTRAINT check_positive_fares CHECK (
  initial_fare >= 0 AND 
  estimated_fare >= 0 AND 
  (offered_fare IS NULL OR offered_fare > 0) AND
  (final_fare IS NULL OR final_fare > 0)
);

-- Ensure valid ratings
ALTER TABLE ratings ADD CONSTRAINT check_rating_range CHECK (rating >= 1 AND rating <= 5);
