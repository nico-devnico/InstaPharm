#!/usr/bin/env sh
# Build MLD une seule fois : OSM → extract → partition (+ customize initial)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/data"
mkdir -p "$DATA"

PBF_URL="${PBF_URL:-https://download.geofabrik.de/africa/cameroon-latest.osm.pbf}"
PBF="$DATA/cameroon-latest.osm.pbf"

echo "==> [1/4] Téléchargement OSM Cameroun"
if [ ! -f "$PBF" ]; then
  curl -L --fail -o "$PBF" "$PBF_URL"
else
  echo "    PBF déjà présent : $PBF"
fi

echo "==> [2/4] osrm-extract (car profile)"
docker run --rm -t -v "$DATA:/data" ghcr.io/project-osrm/osrm-backend:latest \
  osrm-extract -p /opt/car.lua /data/cameroon-latest.osm.pbf

echo "==> [3/4] osrm-partition (MLD — une seule fois)"
docker run --rm -t -v "$DATA:/data" ghcr.io/project-osrm/osrm-backend:latest \
  osrm-partition /data/cameroon-latest.osrm

echo "==> [4/4] osrm-customize initial (poids par défaut)"
docker run --rm -t -v "$DATA:/data" ghcr.io/project-osrm/osrm-backend:latest \
  osrm-customize /data/cameroon-latest.osrm

echo ""
echo "MLD prêt. Démarrez le moteur :"
echo "  cd $ROOT && docker compose up -d"
echo "Puis branchez l’app :"
echo "  OSRM_BASE_URL=http://localhost:5000"
