#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
}

@test "json_field extracts a top-level string field" {
  json='{"uid":"abc-123","key":"tok_XYZ","name":null}'
  run json_field key "$json"
  [[ "$output" == "tok_XYZ" ]]
  run json_field uid "$json"
  [[ "$output" == "abc-123" ]]
}

@test "run_meilisearch_admin execs curl inside the container with the master key" {
  run run_meilisearch_admin GET /keys
  [[ "$status" -eq 0 ]]
  assert_stub_called_with docker "exec -i dokku-shared-meilisearch curl .* http://localhost:7700/keys"
  assert_stub_called_with docker "Authorization: Bearer master-key"
}

@test "ensure_shared_container short-circuits when container already running" {
  stub_response docker 'dokku-shared-meilisearch'
  run ensure_shared_container
  [[ "$status" -eq 0 ]]
  # Only the `docker ps` probe should have run — no `docker run`.
  run grep -c '^docker run ' "$STUB_LOG"
  [[ "$output" == "0" ]]
}

# Queue: docker ps (container up) + two POST /keys responses (full, then ro).
create_demo() {
  stub_response docker 'dokku-shared-meilisearch'
  stub_response docker '{"uid":"uid-rw","key":"key_rw_token","actions":["search"],"indexes":["demo-*"]}'
  stub_response docker '{"uid":"uid-ro","key":"key_ro_token","actions":["search"],"indexes":["demo-*"]}'
  service_create "demo"
}

@test "service_create stores both key tokens and uids" {
  create_demo
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/KEY_RW")"     == "key_rw_token" ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/KEY_RW_UID")" == "uid-rw" ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/KEY_RO")"     == "key_ro_token" ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/KEY_RO_UID")" == "uid-ro" ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/LINKS" ]]
}

@test "service_create posts two keys scoped to the tenant prefix" {
  create_demo
  posts=()
  while IFS= read -r line; do posts+=("$line"); done < <(grep 'curl .* http://localhost:7700/keys' "$STUB_LOG")
  [[ "${#posts[@]}" -eq 2 ]]
  # full key (first) carries write actions; both scope indexes to "demo-*"
  [[ "${posts[0]}" == *'"indexes":["demo-*"]'* ]]
  [[ "${posts[0]}" == *'documents.add'* ]]
  [[ "${posts[1]}" == *'"indexes":["demo-*"]'* ]]
  # read-only key (second) must NOT grant document writes
  [[ "${posts[1]}" != *'documents.add'* ]]
  [[ "${posts[1]}" == *'"search"'* ]]
}

@test "service_create refuses an existing tenant" {
  create_demo
  run service_create "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"already exists"* ]]
}

@test "service_create rejects invalid names" {
  run service_create "BadName"
  [[ "$status" -ne 0 ]]
  run service_create "has-hyphen"
  [[ "$status" -ne 0 ]]
  run service_create ""
  [[ "$status" -ne 0 ]]
}

@test "service_connection_info prints url and full key" {
  create_demo
  run service_connection_info "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"MEILISEARCH_URL=http://dokku-shared-meilisearch:7700"* ]]
  [[ "$output" == *"MEILISEARCH_API_KEY=key_rw_token"* ]]
}

@test "service_destroy deletes both keys, matching indexes, and the data dir" {
  create_demo
  : >"$STUB_LOG"
  # GET /indexes lists two demo indexes + one foreign index that must be skipped.
  stub_response docker '{"results":[{"uid":"demo-products"},{"uid":"demo-orders"},{"uid":"other-data"}]}'
  service_destroy "demo"
  [[ ! -d "$PLUGIN_DATA_ROOT/demo" ]]
  run grep -c 'curl .* -X DELETE .* http://localhost:7700/keys/uid-rw' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
  run grep -c 'curl .* -X DELETE .* http://localhost:7700/keys/uid-ro' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
  run grep -c 'http://localhost:7700/indexes/demo-products' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
  run grep -c 'http://localhost:7700/indexes/other-data' "$STUB_LOG"
  [[ "$output" == "0" ]]
}

@test "service_destroy errors when tenant is missing" {
  run service_destroy "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}
