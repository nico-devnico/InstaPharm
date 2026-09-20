#!/usr/bin/env sh
# Génère un fichier de vitesses pour osrm-customize.
#
# En production : remplacer ce script par un connecteur vers votre flux
# (GPS livreurs, API TomTom/HERE, capteurs urbains, etc.) produisant :
#   from_osm_node_id,to_osm_node_id,speed_km_h
#
# Ici : fichier d’exemple + modulation horaire (pics Douala/Yaoundé).
set -eu

OUT="${1:-./data/traffic_speeds.csv}"
HOUR="$(date -u +%H | sed 's/^0//')"
# Pics matin 7–9 et soir 17–19 (UTC+1 ≈ heure Cameroun proche)
FACTOR="1.0"
case "$HOUR" in
  6|7|8|16|17|18) FACTOR="0.45" ;;  # bouchons
  9|10|15|19) FACTOR="0.65" ;;      # ralentissements
  *) FACTOR="0.9" ;;
esac

# Si un fichier de corridors partenaires existe, on module ses vitesses.
BASE="$(dirname "$OUT")/traffic_base.csv"
mkdir -p "$(dirname "$OUT")"

if [ -f "$BASE" ]; then
  echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ) factor=$FACTOR" > "$OUT"
  # CSV: from,to,speed → speed * factor (min 5 km/h)
  awk -F',' -v f="$FACTOR" '
    /^#/ || NF < 3 { next }
    {
      speed = $3 * f
      if (speed < 5) speed = 5
      printf "%s,%s,%.1f\n", $1, $2, speed
    }
  ' "$BASE" >> "$OUT"
  echo "Écrit $OUT depuis traffic_base.csv (facteur $FACTOR)"
else
  # Placeholder : customize sans arêtes = poids profil car.lua
  # Créez traffic_base.csv avec des paires de nœuds OSM Cameroun.
  cat > "$OUT" <<EOF
# Placeholder — ajoutez des arêtes OSM (from,to,speed_kmh) dans traffic_base.csv
# Exemple (à remplacer par de vrais node ids extraits de votre graphe) :
# 123456789,123456790,12.0
EOF
  echo "Aucun traffic_base.csv — $OUT placeholder (customize standard)"
fi
