# BikeTaxi Migration - Emergency Rollback Procedures

## Quick Reference

**If something breaks**: Follow the procedures below in order of preference.

---

## Level 1: Code Rollback (Fastest)

### When to Use
- TypeScript backend compile errors
- React frontend build errors
- Socket.io connectivity issues
- New code hasn't been deployed

### Procedure

```bash
# 1. Local rollback
cd /vercel/share/v0-project
git reset --hard v1-before-migration
git status

# 2. Verify everything compiles
npm run build  # or yarn build

# 3. If needed, go back to backup branch
git checkout backup/prototype
git status

# 4. Optional: Purge new directories
rm -rf backend/typescript
rm -rf frontend/react_app
rm -rf database/postgres

# 5. Verify original project still works
cd backend && npm start &
cd frontend/bike_taxi_app && flutter run -d chrome &
```

**Time to Recovery**: 2-5 minutes

---

## Level 2: Git Branch Rollback (Safe & Reversible)

### When to Use
- New backend partially migrated
- Frontend has issues
- Need to preserve migration work for later

### Procedure

```bash
# 1. Create safety checkpoint
git tag pre-rollback-attempt-$(date +%Y%m%d-%H%M%S)

# 2. Switch to backup
git checkout backup/prototype

# 3. Force push to main (if needed)
git push origin backup/prototype:main --force

# 4. Update all deployed services
# Vercel (Frontend)
vercel deploy --prod

# Render (Backend)
# Re-deploy from backup branch

# 5. Verification
curl https://dottaxi.vercel.app  # Should show Flutter version
curl https://biketaxi.onrender.com/api/users/login  # Should work
```

**Time to Recovery**: 10-15 minutes

---

## Level 3: Database Rollback

### When to Use
- PostgreSQL migration corrupted data
- MongoDB data was accidentally modified
- Need to restore from backup

### Procedure

#### MongoDB Restoration

```bash
# 1. List available backups
ls -la database/mongodb/backups/

# 2. Stop all services
pm2 stop backend

# 3. Restore from most recent backup
mongorestore --drop ./database/mongodb/backups/backup-20260630-120000/

# 4. Verify restore
mongo --eval "db.users.countDocuments()"

# 5. Restart services
pm2 start backend

# 6. Health check
curl https://biketaxi.onrender.com/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"test","password":"test"}'
```

#### PostgreSQL Issue (Stop and Revert)

```bash
# 1. If migration failed midway
psql $DATABASE_URL -c "DROP SCHEMA public CASCADE;"
psql $DATABASE_URL -c "CREATE SCHEMA public;"

# 2. Or: Restore PostgreSQL backup (if you have one)
psql $DATABASE_URL < database/postgres/backups/backup-20260630.sql

# 3. Re-run original MongoDB backend
cd backend
npm start
```

**Time to Recovery**: 15-30 minutes

---

## Level 4: Full Infrastructure Rollback

### When to Use
- Catastrophic failure
- All services are down
- Need to completely restore to pre-migration state

### Procedure

```bash
# Step 1: Verify backup integrity
echo "Checking backup tag exists..."
git tag | grep v1-before-migration

# Step 2: Reset local repo
cd /vercel/share/v0-project
git fetch origin
git reset --hard origin/backup/prototype

# Step 3: Restore MongoDB
mongorestore --drop ./database/mongodb/backups/backup-20260630-120000/ &

# Step 4: Re-deploy frontend (Vercel)
cd frontend/bike_taxi_app
vercel deploy --prod

# Step 5: Re-deploy backend (Render)
git push origin backup/prototype:main --force
# Render will auto-redeploy from main branch

# Step 6: Verify all services
echo "Waiting 5 minutes for services to come online..."
sleep 300

# Health checks
./scripts/health-check.sh
```

**Time to Recovery**: 30-45 minutes (mostly waiting for redeploy)

---

## Level 5: Data Corruption - Selective Recovery

### When to Use
- Only certain tables are corrupted
- Need to recover specific data (e.g., rides table)
- Rest of system is fine

### Procedure

#### MongoDB Selective Restore
```bash
# 1. Restore only rides collection
mongorestore --nsInclude="biketaxi.rides" \
  ./database/mongodb/backups/backup-20260630-120000/

# 2. Verify data
mongo --eval "db.rides.find().limit(1).pretty()"

# 3. Check consistency
mongo --eval "db.rides.aggregate([{\$count: 'total'}])"
```

#### PostgreSQL Selective Restore
```bash
# 1. Export just the users table
pg_dump $DATABASE_URL --table=users > /tmp/users.sql

# 2. Restore
psql $DATABASE_URL < /tmp/users.sql

# 3. Or: Restore from backup
pg_restore $DATABASE_URL < database/postgres/backups/backup-20260630.sql \
  --table=users
```

**Time to Recovery**: 10-20 minutes

---

## Pre-Rollback Checklist

### Always Do This First

- [ ] Take a screenshot of the error
- [ ] Check git status: `git status`
- [ ] Check git log: `git log --oneline | head -5`
- [ ] Verify backup exists: `git tag | grep v1-before-migration`
- [ ] Backup current state: `git tag pre-incident-$(date +%s)`
- [ ] Check disk space: `df -h`
- [ ] Check database connection: `mongosh --eval "db.adminCommand('ping')"`
- [ ] Stop affected services: `pm2 stop backend` or `pm2 stop all`
- [ ] Record current time and symptoms
- [ ] Notify team (if applicable)

---

## Health Check After Rollback

```bash
#!/bin/bash
# scripts/health-check.sh

echo "=== Health Check ==="

# Check Git
echo "1. Git status:"
git log --oneline | head -1

# Check Backend
echo "2. Backend API:"
curl -s https://biketaxi.onrender.com/api/health || echo "❌ Backend down"

# Check Frontend
echo "3. Frontend:"
curl -s https://dottaxi.vercel.app | grep -q "flutter" && echo "✅ Flutter app" || echo "❌ Frontend issue"

# Check Database
echo "4. MongoDB:"
mongosh --eval "db.adminCommand('ping')" 2>/dev/null && echo "✅ MongoDB connected" || echo "❌ MongoDB issue"

# Check Collections
echo "5. Data:"
mongosh --eval "db.users.countDocuments()" 2>/dev/null
mongosh --eval "db.rides.countDocuments()" 2>/dev/null

echo "=== Health Check Complete ==="
```

---

## Communication Template

### If Rollback is Needed

```
INCIDENT: BikeTaxi Migration Rollback

Status: Rolling back to v1-before-migration
Duration: Expected 30-45 minutes

Affected Services:
- Frontend (briefly)
- Backend API (briefly)  
- Real-time features (briefly)

Timeline:
- T+0: Rollback initiated
- T+5: Code reset complete
- T+10: Services restarting
- T+15: Database restored
- T+30: Full validation
- T+45: Service restored

Users May Experience:
- 10-15 minute service interruption
- Possible loss of in-progress rides (will be recovered from backup)

Recovery: [Describe what happened and what's fixed]
```

---

## Data Recovery Specifics

### MongoDB Collections to Monitor

```javascript
// Check collection sizes
db.users.countDocuments()      // Should be > 0
db.rides.countDocuments()      // Should be > 0
db.adminCommand('listCollections')  // Should show all collections
```

### PostgreSQL Recovery Verification

```sql
-- Verify tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public';

-- Check record counts
SELECT 'users' as table_name, COUNT(*) as count FROM users
UNION ALL
SELECT 'rides', COUNT(*) FROM rides
UNION ALL
SELECT 'offers', COUNT(*) FROM offers;

-- Verify foreign keys
SELECT constraint_name FROM information_schema.table_constraints 
WHERE constraint_type = 'FOREIGN KEY';
```

---

## Post-Rollback Analysis

### After Recovery, Document:

1. **What failed?**
   - Specific error message
   - File/line number
   - Conditions that triggered it

2. **Why did it fail?**
   - Was it tested?
   - Was it a dependency issue?
   - Was it a data migration issue?

3. **How to prevent?**
   - Add test coverage
   - Add validation
   - Add integration test

4. **Create Issue**: Document in GitHub for next attempt

---

## Important Contacts & Resources

- **Git Backup Tag**: `git tag | grep v1-before-migration`
- **Backup Branch**: `backup/prototype`
- **MongoDB Backup Location**: `database/mongodb/backups/`
- **PostgreSQL Backup Location**: `database/postgres/backups/`
- **Deployment**: Vercel + Render dashboards
- **Database**: MongoDB Atlas + PostgreSQL managed service

---

## Quick Commands Reference

```bash
# Show current state
git status
git log --oneline | head -3

# Go to backup
git checkout backup/prototype

# Go to specific tag
git checkout v1-before-migration

# List all backups
ls -la database/mongodb/backups/

# Check database
mongosh --eval "db.adminCommand('ping')"
psql $DATABASE_URL -c "SELECT 1;"

# Restart services
pm2 restart all
pm2 status

# View logs
pm2 logs backend
pm2 logs backend --tail 100
```

---

## When Everything Fails

### Nuclear Option (Last Resort)

**Only if absolutely nothing else works:**

```bash
# 1. Delete all migration work
rm -rf backend/typescript frontend/react_app database/postgres

# 2. Reset to clean state
git checkout backup/prototype
git reset --hard v1-before-migration
git clean -fd

# 3. Verify original project
ls -la backend/  # Should only show original files
ls -la frontend/ # Should only show Flutter app

# 4. Start fresh
cd backend && npm install && npm start &
cd frontend/bike_taxi_app && flutter run -d chrome &

# 5. Notify team
echo "Nuclear rollback complete. Migration data preserved in git history."
```

**Expected Result**: Application runs exactly as before migration started.

---

## Testing Rollback (Recommended)

### Do This Before Starting Phase 3

```bash
# 1. Tag current state
git tag test-rollback-point

# 2. Create dummy files
mkdir -p backend/typescript frontend/react_app
echo "test" > backend/typescript/test.ts
echo "test" > frontend/react_app/test.tsx

# 3. Commit
git add .
git commit -m "Test migration structure"

# 4. Now rollback
git reset --hard v1-before-migration

# 5. Verify everything is cleaned up
ls backend/typescript  # Should not exist or be empty
git status  # Should be clean

# 6. Verify app still runs
npm test  # If available
```

---

**Version**: 1.0  
**Last Updated**: 2026-06-30  
**Status**: Phase 2 - Ready for review
