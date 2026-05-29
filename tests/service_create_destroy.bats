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
