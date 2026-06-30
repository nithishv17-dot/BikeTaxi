# Phase 8: Production Cutover - Final Phase

## Overview

Phase 8 is the final migration phase, switching BikeTaxi from MongoDB as the primary database to PostgreSQL with gradual traffic switching and continuous monitoring. This is a controlled, reversible process with fallback at every step.

## Timeline & Milestones

```
Total Duration: 2-4 hours
Go-Live Window: During low-traffic hours (2 AM - 6 AM recommended)

T+0:00    Cutover begins, validation starts
T+0:30    PostgreSQL becomes primary (read-write)
T+1:00    Traffic switched to 10% PostgreSQL
T+1:30    Traffic switched to 50% PostgreSQL
T+2:00    Traffic switched to 100% PostgreSQL
T+2:30    Disable dual-write mode
T+3:00    Migrate remaining data
T+3:30    Archive MongoDB as backup
T+4:00    Post-cutover validation complete
```

## Pre-Cutover Checklist (30 minutes before)

### Environment Verification

```bash
# Check all services running
curl http://localhost:5000/api/health
curl http://localhost:3000/api/health

# Verify databases connected
echo "MongoDB: Connected" && mongosh --eval "db.adminCommand('ping')"
echo "PostgreSQL: Connected" && psql -c "SELECT version()"

# Verify dual-write enabled
curl http://localhost:5000/api/migration/status

# Check backup readiness
ls -lah backup/mongodb/latest/
ls -lah backup/postgresql/latest/

# Verify rollback tags exist
git tag | grep "v1-before-migration"
git branch | grep "backup/prototype"
```

Expected output:
```
✓ All services: Running
✓ MongoDB: Connected
✓ PostgreSQL: Connected
✓ Dual-write: Enabled
✓ Backups: Ready
✓ Rollback tags: Available
```

### Data Consistency Check

```bash
# Final consistency check before cutover
curl -X POST http://localhost:5000/api/migration/consistency/verify

# Check for pending migrations
curl http://localhost:5000/api/migration/progress

# Verify no orphaned records
curl http://localhost:5000/api/migration/inconsistencies
```

Expected:
```json
{
  "users": {
    "mongoTotal": 2543,
    "postgresTotal": 2543,
    "matching": 2543,
    "inconsistencies": 0
  },
  "rides": {
    "mongoTotal": 15420,
    "postgresTotal": 15420,
    "matching": 15420,
    "inconsistencies": 0
  },
  "status": "FULLY_CONSISTENT"
}
```

### Team Readiness

- [ ] Team lead verified and present
- [ ] On-call engineer ready to respond
- [ ] Database administrator available
- [ ] Network team standing by
- [ ] Communication channel open (Slack, video conference)
- [ ] Incident command center activated

### Traffic Patterns

```
Check typical traffic patterns:
- Current concurrent users: < 50 (recommendation: cutover during low traffic)
- Current requests/sec: < 10
- Peak traffic window: 6 PM - 11 PM
- Recommended cutover: 2 AM - 6 AM

If current traffic > 100 users: WAIT for lower traffic window
```

## Phase 8 Execution

### Step 1: Final Validation (30 minutes)

**1.1 Backend Readiness**

```bash
cd /vercel/share/v0-project/backend

# Run final validation tests
npm run test:unit
npm run test:integration

# Check TypeScript compilation
npm run build:ts

# Verify API starts cleanly
npm start &
sleep 5
curl http://localhost:5000/api/health
kill %1
```

Expected: All tests passing, API starts without errors

**1.2 Database Readiness**

```bash
# Check PostgreSQL schema
psql -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"

# Expected: 12 tables (users, rides, ratings, etc.)

# Check MongoDB data count
mongosh --eval "db.users.countDocuments(); db.rides.countDocuments();"

# Expected: Matching counts with PostgreSQL
```

**1.3 Frontend Readiness**

```bash
cd /vercel/share/v0-project/frontend/react_app

# Build frontend
npm run build

# Check build output
ls -lah .next/
```

Expected: Build completes without errors

### Step 2: Switch to PostgreSQL Primary (1 hour)

**2.1 Update Backend Configuration**

```bash
# Update .env.production
export DATABASE_TYPE=postgres
export MONGODB_MODE=backup-only
export POSTGRES_MODE=primary
export DUAL_WRITE_ENABLED=true  # Keep on for safety
```

**2.2 Restart Backend Services**

```bash
# Stop current backend
pm2 stop biketaxi-backend

# Clear any connections
sleep 5

# Start backend with PostgreSQL primary
export DATABASE_TYPE=postgres
npm start

# Verify startup
sleep 10
curl http://localhost:5000/api/health
```

Expected response:
```json
{
  "status": "ok",
  "database": "postgres",
  "mode": "dual-write",
  "timestamp": "2026-06-30T06:00:00Z"
}
```

**2.3 Validate Reads from PostgreSQL**

```bash
# Test reading users
curl http://localhost:5000/api/users/count

# Test reading rides
curl http://localhost:5000/api/rides/recent

# Verify response times
time curl http://localhost:5000/api/users/list

# Expected latency: 5-20ms
```

### Step 3: Gradual Traffic Switching

**3.1 Stage 1: 10% Traffic to PostgreSQL (30 minutes)**

```bash
# Update load balancer or API gateway config
export POSTGRES_TRAFFIC_PERCENT=10
export MONGODB_TRAFFIC_PERCENT=90

# Restart services
pm2 restart biketaxi-backend

# Monitor metrics
for i in {1..30}; do
  echo "Minute $i:"
  curl http://localhost:5000/api/migration/metrics
  sleep 60
done
```

Monitor for:
- Increased error rates? NO
- Performance degradation? NO
- Consistency issues? NO
- If any YES: ROLLBACK to Step 1

**3.2 Stage 2: 50% Traffic to PostgreSQL (30 minutes)**

```bash
export POSTGRES_TRAFFIC_PERCENT=50
export MONGODB_TRAFFIC_PERCENT=50

pm2 restart biketaxi-backend

# Monitor for 30 minutes
for i in {1..30}; do
  curl http://localhost:5000/api/migration/metrics
  sleep 60
done
```

Continue monitoring. If all metrics good: proceed to Stage 3

**3.3 Stage 3: 100% Traffic to PostgreSQL (30 minutes)**

```bash
export POSTGRES_TRAFFIC_PERCENT=100
export MONGODB_TRAFFIC_PERCENT=0

pm2 restart biketaxi-backend

# Monitor for 30 minutes
for i in {1..30}; do
  curl http://localhost:5000/api/migration/metrics
  sleep 60
done
```

### Step 4: Disable Dual-Write (30 minutes)

After 1-2 hours at 100% PostgreSQL with no issues:

```bash
# Disable dual-write mode
export DUAL_WRITE_ENABLED=false
export MONGODB_MODE=backup-only

# Restart services
pm2 restart biketaxi-backend

# Verify mongoDB not being written to
curl http://localhost:5000/api/migration/metrics

# Expected: All writes going to PostgreSQL only
```

### Step 5: Archive MongoDB (1 hour)

```bash
# Create final backup of MongoDB
mongodump --out ./backup/mongodb/final-$(date +%Y%m%d-%H%M%S)

# Archive to S3 or long-term storage
aws s3 sync ./backup/mongodb/final-* s3://biketaxi-backups/

# Keep MongoDB running as reference backup for 24-48 hours
# Do NOT delete yet
```

### Step 6: Post-Cutover Validation (1 hour)

**6.1 Data Integrity Check**

```bash
# Verify all data is in PostgreSQL
curl http://localhost:5000/api/migration/summary

# Check for any missing records
curl http://localhost:5000/api/migration/validation/complete

# Verify consistency
curl http://localhost:5000/api/migration/consistency/final
```

**6.2 Performance Verification**

```bash
# Run performance test
npm run test:performance

# Expected:
# - Write latency: 8-15ms (improved from dual-write)
# - Read latency: 5-10ms
# - Throughput: > 900 writes/sec
# - p99 latency: < 150ms
```

**6.3 Application Functionality**

```bash
# Test critical flows
curl -X POST http://localhost:5000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","phone":"9999999999","password":"Test@123"}'

# Expected: 201 Created

curl http://localhost:5000/api/rides/available \
  -H "Authorization: Bearer $TOKEN"

# Expected: 200 OK with rides list
```

## Monitoring During Cutover

### Real-Time Dashboards

```
Create dashboard showing:
- Write latency (p50, p95, p99)
- Read latency (p50, p95, p99)
- Error rate (target: < 0.5%)
- Database connections (active/max)
- CPU usage
- Memory usage
- Requests per second
```

### Alert Thresholds

```
CRITICAL (Immediate Action):
- Error rate > 5%
- p99 latency > 500ms
- Database connections exhausted
- Memory > 90%
- CPU > 95%

WARNING (Monitor):
- Error rate > 2%
- p99 latency > 300ms
- Database connections > 80%
- Memory > 75%
- CPU > 80%
```

### Rollback Triggers

Automatically rollback if ANY of these occur:
- Critical alert for > 5 minutes
- 100+ errors in 1 minute
- Complete database outage
- All connections exhausted
- Data corruption detected

## Rollback Procedures

### Immediate Rollback (< 5 minutes)

```bash
# Step 1: Disable PostgreSQL writes
export POSTGRES_MODE=backup-only
export MONGODB_MODE=primary
export DUAL_WRITE_ENABLED=true

# Step 2: Restart backend
pm2 restart biketaxi-backend

# Step 3: Verify MongoDB receives writes
curl http://localhost:5000/api/migration/metrics

# Step 4: Check application health
curl http://localhost:5000/api/health
```

### Extended Rollback (5-30 minutes)

If immediate rollback doesn't work:

```bash
# Clear all connections
pm2 delete biketaxi-backend

# Reset environment
unset DATABASE_TYPE
unset POSTGRES_MODE
unset MONGODB_MODE

# Start with MongoDB-only
npm start

# Verify
curl http://localhost:5000/api/health
```

### Full Rollback (30+ minutes)

If extended rollback doesn't work:

```bash
# Revert all Phase 8 changes
git checkout main -- backend/src/config/database.ts

# Git reset if needed
git reset --hard v1-before-migration

# Reinstall dependencies
npm install --legacy-peer-deps

# Restart MongoDB
mongod

# Start backend
npm start
```

## Post-Cutover Tasks (Next 24-48 hours)

### Hour 1: Continuous Monitoring

```
- Monitor all metrics
- Watch for errors
- Check user complaints
- Verify consistency
- No issues: Continue
- Issues found: Rollback
```

### Hours 2-4: Verification

```
- Run full test suite
- Verify data integrity
- Check performance
- Monitor user flows
- Confirm success
```

### Hours 4-24: Stabilization

```
- Continue monitoring
- Archive old backups
- Document changes
- Update runbooks
- Team debriefing
```

### Hours 24-48: Cleanup

```
- Keep MongoDB as backup (do NOT delete yet)
- Monitor for any delayed issues
- Generate migration report
- Update documentation
- Plan MongoDB decommission (later)
```

## Success Criteria

Migration is successful when:

- [✓] All data migrated to PostgreSQL
- [✓] No data loss verified
- [✓] 100% traffic on PostgreSQL
- [✓] Dual-write disabled
- [✓] Performance improved or equal
- [✓] Error rate < 0.5%
- [✓] All functionality working
- [✓] User reports positive
- [✓] Monitoring shows stability
- [✓] 24 hours without issues

## Failure Scenarios & Actions

### Scenario 1: Slow Reads from PostgreSQL

Symptoms: p99 latency > 300ms

Actions:
1. Check query plan with EXPLAIN
2. Verify index usage
3. Check query optimization
4. Rollback if > 30 seconds

### Scenario 2: Write Failures

Symptoms: 5%+ error rate

Actions:
1. Check PostgreSQL logs
2. Verify connections available
3. Check disk space
4. Rollback immediately

### Scenario 3: Data Inconsistency

Symptoms: Mismatched records between MongoDB and PostgreSQL

Actions:
1. Pause traffic (100% MongoDB)
2. Investigate root cause
3. Resync data if possible
4. Rollback if can't fix

### Scenario 4: Authentication Issues

Symptoms: Users cannot login after cutover

Actions:
1. Verify user table migrated
2. Check password hashing
3. Verify JWT secret
4. Rollback if persists

### Scenario 5: Connection Pool Exhaustion

Symptoms: "Too many connections" errors

Actions:
1. Increase pool max size
2. Kill idle connections
3. Restart backend service
4. Rollback if doesn't resolve

## Communication Plan

### Pre-Cutover (1 day before)

```
Channel: #engineering-announcements
Message:
"We're migrating database infrastructure this Tuesday 2-6 AM.
Expected downtime: None (zero-downtime migration)
Users: No action needed
Team: On-call engineer will monitor"
```

### During Cutover

```
Channel: #biketaxi-incident (every 30 minutes)
Status updates:
T+0:30 - PostgreSQL primary activated
T+1:00 - 10% traffic switched
T+1:30 - 50% traffic switched
T+2:00 - 100% traffic switched
T+2:30 - Dual-write disabled
```

### Post-Cutover (Next 24 hours)

```
Channel: #engineering-announcements
Message:
"Database migration complete! Successfully migrated MongoDB → PostgreSQL.
No data loss, improved performance, zero downtime.
Thank you for your patience!"
```

## Knowledge Transfer

### Team Training Topics

- New PostgreSQL database schema
- Query patterns for PostgreSQL
- Monitoring and alerting
- Troubleshooting common issues
- Rollback procedures
- Backup and restore procedures

### Documentation Updates

- Update runbooks with PostgreSQL procedures
- Update architecture diagrams
- Update configuration guides
- Update troubleshooting guides
- Archive Phase 1-7 documentation

### Handoff Checklist

- [ ] Team understands PostgreSQL setup
- [ ] Team knows how to query data
- [ ] Team knows monitoring procedures
- [ ] Team knows rollback procedures
- [ ] Team knows on-call rotation
- [ ] Runbooks updated and accessible

## Final Checklist

### Before Starting

- [ ] All Phase 7 tests passing
- [ ] Backups verified
- [ ] Rollback procedures tested
- [ ] Team assembled and ready
- [ ] Communication channels open
- [ ] Monitoring dashboards ready
- [ ] Alert thresholds configured

### During Cutover

- [ ] T+0:00: Cutover started, monitoring active
- [ ] T+0:30: PostgreSQL primary, validation passed
- [ ] T+1:00: 10% traffic switched, metrics normal
- [ ] T+1:30: 50% traffic switched, metrics normal
- [ ] T+2:00: 100% traffic switched, metrics normal
- [ ] T+2:30: Dual-write disabled, backup-only mode
- [ ] T+3:00: All data migrated, consistency verified
- [ ] T+4:00: Post-cutover validation complete

### After Cutover

- [ ] 24-hour monitoring complete, no issues
- [ ] All functionality verified
- [ ] Performance metrics confirmed
- [ ] User feedback positive
- [ ] Team debriefing completed
- [ ] Documentation updated
- [ ] Lessons learned documented

## Estimated Duration

- Pre-cutover validation: 30 minutes
- PostgreSQL primary switch: 1 hour
- Traffic switching (gradual): 1.5 hours
- Post-cutover validation: 1.5 hours
- **Total: 4-4.5 hours**

## Risk Mitigation

### Risk: Data Loss
- Mitigation: MongoDB backup + consistency checks
- Rollback: Available (Level 4-5)

### Risk: Performance Degradation
- Mitigation: Load testing completed, gradual switching
- Rollback: Available (immediate)

### Risk: User Impact
- Mitigation: Zero-downtime design, gradual traffic shift
- Rollback: Available at any time

### Risk: Connection Exhaustion
- Mitigation: Pool sizing optimized, connection limits set
- Rollback: Available (increase pool, restart)

### Risk: Data Corruption
- Mitigation: Consistency checks, transaction safety
- Rollback: Available (Level 4-5)

---

**Phase 8 Status**: READY FOR PRODUCTION
**Estimated Duration**: 4 hours
**Go/No-Go Decision Authority**: Tech Lead + Product Owner
**Cutover Window**: 2 AM - 6 AM (low traffic recommended)

