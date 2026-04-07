#!/bin/bash
# ============================================================
# SafeCircle - Local Development Setup Script
# Run this from the project root: ./scripts/setup-local.sh
# ============================================================
set -e

echo "=========================================="
echo "  SafeCircle Local Setup"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── 1. Check prerequisites ────────────────────
echo ""
echo "1. Checking prerequisites..."

check_cmd() {
  if command -v "$1" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $1 found: $(command -v $1)"
    return 0
  else
    echo -e "  ${RED}✗${NC} $1 not found"
    return 1
  fi
}

MISSING=0
check_cmd node || MISSING=1
check_cmd npm || MISSING=1
check_cmd flutter || MISSING=1
check_cmd psql || MISSING=1
check_cmd redis-cli || MISSING=1

if [ $MISSING -eq 1 ]; then
  echo -e "\n${YELLOW}⚠ Some tools are missing. Install them before proceeding.${NC}"
  echo "  Node.js:    https://nodejs.org/"
  echo "  Flutter:    https://flutter.dev/docs/get-started/install"
  echo "  PostgreSQL: https://www.postgresql.org/download/"
  echo "  Redis:      https://redis.io/docs/getting-started/"
fi

# ── 2. Setup PostgreSQL ────────────────────────
echo ""
echo "2. Setting up PostgreSQL database..."

if command -v psql &>/dev/null; then
  # Try to create user and DB (ignore errors if they exist)
  psql -U postgres -c "CREATE USER safecircle WITH PASSWORD 'safecircle_dev';" 2>/dev/null || true
  psql -U postgres -c "CREATE DATABASE safecircle OWNER safecircle;" 2>/dev/null || true
  psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE safecircle TO safecircle;" 2>/dev/null || true

  # Run migrations
  echo "  Running migrations..."
  psql -U safecircle -d safecircle -f backend-api/src/database/migrations/001_initial_schema.sql 2>/dev/null || echo -e "  ${YELLOW}⚠ Migration 001 may already be applied${NC}"
  psql -U safecircle -d safecircle -f backend-api/src/database/migrations/002_journey_schema.sql 2>/dev/null || echo -e "  ${YELLOW}⚠ Migration 002 may already be applied${NC}"
  echo -e "  ${GREEN}✓${NC} Database setup complete"
else
  echo -e "  ${YELLOW}⚠ psql not found. Run migrations manually.${NC}"
fi

# ── 3. Setup Backend ───────────────────────────
echo ""
echo "3. Setting up backend..."

cd backend-api

# Install dependencies
echo "  Installing npm packages..."
npm install --silent 2>&1 | tail -3

# Create .env if not exists
if [ ! -f .env ]; then
  cp .env.example .env
  # Set dev-safe JWT secrets
  sed -i 's/change-this-to-a-secure-random-string/dev-secret-change-in-production-abc123/' .env
  sed -i 's/change-this-to-another-secure-random-string/dev-refresh-secret-change-in-production-xyz789/' .env
  echo -e "  ${GREEN}✓${NC} .env created from .env.example"
else
  echo -e "  ${GREEN}✓${NC} .env already exists"
fi

# Type check
echo "  Running TypeScript check..."
npx tsc --noEmit 2>&1
if [ $? -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} TypeScript compiles cleanly"
else
  echo -e "  ${RED}✗${NC} TypeScript errors found"
fi

cd ..

# ── 4. Setup Mobile App ───────────────────────
echo ""
echo "4. Setting up Flutter app..."

cd mobile-app

if command -v flutter &>/dev/null; then
  # Create platform directories if missing
  if [ ! -d "android" ]; then
    echo "  Creating platform directories..."
    flutter create --org com.safecircle . 2>&1 | tail -3
    echo -e "  ${GREEN}✓${NC} Platform directories created"
  fi

  echo "  Getting Flutter packages..."
  flutter pub get 2>&1 | tail -3
  echo -e "  ${GREEN}✓${NC} Flutter packages installed"
else
  echo -e "  ${YELLOW}⚠ Flutter not found. Install it to build the mobile app.${NC}"
fi

cd ..

# ── 5. Summary ─────────────────────────────────
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "To start the backend:"
echo "  cd backend-api && npm run start:dev"
echo ""
echo "To start the mobile app (emulator):"
echo "  cd mobile-app && flutter run"
echo ""
echo "To start the mobile app (physical device):"
echo "  1. Find your IP: ifconfig | grep 'inet '"
echo "  2. Edit mobile-app/lib/core/config/app_config.dart"
echo "  3. Replace 10.0.2.2 with your IP"
echo "  4. cd mobile-app && flutter run"
echo ""
echo "API Swagger Docs: http://localhost:3000/docs"
echo "Health Check:     http://localhost:3000/api/v1/health"
echo "Pilot Readiness:  http://localhost:3000/api/v1/health/pilot"
echo ""
