#!/usr/bin/env bash
# Exit on error
set -o errexit

echo "Checking database connection variable..."
if [ -z "$COLDDAY_DATABASE_URL" ]; then
  echo "⚠️ ERROR: COLDDAY_DATABASE_URL is not set or empty in environment!"
else
  # Print the URL masked for security
  echo "DATABASE URL is set to: $(echo $COLDDAY_DATABASE_URL | sed 's/\/\/.*@/\/\/****:****@/')"
fi

# Run database migrations
echo "Running database migrations..."
alembic upgrade head

# Start FastAPI application
echo "Starting FastAPI server..."
uvicorn main:app --host 0.0.0.0 --port $PORT
