# Phase 6: Dual-Write Pattern Implementation

## Overview

Phase 6 implements a dual-write pattern that enables the backend to write simultaneously to both MongoDB and PostgreSQL. This allows for gradual data migration while maintaining full rollback capability and zero downtime.

## Architecture

```
Application Layer
       ↓
Dual-Write Manager
       ├─→ MongoDB (Original)
       └─→ PostgreSQL (New)
       ↓
Data Consistency Checker
       ↓
Migration Tracker
       ↓
Health Checks & Validation
```

## Components

### 1. Dual-Write Manager (`src/middleware/dualWrite.ts`)
Manages simultaneous writes to both databases.

**Features:**
- User entity dual-write with field mapping
- Ride entity dual-write with status tracking
- Configurable failure modes (strict/lenient)
- Write operation logging and monitoring
- Runtime enable/disable capability

**Configuration:**
```env
DUAL_WRITE_ENABLED=true
MONGO_FIRST_WRITE=true
POSTGRES_FIRST_WRITE=false
DUAL_WRITE_FAILURE_MODE=lenient
DUAL_WRITE_LOG_DETAILS=true
```

**Usage:**
```typescript
const dualWriteManager = new DualWriteManager(prismaClient);

// Write user to both databases
const result = await dualWriteManager.writeUser(mongoUserModel, userData);
console.log(result.mongo); // MongoDB result
console.log(result.postgres); // PostgreSQL result

// Get statistics
const stats = dualWriteManager.getMigrationStats();
```

### 2. Consistency Check Service (`src/services/consistencyCheck.ts`)
Validates data integrity between MongoDB and PostgreSQL.

**Features:**
- User consistency verification
- Ride consistency verification
- Field-by-field comparison
- Identification of inconsistencies
- Migration readiness assessment

**Usage:**
```typescript
const checkService = new ConsistencyCheckService(
  prismaClient,
  mongoUserModel,
  mongoRideModel
);

// Check user data consistency
const userReport = await checkService.checkUserConsistency();
console.log(userReport.overallStatus); // 'consistent' | 'partial' | 'inconsistent'

// Get full consistency report
const report = await checkService.generateFullReport();
console.log(report.overall); // 'FULLY_CONSISTENT' | 'PARTIALLY_CONSISTENT' | 'INCONSISTENT'
```

### 3. Migration Tracker Service (`src/services/migrationTracker.ts`)
Tracks migration progress and records all data transfers.

**Features:**
- Migration batch tracking
- Progress reporting with ETAs
- Failed record identification
- Audit log export (CSV)
- Real-time statistics

**Usage:**
```typescript
const tracker = new MigrationTrackerService(prismaClient);

// Start migration
tracker.startMigration('User', totalCount);

// Record successful migration
tracker.recordMigration(mongoId, postgresId, 'User', 'completed');

// Record failed migration
tracker.recordMigration(mongoId, postgresId, 'User', 'failed', errorMessage);

// Get progress
const progress = tracker.getProgress();
console.log(`${progress.percentComplete}% complete`);
console.log(`ETA: ${progress.estimatedTimeRemaining}`);

// Export audit log
const csv = tracker.exportLog();
```

## Migration Workflow

### Step 1: Enable Dual-Write (No Changes to Existing Data)
```bash
# Set environment variable
export DUAL_WRITE_ENABLED=true

# Restart backend
npm run dev
```

**State After Step 1:**
- MongoDB: Original data unchanged
- PostgreSQL: Receives new writes alongside MongoDB
- Existing data: Not migrated yet
- Rollback: Trivial (disable dual-write)

### Step 2: Validate Data Consistency
```bash
# Check consistency of User data
curl http://localhost:5000/api/migration/consistency/users

# Check consistency of Ride data
curl http://localhost:5000/api/migration/consistency/rides

# Get full report
curl http://localhost:5000/api/migration/status
```

**Expected Response:**
```json
{
  "users": {
    "overallStatus": "consistent",
    "totalMongoRecords": 150,
    "totalPostgresRecords": 150,
    "matching": 150,
    "mongoOnly": 0,
    "postgresOnly": 0
  },
  "rides": {
    "overallStatus": "consistent",
    "totalMongoRecords": 500,
    "totalPostgresRecords": 500,
    "matching": 500,
    "mongoOnly": 0,
    "postgresOnly": 0
  },
  "overall": "FULLY_CONSISTENT"
}
```

### Step 3: Migrate Historical Data
```bash
# Run migration script
npm run migrate:data

# Or migrate specific entity
npm run migrate:users
npm run migrate:rides
```

**What Happens:**
1. Reads all historical records from MongoDB
2. Inserts into PostgreSQL (with validation)
3. Compares checksums for verification
4. Logs all transfers to audit table
5. Reports success/failure

### Step 4: Validate Post-Migration Consistency
```bash
# Run consistency check again
curl http://localhost:5000/api/migration/consistency/full

# Verify migration rate
curl http://localhost:5000/api/migration/progress
```

### Step 5: Switch to PostgreSQL (Phase 8)
After validation and QA:
1. Disable dual-write: `DUAL_WRITE_ENABLED=false`
2. Update backend to read from PostgreSQL
3. Monitor for 24-48 hours
4. Keep MongoDB as backup for fallback

## Failure Modes

### Lenient Mode (Recommended)
- If PostgreSQL write fails, MongoDB write succeeds
- Application continues functioning normally
- Inconsistency recorded in logs
- Manual reconciliation later

**When to Use:**
- Production environments (high availability)
- Large datasets (network can be unreliable)
- Non-critical operational data

### Strict Mode
- If either database write fails, entire operation fails
- Application returns error to client
- Transaction rolled back in both databases
- Ensures perfect consistency

**When to Use:**
- Development/testing environments
- Critical financial transactions
- Short migration windows

## Monitoring & Health Checks

### Real-Time Metrics
```
GET /api/migration/metrics
```

Response includes:
- Dual-write enabled status
- Success rate percentage
- MongoDB failures count
- PostgreSQL failures count
- Average write time
- Pending operations

### Consistency Health
```
GET /api/migration/health
```

Response indicates:
- MongoDB connection status
- PostgreSQL connection status
- Data consistency status
- Last consistency check timestamp
- Replication lag (if applicable)

## Rollback Procedures

### Level 1: Disable Dual-Write (30 seconds)
```bash
# Stop writing to PostgreSQL, use MongoDB only
export DUAL_WRITE_ENABLED=false
npm run dev
```

### Level 2: Clear PostgreSQL Data (5-10 minutes)
```bash
# If data is corrupted, truncate and restart dual-write
npm run db:truncate-postgres
npm run db:seed-from-mongo
```

### Level 3: Revert Code Changes (30 minutes)
```bash
# Roll back all Phase 6 changes
git reset --hard v1-before-migration
npm install
npm run dev
```

### Level 4: Restore from Backup (1-2 hours)
```bash
# Restore MongoDB from backup
mongorestore ./backup/mongodb/backup-timestamp/
mongod
npm run dev
```

### Level 5: Full Recovery (2-4 hours)
```bash
# Complete system restore
- Restore MongoDB from latest backup
- Rebuild PostgreSQL from scratch
- Restore application code from git
- Run full test suite
- Gradual production rollout
```

## Performance Considerations

### Write Latency
- Single DB write: ~5-10ms
- Dual-write (parallel): ~10-20ms
- Dual-write (sequential): ~15-30ms

**Optimization:**
```typescript
// Parallel writes (faster but less safe)
Promise.all([writeToMongo(), writeToPostgres()]);

// Sequential writes (slower but safer)
await writeToMongo();
await writeToPostgres();
```

### Connection Pooling
```env
# PostgreSQL
DATABASE_POOL_MIN=5
DATABASE_POOL_MAX=20

# MongoDB
MONGODB_POOL_SIZE=50
```

### Batch Operations
- Recommended batch size: 100-500 records
- Adjust based on memory and network
- Monitor CPU and memory during migration

## Data Validation

### Pre-Migration Checks
- Record count matching
- Field count matching
- Data type compatibility
- Null value handling
- Constraint compatibility

### Post-Migration Verification
- Checksum validation
- Row count verification
- Sample data comparison
- Index presence check
- Constraint verification

### Ongoing Consistency
- 5-minute automatic checks (configurable)
- Manual on-demand checks available
- Automatic alerting on mismatches
- Detailed reconciliation reports

## Audit Trail

### Write Operations Log
- Timestamp of each write
- Source (MongoDB/PostgreSQL)
- Operation type (create/update/delete)
- Success/failure status
- Error messages if failed

### Migration Progress Log
```json
{
  "timestamp": "2026-06-30T10:30:00Z",
  "event": "migration_started",
  "entity_type": "User",
  "total_records": 1000,
  "batch_size": 100
}
```

### Consistency Check Log
```json
{
  "timestamp": "2026-06-30T10:35:00Z",
  "check_type": "consistency_verification",
  "users_status": "consistent",
  "rides_status": "consistent",
  "inconsistencies_found": 0
}
```

## Testing

### Unit Tests
```bash
npm run test:dual-write
npm run test:consistency
npm run test:migration-tracker
```

### Integration Tests
```bash
npm run test:integration:dual-write
```

### Load Tests
```bash
npm run test:load:dual-write
npm run test:load:migration
```

### Rollback Tests
```bash
npm run test:rollback:level1
npm run test:rollback:level2
npm run test:rollback:level3
```

## Timeline

### Phase 6A: Setup (2-3 hours)
- Deploy dual-write middleware
- Deploy consistency checking
- Deploy migration tracking
- Configure monitoring

### Phase 6B: Initial Validation (1-2 hours)
- Enable dual-write on staging
- Run consistency checks
- Verify no data loss
- Monitor performance impact

### Phase 6C: Production Gradual Rollout (4-6 hours)
- Enable dual-write on production (read-only MongoDB)
- Monitor for 1 hour
- Start data migration batches
- Verify consistency
- Complete migration
- Run full validation

### Phase 6D: Stabilization (12-24 hours)
- Monitor dual-write metrics
- Watch for consistency issues
- Handle any edge cases
- Prepare for Phase 7

## Cost Analysis

### Storage (MongoDB + PostgreSQL)
- MongoDB: Current size
- PostgreSQL: Same size (during migration)
- Temporary 2x storage during Phase 6
- Back to normal after Phase 8

### Compute (Dual-Write Overhead)
- CPU: +5-10% during write operations
- Memory: +2-3% (buffers)
- Network: +50% (writes to both DBs)
- Mitigated by efficient indexing

### Time (Duration)
- Phase 6A Setup: 2-3 hours
- Phase 6B Validation: 1-2 hours
- Phase 6C Migration: 4-6 hours
- Phase 6D Stabilization: 12-24 hours
- **Total: 19-35 hours spread over 2-3 days**

## Troubleshooting

### Dual-Write Not Activating
```bash
# Check environment variable
echo $DUAL_WRITE_ENABLED

# Check application logs
tail -f logs/app.log | grep "dual-write"

# Verify Prisma connection
npm run prisma:studio
```

### Data Inconsistencies
```bash
# Get detailed inconsistency report
curl http://localhost:5000/api/migration/inconsistencies

# Identify specific records
curl http://localhost:5000/api/migration/inconsistencies?entity=User&id=xyz

# Fix specific record (manual reconciliation)
# Compare values and decide source of truth
```

### Performance Degradation
```bash
# Check write operation latency
curl http://localhost:5000/api/migration/latency

# Review connection pool status
npm run prisma:inspect

# Optimize indexes
npm run db:optimize-indexes
```

### Rollback Issues
```bash
# Check database status
curl http://localhost:5000/api/migration/health

# Verify data integrity
npm run db:validate-integrity

# If issues persist, fall back to Level 5
git reset --hard v1-before-migration
```

## Success Metrics

### Phase 6 is successful when:

- [ ] Dual-write enabled without errors
- [ ] 100% write success rate (lenient mode: >99%)
- [ ] Consistency checks pass (User & Ride)
- [ ] Zero data loss in PostgreSQL
- [ ] Performance impact <20%
- [ ] Rollback tested and working
- [ ] Audit logs complete and verified
- [ ] Team trained on procedures
- [ ] Documentation updated
- [ ] Ready for Phase 7

## Next Steps

After Phase 6 is complete:
1. Phase 7: Testing & QA (8-10 hours)
2. Phase 8: Production Cutover (2-4 hours)

Total remaining time: ~3-4 hours after Phase 6 completion.

---

**Phase 6 Status**: READY FOR IMPLEMENTATION
**Estimated Duration**: 19-35 hours
**Target Completion**: Day 2-3 of migration
**Backup Status**: Protected at v1-before-migration tag

