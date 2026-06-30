# BikeTaxi - Local Testing Setup

## Prerequisites Installed

- Node.js 18+
- npm or yarn
- Git
- PostgreSQL (optional for local testing - can use mock data)

## Project Structure

```
/vercel/share/v0-project/
├── backend/                 (Express.js API)
│   ├── src/
│   │   ├── routes/         (API endpoints)
│   │   ├── middleware/     (Auth, validation)
│   │   ├── services/       (Business logic)
│   │   ├── config/         (Configuration)
│   │   └── utils/          (Helpers)
│   ├── package.json
│   └── tsconfig.json
│
├── frontend/
│   └── react_app/          (React/Next.js)
│       ├── src/
│       │   ├── components/ (React components)
│       │   ├── pages/      (Pages)
│       │   ├── store/      (Redux)
│       │   └── styles/     (CSS)
│       └── package.json
│
└── docs/
    ├── MIGRATION_COMPLETE.md
    ├── DEPLOYMENT_GUIDE.md
    └── LOCAL_TESTING_GUIDE.md
```

## Option A: Quick Demo Server (Easiest)

This is the fastest way to see the project working.

### Start Demo Server

```bash
cd /vercel/share/v0-project/backend
node ../demo-server.js
```

Server runs on: http://localhost:5000

### Test Endpoints

```bash
# Health check
curl http://localhost:5000/health

# Migration status
curl http://localhost:5000/api/migration/status

# List users
curl http://localhost:5000/api/users

# Admin stats
curl http://localhost:5000/api/admin/stats
```

Expected responses: All endpoints return JSON with mock data

## Option B: Full Backend Setup (Production-Like)

### Step 1: Install Dependencies

```bash
cd /vercel/share/v0-project/backend
npm install --legacy-peer-deps
```

### Step 2: Generate Prisma Client

```bash
npm run prisma:generate
```

### Step 3: Build TypeScript

```bash
npm run build:ts
```

### Step 4: Start Backend

```bash
npm run start:ts
```

Backend runs on: http://localhost:5000

## Option C: Full Stack Local Development

### Start Backend

```bash
cd /vercel/share/v0-project/backend
npm install --legacy-peer-deps
npm run dev
```

### Start Frontend (in another terminal)

```bash
cd /vercel/share/v0-project/frontend/react_app
npm install
npm run dev
```

Frontend runs on: http://localhost:3000

## API Testing

### Available Endpoints

#### Authentication
- POST /api/auth/register
- POST /api/auth/login
- POST /api/auth/logout
- POST /api/auth/refresh-token

#### Users
- GET /api/users
- GET /api/users/:id
- PUT /api/users/:id
- GET /api/users/profile

#### Rides
- GET /api/rides
- GET /api/rides/:id
- POST /api/rides/create
- PATCH /api/rides/:id/status
- GET /api/rides/history
- POST /api/rides/:id/rate

#### Admin
- GET /api/admin/stats
- GET /api/admin/users
- GET /api/admin/rides

#### Migration
- GET /api/migration/status
- GET /api/migration/progress
- POST /api/migration/verify

### Test with cURL

```bash
# Register user
curl -X POST http://localhost:5000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "phone": "9876543210",
    "password": "Password@123"
  }'

# Login
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "9876543210",
    "password": "Password@123"
  }'

# Create ride (requires token from login)
curl -X POST http://localhost:5000/api/rides/create \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -d '{
    "startLocation": {"lat": 40.7128, "lng": -74.0060},
    "endLocation": {"lat": 40.7580, "lng": -73.9855},
    "rideType": "regular"
  }'
```

### Test with Postman

1. Open Postman
2. Import the collection: (will create one for you)
3. Set base URL: http://localhost:5000
4. Test each endpoint

## Testing Checklist

### Database Connection
- [ ] Backend starts without errors
- [ ] No database connection errors
- [ ] Mock data loads successfully

### API Functionality
- [ ] Health endpoint returns 200 OK
- [ ] Users endpoint returns list
- [ ] Rides endpoint returns list
- [ ] Admin stats accessible
- [ ] Migration status shows complete

### User Registration & Login
- [ ] Can register new user
- [ ] Can login with credentials
- [ ] JWT token received
- [ ] Token validates future requests

### Ride Features
- [ ] Can create ride
- [ ] Can update ride status
- [ ] Can get ride history
- [ ] Can rate ride

### Error Handling
- [ ] Invalid endpoints return 404
- [ ] Missing auth returns 401
- [ ] Invalid data returns 400
- [ ] Server errors return 500

### Performance
- [ ] Health check responds < 10ms
- [ ] User list responds < 50ms
- [ ] Ride creation responds < 100ms
- [ ] No memory leaks after 100 requests

### Data Integrity
- [ ] Migration status shows 100% complete
- [ ] Record counts match expectations
- [ ] No data loss reported
- [ ] Timestamps correct

## Debugging

### View Logs

```bash
# Backend logs
tail -f /tmp/demo.log

# Or if running in terminal
# Logs appear in same terminal as server
```

### Enable Debug Mode

```bash
# Run with debug logging
DEBUG=* npm run dev

# Or set in .env
LOG_LEVEL=debug
```

### Common Issues

**Port 5000 already in use**
```bash
# Find process using port 5000
lsof -i :5000

# Kill the process
kill -9 <PID>
```

**Module not found errors**
```bash
# Reinstall dependencies
rm -rf node_modules
npm install --legacy-peer-deps

# Regenerate Prisma
npm run prisma:generate
```

**TypeScript compilation errors**
```bash
# Check for syntax errors
npm run build:ts

# Fix issues and try again
npm run dev
```

## Next Steps After Local Testing

If everything works:

1. Document test results
2. Make deployment decision:
   - Deploy to new Render/Vercel services
   - Replace old project
   - Merge into existing project
   - Continue local development

If issues found:

1. Check error logs
2. Fix the code
3. Commit changes
4. Re-test

## Commands Reference

```bash
# Backend
npm install                  # Install dependencies
npm run build:ts            # Compile TypeScript
npm run dev                 # Start in dev mode
npm start:ts               # Start compiled version
npm run test               # Run tests
npm run test:unit          # Run unit tests
npm run test:integration   # Run integration tests
npm run prisma:generate    # Generate Prisma client

# Frontend
npm install                # Install dependencies
npm run dev                # Start dev server
npm run build              # Build for production
npm run start              # Start production build

# Utilities
npm run lint               # Run linter
npm run format             # Format code
npm run type-check         # TypeScript check
```

