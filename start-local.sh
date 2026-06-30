#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       BikeTaxi - Local Testing Server Startup                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Navigate to backend directory
cd "$(dirname "$0")/backend"

echo "Checking dependencies..."
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install --legacy-peer-deps
fi

echo ""
echo "Starting Demo Server..."
echo ""

# Run from backend directory so it has access to node_modules
node ../demo-server.js

# If server fails, show error
if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Failed to start server"
    echo ""
    echo "Troubleshooting:"
    echo "1. Make sure you're in /vercel/share/v0-project directory"
    echo "2. Try: npm install --legacy-peer-deps in backend directory"
    echo "3. Check: http://localhost:5000/health after startup"
    exit 1
fi
