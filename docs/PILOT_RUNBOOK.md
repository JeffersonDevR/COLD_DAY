# ColdDay Pilot Runbook (RF-PILOT-004)

Day-2 procedure to bootstrap a ColdDay pilot (5 clients + 5 technicians + 1 admin)
from a clean machine. Everything is idempotent: re-running any step is safe.

## 1. Prerequisites

- PostgreSQL 15+ with the PostGIS extension enabled on the target database:
  `CREATE EXTENSION IF NOT EXISTS postgis;`
- Backend venv: `cd backend && python -m venv .venv && .venv/bin/pip install -r requirements.txt`
- Dart/Flutter for the app (see section 5).

Database URL resolution (RF-PILOT-002): env var `COLDDAY_DATABASE_URL`
(e.g. `postgresql+asyncpg://postgres:postgres@localhost:5432/coldday`), with a
localhost fallback used when the env var is unset.

## 2. Migrations (RF-PILOT-001)

The schema is owned by Alembic (no `create_all` at startup since S6).

```bash
cd backend
.venv/bin/alembic -x url=postgresql+asyncpg://postgres:postgres@localhost:5432/coldday upgrade head
```

Notes:

- `-x url=...` must come before the subcommand; it overrides the URL for that
  invocation (useful to migrate a different environment without touching config).
- Revisions: `0001_initial_schema` (greenfield mirror of the current model
  schema) → `0002_pilot_delta_legacy_cleanup_user_fk` (drops legacy orphan
  service_requests and adds the real `service_requests.user_id` FK).
- Rollback: `.venv/bin/alembic -x url=... downgrade -1` (drops back to the
  previous revision). `downgrade base` unmigrates everything to an empty schema.
- Sanity check: `.venv/bin/alembic -x url=... check` (only the PostGIS-owned
  `spatial_ref_sys` difference is expected noise).

## 3. Seed (RF-PILOT-003)

```bash
cd backend
.venv/bin/python scripts/seed_pilot.py            # 5 clients + 5 technicians (pending) + 1 admin
.venv/bin/python scripts/seed_pilot.py            # safe: creates nothing (idempotent)
```

Credentials after seeding:

| Role | Document | Password |
|------|----------|----------|
| Admin | 1000000001 | AdminPiloto123 |
| Clients | 2000000001..05 | PilotoCold456 |
| Technicians | 3000000001..05 | PilotoCold456 |

- Technicians are created `pending` — verify them from the admin panel before
  the radar matches them (RF-AUTH-008, RF-MATCH-001).
- Technicians are located around Cúcuta (7.8939, -72.5078) so `ST_DWithin`
  radar queries have candidates.
- Reverse: `.venv/bin/python scripts/seed_pilot.py --teardown` removes exactly
  the seed documents (and their tokens/technician profiles), in FK order.

## 4. Tests

```bash
cd backend
.venv/bin/python -m pytest -m "not integration" -q   # smoke: runs WITHOUT a database
.venv/bin/python -m pytest -q                        # full suite (needs PostGIS)
```

## 5. Flutter app on a real device (RF-PILOT-004)

The app resolves the backend through the `API_URL` compile-time define:

```bash
cd cold_day_flutter
flutter run --dart-define=API_URL=http://<ip-local>:8000
```

- Same Wi-Fi: use the machine's LAN IP (`ip addr` / `ipconfig`), e.g.
  `http://192.168.1.20:8000`. The phone and the backend must be on the same
  network.
- Behind a tunnel (different network): use the tunnel URL, e.g.
  `flutter run --dart-define=API_URL=https://<tunnel-host>` (set CORS origins on
  the backend accordingly — see `app/api/main.py`/middleware).
- Start the backend first: `cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`.

Smoke path after login as admin: verify the 5 technicians from the queue, then
login as a client (2000000001) and create a request — radar should show the
verified technicians.

## 6. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `relation "users" does not exist` on seed | Migrations were not run (section 2) |
| Alembic says no version or unknown revision | `alembic -x url=... stamp 0002` only if the DB already matches head (data was migrated manually); otherwise upgrade fresh |
| Radar returns empty area | Technicians are still `pending` (verify from admin) or the request is outside the technician coverage radius |
| App gets 401 after login | Session expired (24h / 4h admin, RF-AUTH-003); login again |
| `--dart-define` ignored | Forget `flutter clean`; define is fixed at build time |