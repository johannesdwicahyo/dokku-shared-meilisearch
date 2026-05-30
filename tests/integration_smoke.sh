#!/usr/bin/env bash
#
# Integration smoke for shared-meilisearch. Run on a real Dokku host after
# installing the plugin. Not invoked by CI — local bats stubs can't catch the
# failure modes this verifies (perms, key scoping, docker-network DNS,
# Dokku 0.38 dispatch, quota restart).
#
# Usage: ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh

set -euo pipefail

TENANT="${TENANT:-smoke$(date +%s)}"
TENANT2="${TENANT2:-smoke$(date +%s)b}"
APP="${APP:-smokeapp$(date +%s)}"
DATA_ROOT="/var/lib/dokku/services/shared-meilisearch"
C="dokku-shared-meilisearch"

step() { printf '\n=== %s ===\n' "$1"; }

cleanup() {
  set +e
  step "cleanup"
  sudo -u dokku dokku apps:destroy "$APP" --force 2>/dev/null || true
  sudo -u dokku dokku shared-meilisearch:destroy "$TENANT" -f  2>/dev/null || true
  sudo -u dokku dokku shared-meilisearch:destroy "$TENANT2" -f 2>/dev/null || true
}
trap cleanup EXIT

# curl as a given tenant key against an index path; echoes HTTP status code.
api_status() {
  local key="$1" method="$2" path="$3" body="${4:-}"
  if [[ -n "$body" ]]; then
    docker exec -i "$C" curl -s -o /dev/null -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $key" -H "Content-Type: application/json" \
      --data "$body" "http://localhost:7700${path}"
  else
    docker exec -i "$C" curl -s -o /dev/null -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $key" "http://localhost:7700${path}"
  fi
}

step "1. plugin installed and dispatcher responds"
sudo -u dokku dokku shared-meilisearch:help | grep -q "create <name>" \
  || { echo "FAIL: :help missing 'create <name>'"; exit 1; }

step "2. data dir is dokku-owned"
[[ "$(stat -c '%U:%G' "$DATA_ROOT")" == "dokku:dokku" ]] \
  || { echo "FAIL: data dir not dokku:dokku"; exit 1; }

step "3. shared container is up"
docker ps --filter "name=^${C}$" --format '{{.Names}}' | grep -q "$C" \
  || { echo "FAIL: shared container not running"; exit 1; }

step "4. create tenant '$TENANT'"
sudo -u dokku dokku shared-meilisearch:create "$TENANT" | tee /tmp/.smoke-create
grep -q "MEILISEARCH_API_KEY=" /tmp/.smoke-create || { echo "FAIL: create didn't print key"; exit 1; }
KEY="$(grep MEILISEARCH_API_KEY= /tmp/.smoke-create | sed 's/.*=//')"

step "5. write within prefix succeeds (202); outside prefix is 403"
ok="$(api_status "$KEY" POST "/indexes/${TENANT}-products/documents" '[{"id":1,"t":"x"}]')"
[[ "$ok" == "202" ]] || { echo "FAIL: prefixed write not 202: $ok"; exit 1; }
nope="$(api_status "$KEY" POST "/indexes/other-products/documents" '[{"id":1}]')"
[[ "$nope" == "403" ]] || { echo "FAIL: out-of-prefix write not 403: $nope"; exit 1; }

step "6. cross-tenant isolation: tenant2's key cannot read tenant1's index"
sudo -u dokku dokku shared-meilisearch:create "$TENANT2" >/dev/null
KEY2="$(<"$DATA_ROOT/$TENANT2/KEY_RW")"
cross="$(api_status "$KEY2" GET "/indexes/${TENANT}-products/stats")"
[[ "$cross" == "403" ]] || { echo "FAIL: cross-tenant read not 403: $cross"; exit 1; }

step "7. link to an app sets MEILISEARCH_URL + MEILISEARCH_API_KEY"
sudo -u dokku dokku apps:create "$APP"
sudo -u dokku dokku shared-meilisearch:link "$TENANT" "$APP"
url="$(sudo -u dokku dokku config:get "$APP" MEILISEARCH_URL)"
appkey="$(sudo -u dokku dokku config:get "$APP" MEILISEARCH_API_KEY)"
[[ "$url" == "http://${C}:7700" ]] || { echo "FAIL: MEILISEARCH_URL wrong: $url"; exit 1; }
[[ -n "$appkey" ]] || { echo "FAIL: MEILISEARCH_API_KEY not set"; exit 1; }

# Sanity: the read-only key rejects writes in ALL states (independent of
# quota). This is a property check, not the quota proof.
rokey="$(<"$DATA_ROOT/$TENANT/KEY_RO")"
roblock="$(api_status "$rokey" POST "/indexes/${TENANT}-products/documents" '[{"id":99}]')"
[[ "$roblock" == "403" ]] || { echo "FAIL: read-only key allowed a write: $roblock"; exit 1; }

step "8. quota: push tenant over a 1 MB cap, sweep, assert the flip"
sudo -u dokku dokku shared-meilisearch:set-quota "$TENANT" 1
# Bulk-insert ~2 MB of documents so rawDocumentDbSize clears the 1 MB cap.
payload="$(awk 'BEGIN{printf "["; for(i=0;i<6000;i++){if(i)printf","; printf "{\"id\":%d,\"t\":\"%0*d\"}", i, 200, i} printf "]"}')"
api_status "$KEY" POST "/indexes/${TENANT}-products/documents" "$payload" >/dev/null
sleep 10   # let Meilisearch finish indexing so the size is reflected in stats
sudo -u dokku dokku shared-meilisearch:check-quotas
# The OBSERVABLE effect of the two-key model: the linked app's key was swapped
# to the stored read-only token, and info reports read-only.
appkey_ro="$(sudo -u dokku dokku config:get "$APP" MEILISEARCH_API_KEY)"
[[ "$appkey_ro" == "$rokey" ]] \
  || { echo "FAIL: over-quota didn't swap app key to read-only token"; exit 1; }
sudo -u dokku dokku shared-meilisearch:info "$TENANT" | grep -q "Read-only:.*true" \
  || { echo "FAIL: quota didn't flip read-only"; exit 1; }

step "9. lift cap and re-sweep restores the full key on the app"
rwkey="$(<"$DATA_ROOT/$TENANT/KEY_RW")"
sudo -u dokku dokku shared-meilisearch:set-quota "$TENANT" 1000
sudo -u dokku dokku shared-meilisearch:check-quotas
appkey_rw="$(sudo -u dokku dokku config:get "$APP" MEILISEARCH_API_KEY)"
[[ "$appkey_rw" == "$rwkey" ]] \
  || { echo "FAIL: release didn't restore the full key on the app"; exit 1; }
sudo -u dokku dokku shared-meilisearch:info "$TENANT" | grep -q "Read-only:.*false" \
  || { echo "FAIL: quota didn't release"; exit 1; }

step "10. list shows the tenant; destroy removes it"
sudo -u dokku dokku shared-meilisearch:list | grep -q "^$TENANT$" \
  || { echo "FAIL: list missing $TENANT"; exit 1; }
sudo -u dokku dokku shared-meilisearch:destroy "$TENANT" -f
sudo -u dokku dokku shared-meilisearch:list | grep -q "^$TENANT$" \
  && { echo "FAIL: tenant still listed after destroy"; exit 1; } || true

echo
echo "=== ALL SMOKE STEPS PASSED ==="
