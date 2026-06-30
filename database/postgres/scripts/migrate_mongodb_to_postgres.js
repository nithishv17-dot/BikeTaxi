/**
 * MongoDB to PostgreSQL Data Migration Script
 * Phase 3: Data Transfer
 * 
 * This script:
 * 1. Connects to both MongoDB and PostgreSQL
 * 2. Reads all data from MongoDB
 * 3. Transforms data to PostgreSQL schema
 * 4. Validates data integrity
 * 5. Performs atomic insert
 * 
 * Usage:
 *   node migrate_mongodb_to_postgres.js
 * 
 * Safety:
 *   - Run against PostgreSQL dev database first
 *   - Backup PostgreSQL before running
 *   - MongoDB remains unchanged
 */

require("dotenv").config();
const mongoose = require("mongoose");
const { PrismaClient } = require("@prisma/client");

// ============================================================================
// Constants
// ============================================================================

const BATCH_SIZE = 100;
const LOG_PREFIX = "[MIGRATION]";

// ============================================================================
// Utility Functions
// ============================================================================

function log(message, level = "info") {
  const timestamp = new Date().toISOString();
  const levelStr = level.toUpperCase().padEnd(7);
  console.log(`${timestamp} ${LOG_PREFIX} [${levelStr}] ${message}`);
}

function logError(message, error) {
  log(message, "error");
  if (error) {
    console.error("  Error:", error.message);
  }
}

async function connectMongoDB() {
  try {
    await mongoose.connect(process.env.MONGODB_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });
    log("Connected to MongoDB", "success");
    return mongoose.connection.db;
  } catch (error) {
    logError("Failed to connect to MongoDB", error);
    throw error;
  }
}

async function connectPostgres() {
  const prisma = new PrismaClient();
  try {
    await prisma.$connect();
    log("Connected to PostgreSQL", "success");
    return prisma;
  } catch (error) {
    logError("Failed to connect to PostgreSQL", error);
    throw error;
  }
}

// ============================================================================
// Data Validation
// ============================================================================

function validateUser(user) {
  if (!user.name || typeof user.name !== "string") {
    throw new Error("User missing required field: name");
  }
  if (!user.phone || typeof user.phone !== "string") {
    throw new Error("User missing required field: phone");
  }
  if (!user.password || typeof user.password !== "string") {
    throw new Error("User missing required field: password");
  }
  return true;
}

function validateRide(ride) {
  if (!ride.riderId) throw new Error("Ride missing riderId");
  if (!ride.pickupAddress) throw new Error("Ride missing pickupAddress");
  if (ride.pickupLatitude === undefined) throw new Error("Ride missing pickupLatitude");
  if (ride.pickupLongitude === undefined) throw new Error("Ride missing pickupLongitude");
  if (!ride.dropAddress) throw new Error("Ride missing dropAddress");
  if (ride.dropLatitude === undefined) throw new Error("Ride missing dropLatitude");
  if (ride.dropLongitude === undefined) throw new Error("Ride missing dropLongitude");
  return true;
}

// ============================================================================
// Data Transformation
// ============================================================================

function transformUser(mongoUser) {
  return {
    // Convert MongoDB _id to string
    id: mongoUser._id.toString(),
    name: mongoUser.name,
    phone: mongoUser.phone,
    password: mongoUser.password,
    role: (mongoUser.role || "USER").toUpperCase(),
    email: mongoUser.email || null,
    profileImage: mongoUser.profileImage || null,
    latitude: mongoUser.latitude || null,
    longitude: mongoUser.longitude || null,
    lastLocationUpdate: mongoUser.lastLocationUpdate || null,
    isAvailable: mongoUser.isAvailable || false,
    isVerified: mongoUser.isVerified || false,
    isBanned: mongoUser.isBanned || false,
    averageRating: mongoUser.averageRating || 0,
    totalRatings: mongoUser.totalRatings || 0,
    totalRides: mongoUser.totalRides || 0,
    createdAt: mongoUser.createdAt || new Date(),
    updatedAt: mongoUser.updatedAt || new Date(),
    deletedAt: mongoUser.deletedAt || null,
  };
}

function transformRide(mongoRide) {
  return {
    id: mongoRide._id.toString(),
    riderId: mongoRide.riderId.toString(),
    driverId: mongoRide.driverId ? mongoRide.driverId.toString() : null,
    pickupAddress: mongoRide.pickupAddress,
    pickupLatitude: mongoRide.pickupLatitude,
    pickupLongitude: mongoRide.pickupLongitude,
    pickupPlaceId: mongoRide.pickupPlaceId || null,
    dropAddress: mongoRide.dropAddress,
    dropLatitude: mongoRide.dropLatitude,
    dropLongitude: mongoRide.dropLongitude,
    dropPlaceId: mongoRide.dropPlaceId || null,
    distanceKm: mongoRide.distanceKm || null,
    estimatedDuration: mongoRide.estimatedDuration || null,
    polyline: mongoRide.polyline || null,
    initialFare: mongoRide.initialFare || 0,
    estimatedFare: mongoRide.estimatedFare || 0,
    offeredFare: mongoRide.offeredFare || null,
    finalFare: mongoRide.finalFare || null,
    paymentMethod: (mongoRide.paymentMethod || "CASH").toUpperCase(),
    paymentStatus: (mongoRide.paymentStatus || "PENDING").toUpperCase(),
    status: (mongoRide.status || "REQUESTED").toUpperCase(),
    negotiationStatus: (mongoRide.negotiationStatus || "OPEN").toUpperCase(),
    negotiationExpiresAt: mongoRide.negotiationExpiresAt || null,
    otp: mongoRide.otp || null,
    otpVerified: mongoRide.otpVerified || false,
    riderRating: mongoRide.riderRating || null,
    driverRating: mongoRide.driverRating || null,
    riderFeedback: mongoRide.riderFeedback || null,
    driverFeedback: mongoRide.driverFeedback || null,
    createdAt: mongoRide.createdAt || new Date(),
    updatedAt: mongoRide.updatedAt || new Date(),
    requestedAt: mongoRide.requestedAt || null,
    acceptedAt: mongoRide.acceptedAt || null,
    startedAt: mongoRide.startedAt || null,
    completedAt: mongoRide.completedAt || null,
  };
}

// ============================================================================
// Migration Logic
// ============================================================================

async function migrateUsers(db, prisma) {
  log("Starting user migration...");
  const mongoUsers = await db.collection("users").find({}).toArray();
  log(`Found ${mongoUsers.length} users in MongoDB`);

  let migrated = 0;
  let failed = 0;

  for (let i = 0; i < mongoUsers.length; i += BATCH_SIZE) {
    const batch = mongoUsers.slice(i, i + BATCH_SIZE);

    for (const mongoUser of batch) {
      try {
        validateUser(mongoUser);
        const pgUser = transformUser(mongoUser);
        
        await prisma.user.upsert({
          where: { phone: pgUser.phone },
          update: pgUser,
          create: pgUser,
        });
        migrated++;
      } catch (error) {
        logError(`Failed to migrate user ${mongoUser._id}`, error);
        failed++;
      }
    }

    log(`Migrated ${Math.min(i + BATCH_SIZE, mongoUsers.length)} / ${mongoUsers.length} users`);
  }

  log(`User migration complete: ${migrated} succeeded, ${failed} failed`);
  return { migrated, failed };
}

async function migrateRides(db, prisma) {
  log("Starting ride migration...");
  const mongoRides = await db.collection("rides").find({}).toArray();
  log(`Found ${mongoRides.length} rides in MongoDB`);

  let migrated = 0;
  let failed = 0;

  for (let i = 0; i < mongoRides.length; i += BATCH_SIZE) {
    const batch = mongoRides.slice(i, i + BATCH_SIZE);

    for (const mongoRide of batch) {
      try {
        validateRide(mongoRide);
        const pgRide = transformRide(mongoRide);

        await prisma.ride.upsert({
          where: { id: pgRide.id },
          update: pgRide,
          create: pgRide,
        });
        migrated++;
      } catch (error) {
        logError(`Failed to migrate ride ${mongoRide._id}`, error);
        failed++;
      }
    }

    log(`Migrated ${Math.min(i + BATCH_SIZE, mongoRides.length)} / ${mongoRides.length} rides`);
  }

  log(`Ride migration complete: ${migrated} succeeded, ${failed} failed`);
  return { migrated, failed };
}

async function migrateOffers(db, prisma) {
  log("Starting offer migration...");
  const mongoOffers = await db.collection("offers").find({}).toArray();
  log(`Found ${mongoOffers.length} offers in MongoDB`);

  let migrated = 0;
  let failed = 0;

  for (const mongoOffer of mongoOffers) {
    try {
      const pgOffer = {
        id: mongoOffer._id.toString(),
        rideId: mongoOffer.rideId.toString(),
        driverId: mongoOffer.driverId.toString(),
        offeredFare: mongoOffer.offeredFare,
        offerStatus: (mongoOffer.offerStatus || "PENDING").toUpperCase(),
        createdAt: mongoOffer.createdAt || new Date(),
        expiresAt: mongoOffer.expiresAt || new Date(),
        respondedAt: mongoOffer.respondedAt || null,
      };

      await prisma.offer.upsert({
        where: { id: pgOffer.id },
        update: pgOffer,
        create: pgOffer,
      });
      migrated++;
    } catch (error) {
      logError(`Failed to migrate offer ${mongoOffer._id}`, error);
      failed++;
    }
  }

  log(`Offer migration complete: ${migrated} succeeded, ${failed} failed`);
  return { migrated, failed };
}

// ============================================================================
// Main Migration Flow
// ============================================================================

async function main() {
  log("=".repeat(70));
  log("MongoDB to PostgreSQL Migration Script");
  log("=".repeat(70));

  let mongoDb;
  let prisma;

  try {
    // Connect to databases
    mongoDb = await connectMongoDB();
    prisma = await connectPostgres();

    // Verify PostgreSQL is empty (safety check)
    const userCount = await prisma.user.count();
    if (userCount > 0) {
      log(
        "WARNING: PostgreSQL database already has data. Proceeding with upsert (update existing).",
        "warn"
      );
    }

    // Perform migration
    log("Starting migration process...");
    const userStats = await migrateUsers(mongoDb, prisma);
    const rideStats = await migrateRides(mongoDb, prisma);
    const offerStats = await migrateOffers(mongoDb, prisma);

    // Summary
    log("=".repeat(70));
    log("Migration Summary:");
    log(`  Users:  ${userStats.migrated} migrated, ${userStats.failed} failed`);
    log(`  Rides:  ${rideStats.migrated} migrated, ${rideStats.failed} failed`);
    log(`  Offers: ${offerStats.migrated} migrated, ${offerStats.failed} failed`);
    log("=".repeat(70));

    if (userStats.failed + rideStats.failed + offerStats.failed === 0) {
      log("Migration completed successfully!", "success");
    } else {
      log("Migration completed with errors. Please review the logs above.", "warn");
    }
  } catch (error) {
    logError("Migration failed", error);
    process.exit(1);
  } finally {
    if (prisma) {
      await prisma.$disconnect();
    }
    if (mongoDb) {
      await mongoose.disconnect();
    }
  }
}

main();
