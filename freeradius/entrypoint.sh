#!/bin/sh
# Container her başladığında, .env üzerinden gelen sırları (RADIUS_SHARED_SECRET,
# VPN_RADIUS_SERVICE_SECRET) şablon dosyalarına (clients.conf.template,
# users.template) enjekte eder. Böylece secret'lar imaja/koda gömülmez,
# yalnızca docker-compose.yml'nin environment/env_file'ından gelir.
set -e

: "${RADIUS_SHARED_SECRET:?RADIUS_SHARED_SECRET tanımlı değil (.env dosyasını kontrol edin)}"
: "${VPN_RADIUS_SERVICE_SECRET:?VPN_RADIUS_SERVICE_SECRET tanımlı değil (.env dosyasını kontrol edin)}"

envsubst '${RADIUS_SHARED_SECRET}' \
    < /etc/freeradius/3.0/clients.conf.template \
    > /etc/freeradius/3.0/clients.conf

envsubst '${VPN_RADIUS_SERVICE_SECRET}' \
    < /etc/freeradius/3.0/users.template \
    > /etc/freeradius/3.0/users

chown freerad:freerad /etc/freeradius/3.0/clients.conf /etc/freeradius/3.0/users

exec "$@"
