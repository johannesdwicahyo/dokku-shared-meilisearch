#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'key_rw_token' >"$PLUGIN_DATA_ROOT/demo/KEY_RW"
  printf 'key_ro_token' >"$PLUGIN_DATA_ROOT/demo/KEY_RO"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
}

@test "service_get_quota_mb returns default when no override" {
  run service_get_quota_mb "demo"
  [[ "$output" == "100" ]]
}

@test "service_set_quota writes a positive integer" {
  service_set_quota "demo" "250"
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "250" ]]
}

@test "service_set_quota rejects non-numeric / zero / negative / empty" {
  run service_set_quota "demo" "huge"; [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "0";    [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "-5";   [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "";     [[ "$status" -ne 0 ]]
}

@test "service_unset_quota removes the override file" {
  printf '250' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  service_unset_quota "demo"
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_MB" ]]
}

# tenant_usage makes: GET /indexes, then GET /indexes/<uid>/stats per match.
# Queue one /indexes listing + one stats blob per matching index.
@test "tenant_usage returns 0 0 for a tenant with no indexes" {
  stub_response docker '{"results":[]}'
  run tenant_usage "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "0 0" ]]
}

@test "tenant_usage sums rawDocumentDbSize over matching indexes only" {
  stub_response docker '{"results":[{"uid":"demo-a"},{"uid":"demo-b"},{"uid":"other-c"}]}'
  stub_response docker '{"numberOfDocuments":3,"rawDocumentDbSize":1000,"isIndexing":false}'
  stub_response docker '{"numberOfDocuments":2,"rawDocumentDbSize":2000,"isIndexing":false}'
  run tenant_usage "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "2 3000" ]]
}

@test "service_check_quota flips to read-only and restarts links when over cap" {
  printf 'myapp\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  printf '1' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"     # 1 MB cap
  stub_response docker '{"results":[{"uid":"demo-a"}]}'
  stub_response docker '{"numberOfDocuments":1,"rawDocumentDbSize":2097152}'  # 2 MB
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"flipped"* ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
  # App restarted onto the read-only key (config:set WITHOUT --no-restart).
  assert_stub_called_with dokku "config:set myapp MEILISEARCH_API_KEY=key_ro_token"
}

@test "service_check_quota releases only below the hysteresis threshold (90%)" {
  printf 'myapp\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"    # 10 MB cap; 90% = 9 MB
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  # 9.5 MB: under cap but above 90% -> stay violated, silent.
  stub_response docker '{"results":[{"uid":"demo-a"}]}'
  stub_response docker '{"numberOfDocuments":1,"rawDocumentDbSize":9961472}'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
}

@test "service_check_quota releases and restores full key when well under cap" {
  printf 'myapp\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  # 5 MB: comfortably under 90% -> release.
  stub_response docker '{"results":[{"uid":"demo-a"}]}'
  stub_response docker '{"numberOfDocuments":1,"rawDocumentDbSize":5242880}'
  run service_check_quota "demo"
  [[ "$output" == *"released"* ]]
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
  assert_stub_called_with dokku "config:set myapp MEILISEARCH_API_KEY=key_rw_token"
}

@test "service_check_quota is silent when under cap and not flagged" {
  printf '100' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  stub_response docker '{"results":[{"uid":"demo-a"}]}'
  stub_response docker '{"numberOfDocuments":1,"rawDocumentDbSize":1024}'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}
