#!/usr/bin/env bash
# ============================================================
# Cold Day — Setup PostgreSQL + PostGIS en CachyOS (Arch-based)
# Uso: chmod +x setup_db_cachyos.sh && ./setup_db_cachyos.sh
# ============================================================
set -euo pipefail

DB_USER="postgres"
DB_PASS="postgres"
DB_NAME="coldday"
PG_DATA="/var/lib/postgres/data"

echo "==> [1/5] Instalando PostgreSQL y PostGIS (pacman)"
sudo pacman -S --needed --noconfirm postgresql postgis

echo "==> [2/5] Inicializando el clúster de datos (si hace falta)"
if [ ! -d "$PG_DATA/base" ]; then
    sudo -u postgres initdb --locale C.UTF-8 -E UTF8 -D "$PG_DATA"
    echo "    Clúster inicializado en $PG_DATA"
else
    echo "    Clúster ya existe, se omite initdb"
fi

echo "==> [3/5] Habilitando y arrancando el servicio"
sudo systemctl enable --now postgresql
sudo systemctl restart postgresql

echo "==> [4/5] Creando usuario y base de datos"
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';
SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec
SQL

echo "==> [5/5] Activando la extensión PostGIS"
sudo -u postgres psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<SQL
CREATE EXTENSION IF NOT EXISTS postgis;
SELECT PostGIS_Version();
SQL

echo ""
echo "✅ Listo. Conexión esperada por el backend:"
echo "   postgresql+asyncpg://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
echo "   Para probar: cd backend && uvicorn main:app --reload"
