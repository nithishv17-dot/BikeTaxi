# OPTION A: Deploy to NEW Services

## Overview

Deploy BikeTaxi to brand new services while keeping your old project running.

```
OLD PROJECT (Stays Live)          NEW PROJECT (BikeTaxi)
├── Render backend                ├── Render backend
├── Vercel frontend               ├── Vercel frontend
└── PostgreSQL                    └── PostgreSQL (new or shared)

Both running simultaneously - no downtime!
```

## Prerequisites

- GitHub account with repository access
- Render account (https://render.com)
- Vercel account (https://vercel.com)
- PostgreSQL database (Neon or Supabase)
- Environment variables prepared

## Step 1: Database Setup (5 minutes)

### Choose Your Database

#### Option 1A: Neon (Recommended)
1. Go to https://neon.tech
2. Sign up with GitHub
3. Create new project: "BikeTaxi-Production"
4. Copy connection string
5. Save for later: `DATABASE_URL`

#### Option 1B: Supabase
1. Go to https://supabase.com
2. Sign up with GitHub
3. Create new project: "BikeTaxi-Production"
4. Copy connection string
5. Save for later: `DATABASE_URL`

### Prepare Database Connection String

Your connection string will look like:
```
postgresql://user:password@host:5432/database
```

Save this - you'll need it in Step 2 and Step 3.

---

## Step 2: Deploy Backend to NEW Render Service (10 minutes)

### 2.1 Create New Render Service

1. Go to https://render.com
2. Sign in with GitHub
3. Click "New +"
4. Select "Web Service"
5. Click "Connect repository"

### 2.2 Find Repository

1. Search for "BikeTaxi"
2. Select: `nithishv17-dot/BikeTaxi`
3. Branch: `v0/project-analysis-b16c254b`
4. Click "Connect"

### 2.3 Configure Service

Fill in these fields:

| Field | Value |
|-------|-------|
| Name | `biketaxi-api-prod` |
| Environment | Node |
| Build Command | `cd backend && npm install --legacy-peer-deps && npm run build:ts` |
| Start Command | `cd backend && npm run start:ts` |
| Region | Choose closest to users |
| Plan | Free (or Starter if preferred) |

### 2.4 Environment Variables

Click "Advanced" → "Environment Variables"

Add these variables:

```
DATABASE_URL=<your-neon-or-supabase-connection-string>
NODE_ENV=production
PORT=10000
JWT_SECRET=<run: openssl rand -base64 32>
CORS_ORIGIN=<your-vercel-frontend-url-from-step-3>
LOG_LEVEL=info
DATABASE_TYPE=postgres
POSTGRES_MODE=primary
MONGODB_MODE=backup-only
DUAL_WRITE_ENABLED=false
```

### 2.5 Generate JWT Secret

Run in terminal:
```bash
openssl rand -base64 32
```

Copy the output and paste into `JWT_SECRET` field.

### 2.6 Deploy

1. Click "Create Web Service"
2. Wait for build to complete (3-5 minutes)
3. You'll get a URL like: `https://biketaxi-api-prod.onrender.com`
4. Save this URL - needed for Step 3

### 2.7 Verify Backend

Wait 2 minutes, then test:

```bash
curl https://biketaxi-api-prod.onrender.com/health
```

Expected response:
```json
{
  "status": "ok",
  "database": "PostgreSQL",
  "version": "1.0.0"
}
```

**Status: Backend deployed! ✓**

---

## Step 3: Deploy Frontend to NEW Vercel Project (10 minutes)

### 3.1 Add Backend URL to Vercel Config

Before deploying, update frontend to know about new backend.

In file: `frontend/react_app/.env.local`:

```
NEXT_PUBLIC_API_URL=https://biketaxi-api-prod.onrender.com
NEXT_PUBLIC_ENVIRONMENT=production
```

Or you can set these in Vercel UI later.

### 3.2 Create New Vercel Project

1. Go to https://vercel.com
2. Sign in with GitHub
3. Click "Add New..."
4. Select "Project"
5. Click "Continue with GitHub"
6. Search for "BikeTaxi"
7. Import `nithishv17-dot/BikeTaxi`

### 3.3 Configure Project

When prompted to configure:

| Field | Value |
|-------|-------|
| Project Name | `biketaxi-prod` |
| Framework Preset | Next.js |
| Root Directory | `frontend/react_app` |
| Build Command | `npm run build` |
| Output Directory | `.next` |

### 3.4 Environment Variables

Add these variables:

```
NEXT_PUBLIC_API_URL=https://biketaxi-api-prod.onrender.com
NEXT_PUBLIC_ENVIRONMENT=production
NEXT_PUBLIC_APP_NAME=BikeTaxi
```

### 3.5 Deploy

1. Click "Deploy"
2. Wait for build to complete (2-3 minutes)
3. You'll get a URL like: `https://biketaxi-prod.vercel.app`
4. Save this URL

### 3.6 Update Render CORS

Go back to Render → biketaxi-api-prod:

1. Click "Environment"
2. Edit `CORS_ORIGIN`
3. Set to: `https://biketaxi-prod.vercel.app`
4. Click "Save"
5. Service will restart

### 3.7 Verify Frontend

Test loading the app:

1. Go to `https://biketaxi-prod.vercel.app`
2. Should load without errors
3. Check browser console (F12) for any errors
4. Try loading the health endpoint in browser

**Status: Frontend deployed! ✓**

---

## Step 4: Verify Integration (5 minutes)

### Test Complete Flow

```bash
# 1. Health check
curl https://biketaxi-api-prod.onrender.com/health

# 2. Migration status
curl https://biketaxi-api-prod.onrender.com/api/migration/status

# 3. Users list
curl https://biketaxi-api-prod.onrender.com/api/users

# 4. Admin stats
curl https://biketaxi-api-prod.onrender.com/api/admin/stats
```

All should return 200 OK with JSON responses.

### Test Frontend Integration

1. Open `https://biketaxi-prod.vercel.app`
2. Check console (F12) for errors
3. Try user registration (should fail gracefully if no actual DB)
4. Verify no CORS errors

---

## Step 5: Post-Deployment Monitoring (Ongoing)

### Monitor Backend

Visit Render dashboard:
- Check CPU/Memory usage
- Check error logs
- Set up alerts

### Monitor Frontend

Visit Vercel dashboard:
- Check build logs
- Check Web Vitals
- Monitor error rates

### Database

Check your Neon/Supabase dashboard:
- Connection count
- Query performance
- Disk usage

---

## Summary

### What You Now Have

```
Production URLs:
├── Frontend: https://biketaxi-prod.vercel.app
├── Backend: https://biketaxi-api-prod.onrender.com
└── Database: PostgreSQL (Neon/Supabase)

Old Project (Still Running):
├── Frontend: <your-old-vercel-url>
├── Backend: <your-old-render-url>
└── Database: PostgreSQL (old)

Both can coexist for testing and gradual migration.
```

### Performance

- Render free tier: 750 compute hours/month
- Vercel: 100GB bandwidth/month free
- Both with auto-scaling available

### Next Steps

1. Test thoroughly for 24-48 hours
2. Monitor performance metrics
3. Gather user feedback
4. Switch DNS/load balancer if using custom domain
5. Decommission old project when confident

### Rollback Plan

If issues arise:

1. Revert DNS to old URLs
2. Keep old project running
3. Investigate issues locally
4. Re-deploy when fixed

---

## Troubleshooting

### Backend Build Fails

Check Render build logs:
1. Click "Logs" tab
2. Look for TypeScript errors
3. Verify all dependencies installed
4. Check package.json scripts

### Frontend Can't Reach API

Check browser console (F12):
- CORS error? Check CORS_ORIGIN in Render
- Network error? Check API_URL in Vercel env vars
- Timeout? Check Render service is running

### Database Connection Fails

Check Render logs:
- Verify DATABASE_URL format
- Check firewall rules in Neon/Supabase
- Verify credentials are correct

### Performance Issues

Check metrics:
- Render: CPU, memory, disk
- Vercel: Web Vitals, build time
- Database: Query performance, connections

---

## Security Checklist

- [ ] JWT_SECRET is random and secure
- [ ] DATABASE_URL is not exposed in logs
- [ ] CORS_ORIGIN is set to frontend URL
- [ ] NODE_ENV is set to production
- [ ] No debug mode enabled
- [ ] Secrets not in git repository
- [ ] HTTPS enforced on all URLs

---

## Cost Monitoring

### Render Costs
- Free tier: Included
- Paid tier: Starting at $7/month
- Auto-scales as needed

### Vercel Costs
- Free tier: Included
- Paid tier: Starting at $20/month
- Overage: $0.15 per GB bandwidth

### Database Costs
- Neon: Starting at $0.30/GB storage
- Supabase: Starting at $5/month

**Estimated total: $5-15/month for production**

---

## Success Criteria

Your deployment is successful when:

- [ ] Backend responds at /health
- [ ] Frontend loads without errors
- [ ] API calls from frontend work
- [ ] No CORS errors
- [ ] Database queries working
- [ ] Logs show no critical errors
- [ ] Performance metrics acceptable

---

## Support

For issues:

1. Check Render build logs
2. Check Vercel build logs
3. Check browser console (F12)
4. Check database connection
5. Verify environment variables
6. Review error messages carefully

Questions? Check:
- DEPLOYMENT_GUIDE.md
- MIGRATION_COMPLETE.md
- GitHub repository issues

