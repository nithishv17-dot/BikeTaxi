#!/bin/bash

# BikeTaxi Deployment Script
# Deploys backend to Render and frontend to Vercel

set -e

echo "════════════════════════════════════════════════════════════════"
echo "          BikeTaxi Deployment - Render & Vercel"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "DEPLOYMENT_GUIDE.md" ]; then
    echo -e "${RED}Error: Please run this script from the project root directory${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Preparing Backend for Render${NC}"
echo "---"

# Check backend
if [ ! -d "backend" ]; then
    echo -e "${RED}Error: backend directory not found${NC}"
    exit 1
fi

cd backend

# Install dependencies
echo "Installing backend dependencies..."
npm install --legacy-peer-deps

# Build TypeScript
echo "Building TypeScript..."
npm run build:ts

# Check if build succeeded
if [ ! -d "dist" ]; then
    echo -e "${RED}Error: Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Backend ready for Render${NC}"
cd ..

echo ""
echo -e "${YELLOW}Step 2: Preparing Frontend for Vercel${NC}"
echo "---"

# Check frontend
if [ ! -d "frontend/react_app" ]; then
    echo -e "${RED}Error: frontend/react_app directory not found${NC}"
    exit 1
fi

cd frontend/react_app

# Install dependencies
echo "Installing frontend dependencies..."
npm install --legacy-peer-deps

# Build Next.js
echo "Building Next.js..."
npm run build

# Check if build succeeded
if [ ! -d ".next" ]; then
    echo -e "${RED}Error: Frontend build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Frontend ready for Vercel${NC}"
cd ../..

echo ""
echo -e "${YELLOW}Step 3: Git Configuration${NC}"
echo "---"

# Ensure we're on the right branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT_BRANCH"

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Uncommitted changes detected${NC}"
    echo "Commit changes before deployment? (y/n)"
    read -r response
    if [ "$response" = "y" ]; then
        git add .
        git commit -m "Prepare for deployment: Render backend, Vercel frontend"
    fi
fi

echo ""
echo -e "${YELLOW}Step 4: Deployment Instructions${NC}"
echo "---"
echo ""
echo "Backend (Render):"
echo "1. Go to https://render.com"
echo "2. Connect your GitHub repository"
echo "3. Create new Web Service"
echo "4. Use these settings:"
echo "   - Runtime: Node"
echo "   - Build: npm install --legacy-peer-deps && npm run build:ts"
echo "   - Start: npm run start:ts"
echo "   - Root Directory: backend"
echo "5. Add environment variables from .env.render.example"
echo ""

echo "Frontend (Vercel):"
echo "1. Go to https://vercel.com"
echo "2. Import your GitHub repository"
echo "3. Use these settings:"
echo "   - Framework: Next.js"
echo "   - Build: npm run build"
echo "   - Root Directory: frontend/react_app"
echo "4. Add environment variables from .env.vercel.example"
echo ""

echo -e "${YELLOW}Step 5: Database Setup${NC}"
echo "---"
echo ""
echo "Choose database provider:"
echo "1. Neon (PostgreSQL) - https://neon.tech"
echo "2. Supabase (PostgreSQL) - https://supabase.com"
echo "3. AWS RDS - https://aws.amazon.com/rds/"
echo ""
echo "After setting up database:"
echo "1. Get the connection string"
echo "2. Add DATABASE_URL to Render environment variables"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                   Deployment Ready!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "1. Set up PostgreSQL database (Neon/Supabase/AWS)"
echo "2. Deploy backend to Render"
echo "3. Deploy frontend to Vercel"
echo "4. Add environment variables to both services"
echo "5. Test the deployed application"
echo ""
echo "Documentation:"
echo "- See DEPLOYMENT_GUIDE.md for detailed instructions"
echo "- See .env.render.example for backend variables"
echo "- See .env.vercel.example for frontend variables"
echo ""
