#!/bin/bash

# Complete Member GraphQL Setup Script
# Run this script once Docker connectivity is resolved

echo "🚀 Starting Member GraphQL API Setup..."
echo "========================================"

# Step 1: Start GraphQL Container
echo "1. Starting GraphQL Container..."
./commands/docker-start.sh member development
if [ $? -ne 0 ]; then
    echo "❌ Failed to start GraphQL container"
    exit 1
fi

# Step 2: Wait for container to be ready
echo "2. Waiting for container to be ready..."
sleep 10

# Step 3: Track all tables
echo "3. Tracking all 33 database tables..."
./commands/track-all-tables.sh member development
if [ $? -ne 0 ]; then
    echo "❌ Failed to track tables"
    exit 1
fi

# Step 4: Track relationships
echo "4. Tracking all 24 foreign key relationships..."
./commands/track-relationships.sh member development
if [ $? -ne 0 ]; then
    echo "❌ Failed to track relationships"
    exit 1
fi

# Step 5: Verify complete setup
echo "5. Verifying complete setup..."
./commands/verify-complete-setup.sh member development
if [ $? -ne 0 ]; then
    echo "❌ Setup verification failed"
    exit 1
fi

# Step 6: Test connectivity
echo "6. Testing GraphQL connectivity..."
./commands/test-connections.sh member development
if [ $? -ne 0 ]; then
    echo "❌ Connectivity test failed"
    exit 1
fi

echo ""
echo "✅ Member GraphQL API setup completed successfully!"
echo "📡 GraphQL endpoint: http://localhost:8102/v1/graphql"
echo "🔧 Admin console: http://localhost:8102/console"
echo "🔑 Admin secret: CCTech2024Member"
echo ""
echo "📊 Database Summary:"
echo "   - 33 tables across 9 schemas"
echo "   - 24 foreign key relationships"
echo "   - Full GraphQL introspection enabled"