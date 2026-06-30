# BikeTaxi Deployment Guide

## Deployment Architecture

```
Frontend: Vercel (React)
Backend: Render (Node.js/Express)
Database: PostgreSQL (Neon/Supabase recommended)
```

## Backend Deployment on Render

### Step 1: Create Render Account
1. Go to https://render.com
2. Sign up with GitHub
3. Create a new Web Service

### Step 2: Configure Backend for Render
```
Service: Web Service
Runtime: Node
Build Command: npm install && npm run build:ts
Start Command: npm run start:ts
```

### Step 3: Environment Variables on Render
```
DATABASE_TYPE=postgres
DATABASE_URL=<your-postgres-connection-string>
NODE_ENV=production
PORT=10000
POSTGRES_MODE=primary
MONGODB_MODE=backup-only
DUAL_WRITE_ENABLED=false
LOG_LEVEL=info
```

### Step 4: Deploy Backend
```bash
git push origin v0/project-analysis-b16c254b
# Render will auto-deploy on push
```

## Frontend Deployment on Vercel

### Step 1: Create Vercel Account
1. Go to https://vercel.com
2. Sign up with GitHub
3. Import project

### Step 2: Configure Frontend for Vercel
```
Framework: Next.js
Build Command: npm run build
Start Command: npm run start
Root Directory: frontend/react_app
```

### Step 3: Environment Variables on Vercel
```
NEXT_PUBLIC_API_URL=https://biketaxi-api.render.com
NEXT_PUBLIC_APP_NAME=BikeTaxi
NEXT_PUBLIC_ENVIRONMENT=production
```

### Step 4: Deploy Frontend
```bash
# Vercel auto-deploys on push
```

## Database Setup

### Option A: Neon (Recommended)
1. Go to https://neon.tech
2. Create PostgreSQL database
3. Get connection string
4. Add to Render environment variables

### Option B: Supabase
1. Go to https://supabase.com
2. Create PostgreSQL project
3. Get connection string
4. Add to Render environment variables

## Verification Checklist

Backend (Render):
- [ ] Service created on Render
- [ ] GitHub connected
- [ ] Environment variables set
- [ ] Build logs show success
- [ ] Health endpoint responds

Frontend (Vercel):
- [ ] Project imported
- [ ] Environment variables set
- [ ] Build logs show success
- [ ] Application loads
- [ ] API calls work

Database:
- [ ] PostgreSQL created
- [ ] Connection string obtained
- [ ] Schema migrated
- [ ] Data accessible

## Deployment URLs

After deployment, you'll have:
- Backend API: https://biketaxi-api.render.com
- Frontend App: https://biketaxi.vercel.app
