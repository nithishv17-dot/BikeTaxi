/**
 * PostgreSQL Database Configuration
 * Phase 3: Database Setup
 * 
 * This module exports the Prisma client instance for use throughout the backend.
 * It handles connection pooling and error handling.
 */

import { PrismaClient } from "@prisma/client";

let prisma: PrismaClient;

if (process.env.NODE_ENV === "production") {
  prisma = new PrismaClient({
    log: [
      {
        emit: "event",
        level: "error",
      },
    ],
  });
} else {
  // Use a global variable to store the Prisma client in development
  // This prevents creating multiple Prisma clients on hot reload
  const globalForPrisma = global as unknown as { prisma: PrismaClient };
  if (!globalForPrisma.prisma) {
    globalForPrisma.prisma = new PrismaClient({
      log: [
        { emit: "stdout", level: "query" },
        { emit: "stdout", level: "error" },
        { emit: "stdout", level: "warn" },
      ],
    });
  }
  prisma = globalForPrisma.prisma;
}

// Handle connection errors
prisma.$on("error", (e: any) => {
  console.error("[Prisma Error]", e);
});

export default prisma;
