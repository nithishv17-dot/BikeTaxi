# BikeTaxi Option A - Interactive Deployment Guide

Your automated setup is complete. Follow these simple steps to deploy.

---

## JWT Secret (You'll Need This)

**Save this value - you'll paste it into Render:**

```
LsbQlkmmPW32m7piEvT1u+SVmcwsVsPMzJk8p10LoEE=
```

---

## Step 1: Create PostgreSQL Database (5 minutes)

### Option 1A: Neon (Recommended - Easiest)

1. **Open:** https://neon.tech
2. **Sign up:** Click "Sign up" → GitHub
3. **Authorize:** Approve GitHub access
4. **Create Project:**
   - Project name: `BikeTaxi-Production`
   - Keep defaults, click "Create project"
5. **Copy Connection String:**
   - Click "Connection string"
   - Copy the full string (starts with `postgresql://`)
   - Save as `DATABASE_URL`

**Expected format:**
```
postgresql://user:password@host/biketaxi?sslmode=require
```

### Option 1B: Supabase (Alternative)

1. **Open:** https://supabase.com
2. **Sign up:** GitHub
3. **Create Project:**
   - Name: `BikeTaxi-Production`
   - Set password
4. **Copy Connection String:**
   - Project settings → Database
   - Connection string (Postgres)
   - Copy and save

✓ **Database Created!** Move to Step 2.

---

## Step 2: Deploy Backend to Render (10 minutes)

### 2.1 Go to Render

**Open:** https://render.com

### 2.2 Sign In

- Click "Login"
- Choose "GitHub"
- Authorize access

### 2.3 Create Web Service

1. Click "New +"
2. Select "Web Service"
3. Click "Connect repository"

### 2.4 Select Repository

1. Search: "BikeTaxi"
2. Click the repository: `nithishv17-dot/BikeTaxi`
3. Branch: `v0/project-analysis-b16c254b`
4. Click "Connect"

### 2.5 Configure Service

**Fill in these fields:**

| Field | Value |
|-------|-------|
| Name | `biketaxi-api-prod` |
| Environment | `Node` |
| Build Command | `cd backend && npm install --legacy-peer-deps && npm run build:ts` |
| Start Command | `cd backend && npm run start:ts` |
| Region | Pick closest to your users |

### 2.6 Add Environment Variables

**Scroll down to "Environment Variables"**

Click "Add Environment Variable" for each:

| Key | Value |
|-----|-------|
| `DATABASE_URL` | Paste your connection string from Step 1 |
| `NODE_ENV` | `production` |
| `JWT_SECRET` | Paste: `LsbQlkmmPW32m7piEvT1u+SVmcwsVsPMzJk8p10LoEE=` |
| `CORS_ORIGIN` | `https://biketaxi-prod.vercel.app` (you'll get this URL in Step 3) |
| `LOG_LEVEL` | `info` |
| `DATABASE_TYPE` | `postgres` |
| `POSTGRES_MODE` | `primary` |
| `MONGODB_MODE` | `backup-only` |

### 2.7 Deploy!

Click "Create Web Service"

⏳ **Wait 3-5 minutes for build to complete**

You'll see your backend URL like:
```
https://biketaxi-api-prod.onrender.com
```

✓ **Save this URL** - you need it for Step 3

### 2.8 Verify Backend

Test in terminal or browser:

```bash
curl https://biketaxi-api-prod.onrender.com/health
```

Should return: `{"status":"ok","database":"PostgreSQL",...}`

✓ **Backend Deployed!** Move to Step 3.

---

## Step 3: Deploy Frontend to Vercel (10 minutes)

### 3.1 Go to Vercel

**Open:** https://vercel.com

### 3.2 Sign In

- Click "Login"
- Choose "GitHub"
- Authorize access

### 3.3 Import Project

1. Click "Add New"
2. Select "Project"
3. Click "Continue with GitHub"

### 3.4 Find Repository

1. Search: "BikeTaxi"
2. Click: `nithishv17-dot/BikeTaxi`
3. Click "Import"

### 3.5 Configure Project

**When prompted, fill in:**

| Field | Value |
|-------|-------|
| Project Name | `biketaxi-prod` |
| Framework | `Next.js` |
| Root Directory | `frontend/react_app` |

### 3.6 Add Environment Variables

Click "Environment Variables"

Add:

| Key | Value |
|-----|-------|
| `NEXT_PUBLIC_API_URL` | Paste your Render backend URL from Step 2 (e.g., `https://biketaxi-api-prod.onrender.com`) |
| `NEXT_PUBLIC_ENVIRONMENT` | `production` |
| `NEXT_PUBLIC_APP_NAME` | `BikeTaxi` |

### 3.7 Deploy!

Click "Deploy"

⏳ **Wait 2-3 minutes for build to complete**

You'll get a frontend URL like:
```
https://biketaxi-prod.vercel.app
```

✓ **Save this URL**

### 3.8 Verify Frontend

1. Visit: `https://biketaxi-prod.vercel.app`
2. Should load without errors
3. Open browser console (F12) - no CORS errors

✓ **Frontend Deployed!** Move to Step 4.

---

## Step 4: Update CORS (1 minute)

Now that you have the Vercel URL, update Render's CORS setting:

1. Go back to: https://render.com
2. Click on: `biketaxi-api-prod` service
3. Click: "Environment"
4. Find: `CORS_ORIGIN`
5. Edit the value to: `https://biketaxi-prod.vercel.app`
6. Click "Save"
7. Service will restart automatically

✓ **CORS Updated!** Move to Step 5.

---

## Step 5: Verify Integration (5 minutes)

### Test Backend Endpoints

Run these commands in terminal:

```bash
# Health check
curl https://biketaxi-api-prod.onrender.com/health

# Migration status
curl https://biketaxi-api-prod.onrender.com/api/migration/status

# Users
curl https://biketaxi-api-prod.onrender.com/api/users

# Admin stats
curl https://biketaxi-api-prod.onrender.com/api/admin/stats
```

All should return `200 OK` with JSON.

### Test Frontend

1. Open: `https://biketaxi-prod.vercel.app`
2. Page should load
3. Check console (F12) - no errors
4. Try clicking around

### Success Criteria

- [ ] Backend health check returns 200
- [ ] Frontend loads without errors
- [ ] No CORS errors in console
- [ ] All API endpoints work
- [ ] Database connection working

✓ **All Tests Passed!** Deployment Complete!

---

## What You Now Have

### Production URLs

```
Frontend: https://biketaxi-prod.vercel.app
Backend:  https://biketaxi-api-prod.onrender.com
Database: PostgreSQL (Neon/Supabase)
```

### Old Project (Still Running)

Your original project continues to run on:
- Original Render URL
- Original Vercel URL

Both can coexist!

---

## Post-Deployment

### Monitor for 24-48 Hours

1. Check Render logs: https://render.com
2. Check Vercel logs: https://vercel.com
3. Watch for errors

### If Everything Works

- Decision: Keep new service, decommission old
- Or: Keep both running for A/B testing

### If Issues

1. Check error logs
2. Verify environment variables
3. Check database connection
4. Revert to old URLs if needed

---

## Troubleshooting

### "Backend connection refused"
- Render service still building (wait 2-3 min)
- Check Render logs for build errors
- Verify DATABASE_URL is correct

### "CORS error in frontend"
- Update CORS_ORIGIN in Render
- Wait 1 minute for restart
- Hard refresh (Ctrl+F5) browser

### "Database connection failed"
- Verify DATABASE_URL format
- Check credentials in Neon/Supabase
- Verify firewall allows connection

### "Frontend can't reach API"
- Check NEXT_PUBLIC_API_URL in Vercel env vars
- Verify it matches Render backend URL
- Hard refresh browser

---

## Success! 🎉

You've successfully deployed BikeTaxi to new Render + Vercel services!

**Total Time: ~30 minutes**

Your BikeTaxi is now live and your old project is still running.

Next: Monitor for 24-48 hours, then decide to keep new service or rollback.

