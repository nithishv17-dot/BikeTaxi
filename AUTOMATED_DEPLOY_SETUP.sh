#!/bin/bash

# BikeTaxi Option A - Automated Deployment Setup
# This script prepares everything for deployment to new Render + Vercel services

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   BIKETAXI - AUTOMATED DEPLOYMENT SETUP (OPTION A)           ║"
echo "║                                                                ║"
echo "║   This script prepares your project for deployment            ║"
echo "║   You will then click a few buttons to deploy                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Verify repository setup
echo "Step 1: Verifying GitHub repository..."
cd /vercel/share/v0-project

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "✗ Not a git repository"
    exit 1
fi

REMOTE=$(git config --get remote.origin.url)
echo "✓ Repository: $REMOTE"
echo "✓ Branch: $(git rev-parse --abbrev-ref HEAD)"
echo ""

# Step 2: Verify project structure
echo "Step 2: Verifying project structure..."
if [ ! -d "backend" ]; then
    echo "✗ Missing backend directory"
    exit 1
fi

if [ ! -d "frontend/react_app" ]; then
    echo "✗ Missing frontend/react_app directory"
    exit 1
fi

echo "✓ Backend: Found"
echo "✓ Frontend: Found"
echo ""

# Step 3: Check backend configuration
echo "Step 3: Checking backend configuration..."
if [ ! -f "backend/package.json" ]; then
    echo "✗ Missing backend/package.json"
    exit 1
fi

if [ ! -f "backend/render.yaml" ]; then
    echo "⚠ Missing render.yaml - creating..."
    cat > backend/render.yaml << 'RENDER_CONFIG'
services:
  - type: web
    name: biketaxi-api-prod
    env: node
    buildCommand: npm install --legacy-peer-deps && npm run build:ts
    startCommand: npm run start:ts
    envVars:
      - key: NODE_ENV
        value: production
      - key: LOG_LEVEL
        value: info
RENDER_CONFIG
    echo "✓ render.yaml created"
fi

echo "✓ Backend configuration: Ready"
echo ""

# Step 4: Check frontend configuration
echo "Step 4: Checking frontend configuration..."
if [ ! -f "frontend/react_app/package.json" ]; then
    echo "✗ Missing frontend/react_app/package.json"
    exit 1
fi

if [ ! -f "frontend/react_app/vercel.json" ]; then
    echo "⚠ Missing vercel.json - creating..."
    cat > frontend/react_app/vercel.json << 'VERCEL_CONFIG'
{
  "buildCommand": "npm run build",
  "outputDirectory": ".next",
  "env": {
    "NEXT_PUBLIC_API_URL": "@next_public_api_url",
    "NEXT_PUBLIC_ENVIRONMENT": "production"
  }
}
VERCEL_CONFIG
    echo "✓ vercel.json created"
fi

echo "✓ Frontend configuration: Ready"
echo ""

# Step 5: Create environment variable templates
echo "Step 5: Creating environment templates..."

cat > .env.render.production << 'RENDER_ENV'
# Backend Environment Variables for Render
# Fill these in before deploying

# Database
DATABASE_URL=postgresql://user:password@host:5432/biketaxi
DATABASE_TYPE=postgres

# Node
NODE_ENV=production
PORT=10000

# Security
JWT_SECRET=GENERATE_WITH: openssl rand -base64 32

# CORS
CORS_ORIGIN=https://biketaxi-prod.vercel.app

# Database Modes
POSTGRES_MODE=primary
MONGODB_MODE=backup-only
DUAL_WRITE_ENABLED=false

# Logging
LOG_LEVEL=info
RENDER_ENV

cat > frontend/react_app/.env.production << 'VERCEL_ENV'
# Frontend Environment Variables for Vercel
# These will be set in Vercel UI

NEXT_PUBLIC_API_URL=https://biketaxi-api-prod.onrender.com
NEXT_PUBLIC_ENVIRONMENT=production
NEXT_PUBLIC_APP_NAME=BikeTaxi
VERCEL_ENV

echo "✓ Environment templates created:"
echo "  - .env.render.production"
echo "  - frontend/react_app/.env.production"
echo ""

# Step 6: Generate JWT Secret
echo "Step 6: Generating JWT secret..."
JWT_SECRET=$(openssl rand -base64 32)
echo "✓ Generated JWT secret: $JWT_SECRET"
echo "  (Copy this when setting up Render environment variables)"
echo ""

# Step 7: Push to GitHub
echo "Step 7: Preparing git commit..."
git add -A
git status

echo ""
echo "Ready to commit? (y/n)"
read -r RESPONSE

if [ "$RESPONSE" = "y" ]; then
    git commit -m "Prepare Option A automated deployment

- render.yaml: Render service configuration
- vercel.json: Vercel project configuration  
- .env.render.production: Backend env template
- frontend/.env.production: Frontend env template
- JWT Secret generated

Ready for one-click deployment to:
✓ Backend: https://biketaxi-api-prod.onrender.com
✓ Frontend: https://biketaxi-prod.vercel.app

Next steps:
1. Create database (Neon/Supabase)
2. Connect Render to GitHub
3. Connect Vercel to GitHub
4. Deploy!"
    
    echo "✓ Committed to git"
    echo ""
fi

# Step 8: Create deployment checklist
echo "Step 8: Creating deployment checklist..."

cat > DEPLOYMENT_CHECKLIST.md << 'CHECKLIST'
# Option A Deployment Checklist

## Prerequisites (Do These First)

- [ ] Have Render account (render.com)
- [ ] Have Vercel account (vercel.com)  
- [ ] Have GitHub account with repo access
- [ ] Create PostgreSQL database (Neon or Supabase)
- [ ] Copy DATABASE_URL connection string

## Database Setup (Neon Recommended)

- [ ] Go to https://neon.tech
- [ ] Create account with GitHub
- [ ] New project: "BikeTaxi-Production"
- [ ] Copy connection string
- [ ] Save as DATABASE_URL

## Backend Deployment (Render)

- [ ] Go to https://render.com
- [ ] Sign in with GitHub
- [ ] Click "New +"
- [ ] Select "Web Service"
- [ ] Connect: nithishv17-dot/BikeTaxi
- [ ] Branch: v0/project-analysis-b16c254b
- [ ] Name: biketaxi-api-prod
- [ ] Build Command: cd backend && npm install --legacy-peer-deps && npm run build:ts
- [ ] Start Command: cd backend && npm run start:ts
- [ ] Environment Variables:
  - DATABASE_URL: (your Neon/Supabase URL)
  - NODE_ENV: production
  - JWT_SECRET: (from setup script output)
  - CORS_ORIGIN: (update after Vercel deployment)
  - Others: (see .env.render.production)
- [ ] Deploy
- [ ] Save backend URL: https://biketaxi-api-prod.onrender.com

## Frontend Deployment (Vercel)

- [ ] Go to https://vercel.com
- [ ] Sign in with GitHub
- [ ] Add New → Project
- [ ] Import → nithishv17-dot/BikeTaxi
- [ ] Project Name: biketaxi-prod
- [ ] Framework: Next.js
- [ ] Root Directory: frontend/react_app
- [ ] Environment Variables:
  - NEXT_PUBLIC_API_URL: https://biketaxi-api-prod.onrender.com
  - NEXT_PUBLIC_ENVIRONMENT: production
- [ ] Deploy
- [ ] Save frontend URL: https://biketaxi-prod.vercel.app

## Post-Deployment

- [ ] Update Render CORS_ORIGIN to Vercel URL
- [ ] Test backend health endpoint
- [ ] Test frontend loads
- [ ] Check browser console (F12) for errors
- [ ] Test user registration
- [ ] Test ride creation
- [ ] Monitor for 24 hours
- [ ] Decide: Keep new or rollback

## Verification

Backend tests:
```bash
curl https://biketaxi-api-prod.onrender.com/health
curl https://biketaxi-api-prod.onrender.com/api/migration/status
curl https://biketaxi-api-prod.onrender.com/api/users
```

Frontend: https://biketaxi-prod.vercel.app

All working? Deployment successful!
CHECKLIST

echo "✓ Deployment checklist created: DEPLOYMENT_CHECKLIST.md"
echo ""

# Final Summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  SETUP COMPLETE!                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ Backend configuration: Ready"
echo "✓ Frontend configuration: Ready"
echo "✓ Environment templates: Ready"
echo "✓ JWT Secret: Generated"
echo "✓ Git repository: Ready"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "NEXT: Follow DEPLOYMENT_CHECKLIST.md"
echo ""
echo "Summary of what you need to do:"
echo ""
echo "1. Create database:"
echo "   → Go to https://neon.tech"
echo "   → Create project, get CONNECTION STRING"
echo ""
echo "2. Deploy backend:"
echo "   → Go to https://render.com"
echo "   → New Web Service"
echo "   → Connect GitHub (nithishv17-dot/BikeTaxi)"
echo "   → Configure with template in render.yaml"
echo ""
echo "3. Deploy frontend:"
echo "   → Go to https://vercel.com"
echo "   → Import project"
echo "   → Configure with template in vercel.json"
echo ""
echo "4. Update CORS:"
echo "   → After Vercel deploys, update Render CORS_ORIGIN"
echo ""
echo "5. Test:"
echo "   → Verify both services working"
echo "   → Monitor for 24 hours"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Need help? Check:"
echo "  - DEPLOYMENT_CHECKLIST.md"
echo "  - OPTION_A_QUICK_START.txt"
echo "  - OPTION_A_DEPLOYMENT.md"
echo ""
echo "JWT Secret (needed for Render env vars):"
echo "  $JWT_SECRET"
echo ""
echo "════════════════════════════════════════════════════════════════"

