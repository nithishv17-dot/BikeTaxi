# BikeTaxi Migration - Commands Reference

Quick reference for common commands during migration.

## Backup & Safety

### Verify Backup
```bash
# Check backup branch exists
git branch -v | grep backup

# Check backup tag exists
git tag | grep v1-before-migration

# See what's in backup
git show v1-before-migration:backend/server.js | head -10
```

### Create Emergency Checkpoint
```bash
git tag emergency-$(date +%Y%m%d-%H%M%S)
```

## Git Workflow

### Current Status
```bash
# See current branch
git branch

# See current state
git status

# See recent commits
git log --oneline | head -10

# See what changed
git diff
```

### Switch Branches
```bash
# Go to backup
git checkout backup/prototype

# Go to main
git checkout main

# Go to development
git checkout v0/project-analysis-b16c254b
```

### Go Back to Backup (Emergency)
```bash
# Soft reset (keeps changes)
git reset --soft v1-before-migration

# Hard reset (loses changes)
git reset --hard v1-before-migration

# Force push to main (careful!)
git push origin v1-before-migration:main --force
```

## Project Structure

### See Project Layout
```bash
# Root
ls -la

# Backend
ls -la backend/

# Frontend
ls -la frontend/

# Database
ls -la database/ 2>/dev/null || echo "database/ not yet created"
```

### Find Files
```bash
# Find all MongoDB models
find backend -name "*Model*" -o -name "*model*"

# Find all API routes
find backend/routes -name "*.js"

# Find Flutter source
find frontend/bike_taxi_app/lib -name "*.dart"
```

## Database Operations

### MongoDB Backup
```bash
# Create backup
mongodump --out ./database/mongodb/backup/backup-$(date +%Y%m%d-%H%M%S)/

# Export collections
mongoexport --collection users --out ./database/mongodb/backups/users.json
mongoexport --collection rides --out ./database/mongodb/backups/rides.json

# Restore from backup
mongorestore ./database/mongodb/backup/backup-20260630-120000/
```

### Check MongoDB
```bash
# Connect to MongoDB
mongosh

# In mongosh:
db.adminCommand('ping')
db.users.countDocuments()
db.rides.countDocuments()
```

## Service Management

### Check if Services Running
```bash
# List processes
ps aux | grep node
ps aux | grep flutter

# Check ports
lsof -i :5000      # Backend
lsof -i :3000      # Frontend dev server
```

### Start Services
```bash
# Backend (JavaScript)
cd backend
npm start

# Frontend (Flutter)
cd frontend/bike_taxi_app
flutter run -d chrome
```

### Stop Services
```bash
# Kill by port
lsof -i :5000 -t | xargs kill -9

# Or use pm2
pm2 stop backend
pm2 stop all
pm2 kill
```

## Deployment

### Vercel (Frontend)
```bash
# Deploy frontend
vercel deploy

# Deploy to production
vercel deploy --prod

# Check status
vercel status
```

### Render (Backend)
```bash
# Deploy from main branch
git push origin main

# Render auto-deploys from main
# Check status at https://dashboard.render.com
```

## Documentation

### Read Key Documents
```bash
# Migration plan
cat MIGRATION_PLAN.md | less

# Rollback procedures
cat ROLLBACK_PROCEDURES.md | less

# Schema mapping
cat docs/SCHEMA_MAPPING.md | less

# This phase summary
cat PHASE_2_SUMMARY.md | less
```

### View Specific Sections
```bash
# Get line count
wc -l MIGRATION_PLAN.md

# See structure
grep "^##" MIGRATION_PLAN.md

# Find section
grep -n "Phase 3" MIGRATION_PLAN.md | head -5
```

## Health Checks

### API Health
```bash
# Test login endpoint
curl -X POST https://biketaxi.onrender.com/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"test","password":"test"}'

# Test rides endpoint
curl https://biketaxi.onrender.com/api/rides

# Test frontend
curl https://dottaxi.vercel.app
```

### Database Health
```bash
# MongoDB ping
mongosh --eval "db.adminCommand('ping')"

# MongoDB stats
mongosh --eval "db.stats()"

# Check collections
mongosh --eval "db.getCollectionNames()"
```

## Development Workflow

### Create Feature Branch
```bash
git checkout -b feature/typescript-backend
# or
git checkout -b feature/react-frontend
```

### Commit Work
```bash
git add .
git commit -m "Feature: description"

# Or specific files
git add backend/typescript/
git commit -m "Phase 4: TypeScript backend - part 1"
```

### View Commit History
```bash
# Recent commits
git log --oneline | head -10

# Commits on backup branch
git log backup/prototype --oneline | head -10

# Diff between branches
git diff main backup/prototype
```

## Cleanup & Maintenance

### Remove New Directories (Rollback)
```bash
# Remove TypeScript backend
rm -rf backend/typescript

# Remove React frontend
rm -rf frontend/react_app

# Remove PostgreSQL files
rm -rf database/postgres
```

### Clean Git
```bash
# Remove untracked files
git clean -fd

# Prune branches
git remote prune origin

# Remove old backups (careful!)
rm -rf database/mongodb/backup/backup-old-*
```

## Troubleshooting

### If Git is Broken
```bash
# Show current state
git log --oneline | head -1
git status

# Reset to backup
git reset --hard v1-before-migration

# Verify it worked
git log --oneline | head -1
git status
```

### If Installation Fails
```bash
# Clear node_modules
rm -rf node_modules
rm -rf package-lock.json
npm install

# Or with yarn
yarn install
```

### If Database Connection Fails
```bash
# Check MongoDB running
mongosh --eval "db.adminCommand('ping')"

# Check connection string
grep MONGODB_URI .env.development.local
env | grep MONGO

# Test direct connection
mongosh "mongodb://127.0.0.1:27017/biketaxi"
```

## Git Configuration

### Set User (if needed)
```bash
git config user.email "your@email.com"
git config user.name "Your Name"

# Or globally
git config --global user.email "your@email.com"
git config --global user.name "Your Name"
```

### Check Configuration
```bash
git config --list | grep user
```

## Quick Rollback

### Step 1: Verify Backup
```bash
git log --oneline | head -1  # Note the commit
git tag | grep v1-before-migration
```

### Step 2: Reset
```bash
git reset --hard v1-before-migration
```

### Step 3: Verify
```bash
git status      # Should be clean
ls -la backend  # Should only show original files
```

### Step 4: Clean Up
```bash
rm -rf backend/typescript frontend/react_app database/postgres
git clean -fd
```

### Step 5: Restart Services
```bash
cd backend && npm start &
cd frontend/bike_taxi_app && flutter run -d chrome &
```

## Useful Aliases

### Add to .bashrc or .zshrc
```bash
# Git shortcuts
alias gb='git branch'
alias gs='git status'
alias glog='git log --oneline'
alias gd='git diff'
alias gr='git reset --hard'

# Project shortcuts
alias backend='cd backend'
alias frontend='cd frontend/bike_taxi_app'

# Backup shortcuts
alias backup-check='git tag | grep v1-before-migration && echo "✅ Backup OK"'
alias go-backup='git checkout backup/prototype'
alias go-main='git checkout main'
```

## Emergency Commands

### If Everything is Broken
```bash
# 1. Save current state
git tag emergency-$(date +%s)

# 2. Go to backup
git checkout backup/prototype

# 3. Reset completely
git reset --hard v1-before-migration

# 4. Clean up
git clean -fd
rm -rf node_modules database/postgres backend/typescript frontend/react_app

# 5. Verify
git status
git log --oneline | head -1

# Result: You're back to pre-migration state
```

### If You Can't Remember Commands
```bash
# See this reference
cat COMMANDS_REFERENCE.md

# Or
less COMMANDS_REFERENCE.md
```

---

**Version**: 1.0  
**Last Updated**: 2026-06-30  
**Purpose**: Quick reference during migration  
**Fallback**: When in doubt, `git reset --hard v1-before-migration`
