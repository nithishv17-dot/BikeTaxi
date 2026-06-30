# BikeTaxi Local Testing Guide

## Current Setup

- **Old Project:** Running on Render (backend) + Vercel (frontend) - LIVE
- **New Project:** Running locally for testing

## Local Server Status

The BikeTaxi demo server is running on:
```
http://localhost:5000
```

## Testing Endpoints

### 1. Health Check
```bash
curl http://localhost:5000/health
```

Expected Response:
```json
{
  "status": "ok",
  "timestamp": "2026-06-30T10:30:00Z",
  "database": "PostgreSQL",
  "version": "1.0.0"
}
```

### 2. Migration Status
```bash
curl http://localhost:5000/api/migration/status
```

Expected: Complete migration details with MongoDB→PostgreSQL switch confirmed

### 3. User Endpoints
```bash
# List users
curl http://localhost:5000/api/users

# Get specific user
curl http://localhost:5000/api/users/1

# Admin stats
curl http://localhost:5000/api/admin/stats
```

### 4. Ride Endpoints
```bash
# List rides
curl http://localhost:5000/api/rides

# Get specific ride
curl http://localhost:5000/api/rides/1

# Get available rides
curl http://localhost:5000/api/rides/available
```

### 5. Authentication (Test)
```bash
# Login
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"9876543210","password":"password123"}'
```

## Testing Features

### Feature 1: User Registration
- Endpoint: POST /api/auth/register
- Status: Ready to test
- Expected: User created with PostgreSQL

### Feature 2: Ride Booking
- Endpoint: POST /api/rides/create
- Status: Ready to test
- Expected: Ride stored in PostgreSQL

### Feature 3: Authentication
- Endpoint: POST /api/auth/login
- Status: Ready to test
- Expected: JWT token returned

### Feature 4: Admin Dashboard
- Endpoint: GET /api/admin/stats
- Status: Ready to test
- Expected: System statistics

### Feature 5: Migration Verification
- Endpoint: GET /api/migration/status
- Status: Ready to test
- Expected: All metrics confirmed

## Local Testing Checklist

### Database Connection
- [ ] PostgreSQL connection working
- [ ] Schema migrated successfully
- [ ] Data accessible
- [ ] Indexes operational

### API Functionality
- [ ] Health endpoint responding
- [ ] User list endpoint working
- [ ] Ride list endpoint working
- [ ] Authentication working
- [ ] Admin stats accessible

### Data Integrity
- [ ] Migration status shows 100% complete
- [ ] Record counts match
- [ ] No data loss reported
- [ ] Consistency verified

### Performance
- [ ] Response times acceptable (<50ms)
- [ ] No errors in responses
- [ ] Database queries efficient
- [ ] Memory usage stable

### Error Handling
- [ ] Invalid requests handled
- [ ] Missing auth rejected
- [ ] Database errors logged
- [ ] Graceful error messages

## Next Steps

After local testing:

### If Testing Passes
1. Document results
2. Deploy to Render (new service or replace)
3. Deploy to Vercel (new project or replace)
4. Test in production
5. Monitor for 24 hours

### If Issues Found
1. Document the issue
2. Check error logs
3. Fix the code
4. Re-test locally
5. Try again

## Stopping Local Server

To stop the local test server:
```bash
pkill -f demo-server
```

## Viewing Logs

Check the server logs:
```bash
tail -f /tmp/demo.log
```

## Database Access

To access test data directly:
```bash
# Connect to your PostgreSQL (if available)
psql -c "SELECT * FROM users LIMIT 5;"
```

## Next Phase Decision

Once local testing is complete:
- **Option 1:** Deploy to same Render/Vercel (replace old project)
- **Option 2:** Deploy to new Render/Vercel services (keep both running)
- **Option 3:** Merge features into existing project
- **Option 4:** Continue local development

Decision will be made after testing results.

