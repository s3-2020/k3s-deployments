#!/usr/bin/env bash
# wp-admin-passwd.sh — sæt ny BasicAuth-adgangskode på admin-låsen for dev-WP-sites.
#
# Brug:  ./scripts/wp-admin-passwd.sh <site> [<site2> ...]
# Fx:    ./scripts/wp-admin-passwd.sh usv markhaven
#
# Kræver: kubectl mod clusteret + openssl (kør fx på jmp).
#
# Opdaterer secret <site>-admin-auth (ns dev) med en ny htpasswd-post.
# Traefik tager den nye kode i brug straks — ingen genstart, ingen Flux-push
# (secreten er out-of-band pr. husreglen om hemmelige værdier).
#
# OBS: koden deles IKKE automatisk mellem sites — giv alle sites som
# argumenter for at holde dem synkroniseret (fx usv + markhaven).
#
# Relateret: scripts/wp-admin-lock.sh <site> <on|off> slår selve låsen til/fra.

set -euo pipefail

user="${WP_ADMIN_USER:-jsh}"

[ $# -ge 1 ] || { echo "brug: wp-admin-passwd.sh <site> [<site2> ...]"; exit 1; }

read -rs -p "Ny adgangskode: " pw1; echo
read -rs -p "Gentag adgangskode: " pw2; echo
[ -n "$pw1" ] || { echo "tom adgangskode er ikke tilladt"; exit 1; }
[ "$pw1" = "$pw2" ] || { echo "adgangskoderne matcher ikke"; exit 1; }

hash=$(openssl passwd -apr1 "$pw1")
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s:%s\n' "$user" "$hash" > "$tmp"

for site in "$@"; do
  kubectl -n dev create secret generic "${site}-admin-auth" \
    --from-file="users=$tmp" --dry-run=client -o yaml | kubectl apply -f -
  echo "→ ${site}-admin-auth opdateret (bruger: $user)"
done

echo "Færdig — den nye kode gælder straks for: $*"
