#!/usr/bin/env bash
# Exit on error
set -o errexit

echo "Checking database connection variable..."
if [ -z "$COLDDAY_DATABASE_URL" ]; then
  echo "⚠️ ERROR: COLDDAY_DATABASE_URL is not set or empty!"
  exit 1
fi

echo "DATABASE URL is set to: $(echo $COLDDAY_DATABASE_URL | sed 's/\/\/.*@/\/\/****:****@/')"

# Enable PostGIS extension
echo "Enabling PostGIS extension in database..."
python -c "
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy import text

async def enable_postgis():
    engine = create_async_engine('$COLDDAY_DATABASE_URL')
    async with engine.begin() as conn:
        await conn.execute(text('CREATE EXTENSION IF NOT EXISTS postgis;'))
    await engine.dispose()
    print('PostGIS extension verified/enabled.')

asyncio.run(enable_postgis())
"

# Run database migrations
echo "Running database migrations..."
alembic upgrade head

# Run Seeding Script to create default users
echo "Running seed_pilot.py to create pre-made users..."
python scripts/seed_pilot.py

# Start FastAPI application
echo "Starting FastAPI server..."
uvicorn main:app --host 0.0.0.0 --port $PORT
