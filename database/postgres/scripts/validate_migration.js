/**
 * PostgreSQL Data Validation Script
 * Phase 3: Post-Migration Verification
 * 
 * This script validates:
 * 1. Data integrity after migration
 * 2. Foreign key constraints
 * 3. Referential integrity
 * 4. Data type correctness
 * 5. Completeness of migration
 * 
 * Usage:
 *   node validate_migration.js
 */

require("dotenv").config();
const { PrismaClient } = require("@prisma/client");

// ============================================================================
// Constants
// ============================================================================

const LOG_PREFIX = "[VALIDATION]";
const COLORS = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
};

// ============================================================================
// Utility Functions
// ============================================================================

function log(message, status = "info") {
  const timestamp = new Date().toISOString();
  let color = COLORS.reset;

  switch (status) {
    case "success":
      color = COLORS.green;
      status = "✓";
      break;
    case "error":
      color = COLORS.red;
      status = "✗";
      break;
    case "warn":
      color = COLORS.yellow;
      status = "!";
      break;
    case "info":
      color = COLORS.blue;
      status = "ℹ";
      break;
  }

  console.log(`${color}${timestamp} ${LOG_PREFIX} [${status}]${COLORS.reset} ${message}`);
}

// ============================================================================
// Validation Checks
// ============================================================================

async function checkUserIntegrity(prisma) {
  log("Validating User data integrity...");
  let issues = 0;

  try {
    // Check for null required fields
    const usersWithNullName = await prisma.user.count({
      where: { name: null },
    });
    if (usersWithNullName > 0) {
      log(`Found ${usersWithNullName} users with null name`, "error");
      issues += usersWithNullName;
    }

    // Check for duplicate phones
    const phoneDuplicates = await prisma.$queryRaw`
      SELECT phone, COUNT(*) as count
      FROM users
      WHERE deleted_at IS NULL
      GROUP BY phone
      HAVING COUNT(*) > 1
    `;

    if (phoneDuplicates.length > 0) {
      log(`Found ${phoneDuplicates.length} duplicate phone numbers`, "error");
      issues += phoneDuplicates.length;
    }

    // Check for valid roles
    const invalidRoles = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM users
      WHERE role NOT IN ('USER', 'DRIVER', 'ADMIN')
    `;

    if (invalidRoles[0]?.count > 0) {
      log(`Found ${invalidRoles[0].count} users with invalid roles`, "error");
      issues += invalidRoles[0].count;
    }

    // Check password hashing (should not be plain text)
    const plainTextPasswords = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM users
      WHERE password LIKE '%password%' 
        OR password LIKE '%123456%'
        OR length(password) < 20
    `;

    if (plainTextPasswords[0]?.count > 0) {
      log(
        `Warning: Found ${plainTextPasswords[0].count} potentially plain-text passwords`,
        "warn"
      );
    }

    const userCount = await prisma.user.count();
    log(`User integrity check complete: ${userCount} users, ${issues} issues found`, issues === 0 ? "success" : "warn");
    return issues;
  } catch (error) {
    log(`User integrity check failed: ${error.message}`, "error");
    return 1;
  }
}

async function checkRideIntegrity(prisma) {
  log("Validating Ride data integrity...");
  let issues = 0;

  try {
    // Check for missing rider references
    const orphanRides = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides r
      WHERE r.rider_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = r.rider_id)
    `;

    if (orphanRides[0]?.count > 0) {
      log(`Found ${orphanRides[0].count} rides with non-existent rider`, "error");
      issues += orphanRides[0].count;
    }

    // Check for missing driver references (if driver is assigned)
    const orphanDrivers = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides r
      WHERE r.driver_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = r.driver_id)
    `;

    if (orphanDrivers[0]?.count > 0) {
      log(`Found ${orphanDrivers[0].count} rides with non-existent driver`, "error");
      issues += orphanDrivers[0].count;
    }

    // Check for invalid status values
    const invalidStatus = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides
      WHERE status NOT IN ('REQUESTED', 'NEGOTIATING', 'ACCEPTED', 'STARTED', 'COMPLETED', 'CANCELLED')
    `;

    if (invalidStatus[0]?.count > 0) {
      log(`Found ${invalidStatus[0].count} rides with invalid status`, "error");
      issues += invalidStatus[0].count;
    }

    // Check for invalid payment methods
    const invalidPayment = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides
      WHERE payment_method NOT IN ('CASH', 'UPI', 'CARD')
    `;

    if (invalidPayment[0]?.count > 0) {
      log(`Found ${invalidPayment[0].count} rides with invalid payment method`, "error");
      issues += invalidPayment[0].count;
    }

    // Check for duplicate locations (same pickup and drop)
    const duplicateLocations = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides
      WHERE pickup_latitude = drop_latitude 
        AND pickup_longitude = drop_longitude
    `;

    if (duplicateLocations[0]?.count > 0) {
      log(`Found ${duplicateLocations[0].count} rides with identical pickup/drop locations`, "warn");
    }

    // Check for invalid fare amounts
    const invalidFares = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides
      WHERE initial_fare < 0 
        OR estimated_fare < 0
        OR (offered_fare IS NOT NULL AND offered_fare <= 0)
        OR (final_fare IS NOT NULL AND final_fare <= 0)
    `;

    if (invalidFares[0]?.count > 0) {
      log(`Found ${invalidFares[0].count} rides with invalid fares`, "error");
      issues += invalidFares[0].count;
    }

    // Check for invalid ratings
    const invalidRatings = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM rides
      WHERE (rider_rating IS NOT NULL AND (rider_rating < 1 OR rider_rating > 5))
         OR (driver_rating IS NOT NULL AND (driver_rating < 1 OR driver_rating > 5))
    `;

    if (invalidRatings[0]?.count > 0) {
      log(`Found ${invalidRatings[0].count} rides with invalid ratings`, "error");
      issues += invalidRatings[0].count;
    }

    const rideCount = await prisma.ride.count();
    log(`Ride integrity check complete: ${rideCount} rides, ${issues} issues found`, issues === 0 ? "success" : "warn");
    return issues;
  } catch (error) {
    log(`Ride integrity check failed: ${error.message}`, "error");
    return 1;
  }
}

async function checkOfferIntegrity(prisma) {
  log("Validating Offer data integrity...");
  let issues = 0;

  try {
    // Check for missing ride references
    const orphanOffers = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM offers o
      WHERE NOT EXISTS (SELECT 1 FROM rides r WHERE r.id = o.ride_id)
    `;

    if (orphanOffers[0]?.count > 0) {
      log(`Found ${orphanOffers[0].count} offers with non-existent ride`, "error");
      issues += orphanOffers[0].count;
    }

    // Check for missing driver references
    const orphanDrivers = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM offers o
      WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = o.driver_id)
    `;

    if (orphanDrivers[0]?.count > 0) {
      log(`Found ${orphanDrivers[0].count} offers with non-existent driver`, "error");
      issues += orphanDrivers[0].count;
    }

    // Check for invalid offer status
    const invalidStatus = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM offers
      WHERE offer_status NOT IN ('PENDING', 'SELECTED', 'ACCEPTED', 'REJECTED', 'EXPIRED')
    `;

    if (invalidStatus[0]?.count > 0) {
      log(`Found ${invalidStatus[0].count} offers with invalid status`, "error");
      issues += invalidStatus[0].count;
    }

    // Check for invalid fares
    const invalidFares = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM offers
      WHERE offered_fare <= 0
    `;

    if (invalidFares[0]?.count > 0) {
      log(`Found ${invalidFares[0].count} offers with invalid fares`, "error");
      issues += invalidFares[0].count;
    }

    const offerCount = await prisma.offer.count();
    log(`Offer integrity check complete: ${offerCount} offers, ${issues} issues found`, issues === 0 ? "success" : "warn");
    return issues;
  } catch (error) {
    log(`Offer integrity check failed: ${error.message}`, "error");
    return 1;
  }
}

async function checkRatingIntegrity(prisma) {
  log("Validating Rating data integrity...");
  let issues = 0;

  try {
    // Check for missing ride references
    const orphanRatings = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM ratings r
      WHERE NOT EXISTS (SELECT 1 FROM rides ri WHERE ri.id = r.ride_id)
    `;

    if (orphanRatings[0]?.count > 0) {
      log(`Found ${orphanRatings[0].count} ratings with non-existent ride`, "error");
      issues += orphanRatings[0].count;
    }

    // Check for invalid rating values
    const invalidRatings = await prisma.$queryRaw`
      SELECT COUNT(*) as count FROM ratings
      WHERE rating < 1 OR rating > 5
    `;

    if (invalidRatings[0]?.count > 0) {
      log(`Found ${invalidRatings[0].count} ratings with invalid values`, "error");
      issues += invalidRatings[0].count;
    }

    const ratingCount = await prisma.rating.count();
    log(`Rating integrity check complete: ${ratingCount} ratings, ${issues} issues found`, issues === 0 ? "success" : "warn");
    return issues;
  } catch (error) {
    log(`Rating integrity check failed: ${error.message}`, "error");
    return 1;
  }
}

async function checkDataCompleteness(prisma) {
  log("Checking data completeness...");

  try {
    const stats = {
      users: await prisma.user.count(),
      riders: await prisma.user.count({ where: { role: "USER" } }),
      drivers: await prisma.user.count({ where: { role: "DRIVER" } }),
      rides: await prisma.ride.count(),
      completedRides: await prisma.ride.count({ where: { status: "COMPLETED" } }),
      activeRides: await prisma.ride.count({ where: { status: { in: ["REQUESTED", "NEGOTIATING", "ACCEPTED", "STARTED"] } } }),
      offers: await prisma.offer.count(),
      ratings: await prisma.rating.count(),
    };

    log(`Data Summary:`, "info");
    log(`  Total Users: ${stats.users} (${stats.riders} riders, ${stats.drivers} drivers)`, "info");
    log(`  Total Rides: ${stats.rides} (${stats.activeRides} active, ${stats.completedRides} completed)`, "info");
    log(`  Total Offers: ${stats.offers}`, "info");
    log(`  Total Ratings: ${stats.ratings}`, "info");

    return stats;
  } catch (error) {
    log(`Data completeness check failed: ${error.message}`, "error");
    return null;
  }
}

// ============================================================================
// Main Validation Flow
// ============================================================================

async function main() {
  log("=".repeat(70));
  log("PostgreSQL Data Validation Script");
  log("=".repeat(70));

  const prisma = new PrismaClient();

  try {
    // Connect to database
    await prisma.$connect();
    log("Connected to PostgreSQL", "success");

    // Run all validation checks
    let totalIssues = 0;

    totalIssues += await checkUserIntegrity(prisma);
    totalIssues += await checkRideIntegrity(prisma);
    totalIssues += await checkOfferIntegrity(prisma);
    totalIssues += await checkRatingIntegrity(prisma);
    const stats = await checkDataCompleteness(prisma);

    // Summary
    log("=".repeat(70));
    if (totalIssues === 0) {
      log("Validation complete: All checks passed!", "success");
    } else {
      log(`Validation complete: Found ${totalIssues} issues`, "warn");
    }
    log("=".repeat(70));

    process.exit(totalIssues === 0 ? 0 : 1);
  } catch (error) {
    log(`Validation failed: ${error.message}`, "error");
    process.exit(1);
  } finally {
    await prisma.$disconnect();
  }
}

main();
