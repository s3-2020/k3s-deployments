#!/usr/bin/env bash
# wp-admin-lock.sh — slå BasicAuth-låsen på et dev-sites admin-stier til/fra.
#
# Brug:  ./scripts/wp-admin-lock.sh <site> <on|off>
# Fx:    ./scripts/wp-admin-lock.sh markhaven off
#
# Kræver: git + push-adgang til k3s-deployments. Flux synker inden for ~10 min
# (eller trig reconcile manuelt: kubectl annotate kustomization deployments
# -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite).
#
# Låsen beskytter /wp-login.php, /wp-admin og /xmlrpc.php med BasicAuth.
# Credentials ligger i secret <site>-admin-auth i namespace dev.

set -euo pipefail

site="${1:?brug: wp-admin-lock.sh <site> <on|off>}"
state="${2:?brug: wp-admin-lock.sh <site> <on|off>}"
[[ "$state" == "on" || "$state" == "off" ]] || { echo "tilstand skal være on eller off"; exit 1; }

cd "$(dirname "$0")/.."
kfile="apps/dev/kustomization.yaml"
entry="  - ${site}-adminroute.yaml"

if [[ "$state" == "on" ]]; then
  if grep -qF "$entry" "$kfile"; then
    echo "Lås for '$site' er allerede slået til."
    exit 0
  fi
  sed -i "s|^#  - ${site}-adminroute.yaml$|$entry|" "$kfile"
  action="aktiveret"
else
  if ! grep -qF "$entry" "$kfile"; then
    echo "Lås for '$site' er allerede slået fra."
    exit 0
  fi
  sed -i "s|^$entry$|#  - ${site}-adminroute.yaml|" "$kfile"
  action="deaktiveret"
fi

git add "$kfile"
git commit -q -m "wp-admin-lock: ${site} ${state}" \
  && git push -q origin main \
  || { echo "ADVARSEL: commit/push fejlede — tjek git-status"; exit 1; }

echo "BasicAuth-lås for '$site' ${action}. Flux synker om et øjeblik."
