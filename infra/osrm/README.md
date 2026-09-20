# InstaPharm — OSRM MLD + trafic temps réel
#
# Pipeline
# --------
# ```
# [Données OpenStreetMap] → osrm-extract → osrm-partition   (1×)
#                                    |
# [Flux Trafic Temps Réel] ──→ osrm-customize               (toutes les X min)
#                                    |
#                            osrm-routed --algorithm mld
#                                    |
#                            App Flutter (annotations → bouchons)
# ```
#
# Démarrage rapide
# ----------------
# ```bash
# cd infra/osrm
# chmod +x scripts/*.sh
# ./scripts/build_mld.sh      # long (~10–30 min selon machine)
# docker compose up -d
# ```
#
# Dans `.env` du projet Flutter :
# ```
# OSRM_BASE_URL=http://localhost:5000
# OSRM_TRAFFIC_REFRESH_MINUTES=5
# ```
#
# Sur émulateur Android, `localhost` = `10.0.2.2`.
# Sur appareil physique, utilisez l’IP LAN de la machine Docker.
#
# Trafic réel
# -----------
# 1. Produisez `data/traffic_base.csv` : `from_node,to_node,speed_kmh`
#    (IDs de nœuds OSM du graphe Cameroun).
# 2. `generate_traffic_csv.sh` module les vitesses selon l’heure (pics).
# 3. `customize_loop.sh` appelle `osrm-customize --segment-speed-file`.
#
# Côté app
# --------
# `RoutingService` demande `annotations=duration,distance`, calcule la vitesse
# par segment et colore l’itinéraire :
# - vert = fluide
# - orange = ralentissement
# - rouge / bordeaux = bouchon
#
# Sans moteur custom, l’app utilise `https://router.project-osrm.org`
# (pas de customize, mais détection relative via annotations).
