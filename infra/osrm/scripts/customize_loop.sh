#!/usr/bin/env sh
# Boucle trafic temps réel → osrm-customize (répété toutes les X minutes)
#
# Format attendu (OSRM segment-speed-file) :
#   from_node_id,to_node_id,speed_kmh
#
# Remplacez generate_traffic_csv.sh par votre connecteur GPS / API trafic.
set -eu

DATA_DIR="${DATA_DIR:-/data}"
INTERVAL_MIN="${TRAFFIC_INTERVAL_MIN:-5}"
OSRM="$DATA_DIR/cameroon-latest.osrm"
SPEED_FILE="$DATA_DIR/traffic_speeds.csv"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

echo "Trafic customize loop — intervalle ${INTERVAL_MIN} min"

while true; do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) → génération flux trafic"

  if [ -x "$SCRIPT_DIR/generate_traffic_csv.sh" ]; then
    sh "$SCRIPT_DIR/generate_traffic_csv.sh" "$SPEED_FILE" || true
  elif [ -f "$SCRIPT_DIR/generate_traffic_csv.sh" ]; then
    sh "$SCRIPT_DIR/generate_traffic_csv.sh" "$SPEED_FILE" || true
  fi

  if [ -f "$SPEED_FILE" ] && [ -s "$SPEED_FILE" ]; then
    echo "    osrm-customize --segment-speed-file"
    osrm-customize "$OSRM" --segment-speed-file "$SPEED_FILE" || \
      osrm-customize "$OSRM" || true
  else
    echo "    Pas de CSV trafic — customize poids standards"
    osrm-customize "$OSRM" || true
  fi

  # osrm-routed recharge les fichiers .osrm* au prochain accès mémoire-mappés
  # (redémarrage optionnel si votre déploiement le nécessite)
  echo "    customize OK — prochaine passe dans ${INTERVAL_MIN} min"
  sleep $((INTERVAL_MIN * 60))
done
