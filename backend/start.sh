#!/usr/bin/env bash
# Exit on error
set -o errexit

# Run database migrations
echo "Running database migrations..."
alembic upgrade head

# Start FastAPI application
echo "Starting FastAPI server..."
uvicorn main:app --host 0.0.0.0 --port $PORT
