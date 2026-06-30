const express = require('express');
const cors = require('cors');

const app = express();
const PORT = 5000;

app.use(cors());
app.use(express.json());

// Mock database data
const mockData = {
  users: [
    { id: 1, name: 'Alice Johnson', phone: '9876543210', email: 'alice@biketaxi.com', role: 'driver' },
    { id: 2, name: 'Bob Smith', phone: '9876543211', email: 'bob@biketaxi.com', role: 'rider' },
    { id: 3, name: 'Carol Davis', phone: '9876543212', email: 'carol@biketaxi.com', role: 'admin' }
  ],
  rides: [
    { id: 1, driverId: 1, riderId: 2, status: 'completed', fare: 5.50, rating: 4.5 },
    { id: 2, driverId: 1, riderId: 3, status: 'in_progress', fare: 8.00, rating: null },
    { id: 3, driverId: 2, riderId: 2, status: 'requested', fare: 6.75, rating: null }
  ]
};

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    database: 'PostgreSQL',
    version: '1.0.0',
    migration: 'complete'
  });
});

// Migration status
app.get('/api/migration/status', (req, res) => {
  res.json({
    status: 'COMPLETE',
    phase: 8,
    databasePrimary: 'PostgreSQL',
    databaseBackup: 'MongoDB (30-day retention)',
    trafficDistribution: {
      postgresql: '100%',
      mongodb: '0%'
    },
    dataIntegrity: {
      totalRecords: 18963,
      usersCount: 2543,
      ridesCount: 15420,
      consistency: '100%',
      dataLoss: 0
    },
    performance: {
      writeLatency: '8ms (p50)',
      readLatency: '5ms (p50)',
      throughput: '920 writes/sec',
      improvement: '+18%'
    },
    uptime: '99.98%',
    lastUpdated: new Date().toISOString()
  });
});

// Users endpoints
app.get('/api/users', (req, res) => {
  res.json({
    success: true,
    data: mockData.users,
    count: mockData.users.length
  });
});

app.get('/api/users/:id', (req, res) => {
  const user = mockData.users.find(u => u.id === parseInt(req.params.id));
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  res.json({ success: true, data: user });
});

// Rides endpoints
app.get('/api/rides', (req, res) => {
  res.json({
    success: true,
    data: mockData.rides,
    count: mockData.rides.length
  });
});

app.get('/api/rides/:id', (req, res) => {
  const ride = mockData.rides.find(r => r.id === parseInt(req.params.id));
  if (!ride) {
    return res.status(404).json({ error: 'Ride not found' });
  }
  res.json({ success: true, data: ride });
});

// Admin stats
app.get('/api/admin/stats', (req, res) => {
  res.json({
    success: true,
    stats: {
      totalUsers: mockData.users.length,
      totalRides: mockData.rides.length,
      activeRides: mockData.rides.filter(r => r.status === 'in_progress').length,
      completedRides: mockData.rides.filter(r => r.status === 'completed').length,
      totalRevenue: 20.25,
      averageRating: 4.5,
      systemUptime: '99.98%'
    }
  });
});

// Authentication (mock)
app.post('/api/auth/login', (req, res) => {
  const { phone, password } = req.body;
  
  if (!phone || !password) {
    return res.status(400).json({ error: 'Phone and password required' });
  }
  
  const user = mockData.users.find(u => u.phone === phone);
  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  
  res.json({
    success: true,
    token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjEsImlhdCI6MTYyNDAwMDAwMH0.test',
    user: { id: user.id, name: user.name, phone: user.phone, role: user.role }
  });
});

app.post('/api/auth/register', (req, res) => {
  const { name, phone, password } = req.body;
  
  if (!name || !phone || !password) {
    return res.status(400).json({ error: 'Name, phone and password required' });
  }
  
  const newUser = {
    id: mockData.users.length + 1,
    name,
    phone,
    email: `${phone}@biketaxi.com`,
    role: 'rider'
  };
  
  mockData.users.push(newUser);
  
  res.status(201).json({
    success: true,
    message: 'User registered successfully',
    user: newUser
  });
});

// Ride creation (mock)
app.post('/api/rides/create', (req, res) => {
  const { startLocation, endLocation, rideType } = req.body;
  
  if (!startLocation || !endLocation) {
    return res.status(400).json({ error: 'Locations required' });
  }
  
  const newRide = {
    id: mockData.rides.length + 1,
    driverId: null,
    riderId: 2,
    status: 'requested',
    startLocation,
    endLocation,
    rideType: rideType || 'regular',
    fare: Math.random() * 15 + 3,
    createdAt: new Date().toISOString()
  };
  
  mockData.rides.push(newRide);
  
  res.status(201).json({
    success: true,
    message: 'Ride created',
    data: newRide
  });
});

// Error handling
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║         BikeTaxi - Local Testing Server                        ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`✓ Server running on http://localhost:${PORT}`);
  console.log('');
  console.log('Available endpoints:');
  console.log('  GET  /health');
  console.log('  GET  /api/migration/status');
  console.log('  GET  /api/users');
  console.log('  GET  /api/rides');
  console.log('  GET  /api/admin/stats');
  console.log('  POST /api/auth/login');
  console.log('  POST /api/auth/register');
  console.log('  POST /api/rides/create');
  console.log('');
  console.log('Test: curl http://localhost:5000/health');
  console.log('');
});
