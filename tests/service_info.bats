#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
}

@test "validate_name accepts good names, rejects bad" {
  run validate_name "good_name"
  [[ "$status" -eq 0 ]]
  run validate_name "BadName"
  [[ "$status" -ne 0 ]]
  run validate_name "has-hyphen"
  [[ "$status" -ne 0 ]]
  run validate_name ""
  [[ "$status" -ne 0 ]]
  run validate_name "with space"
  [[ "$status" -ne 0 ]]
}

@test "service_list lists tenants alphabetically and skips _internal" {
  mkdir -p "$PLUGIN_DATA_ROOT/zeta" "$PLUGIN_DATA_ROOT/alpha" "$PLUGIN_DATA_ROOT/_meilidata"
  run service_list
  [[ "$status" -eq 0 ]]
  lines=()
  while IFS= read -r l; do lines+=("$l"); done <<< "$output"
  [[ "${lines[0]}" == "alpha" ]]
  [[ "${lines[1]}" == "zeta" ]]
  for l in "${lines[@]}"; do
    [[ "$l" != "_meilidata" ]] || { echo "_meilidata leaked into list"; return 1; }
  done
}

@test "service_info prints all fields including quota default" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  stub_response docker '{"results":[{"uid":"demo-a"}]}'
  stub_response docker '{"numberOfDocuments":3,"rawDocumentDbSize":32768}'
  run service_info "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"name=demo"* ]]
  [[ "$output" == *"index_prefix=demo-"* ]]
  [[ "$output" == *"host=dokku-shared-meilisearch"* ]]
  [[ "$output" == *"port=7700"* ]]
  [[ "$output" == *"index_count=1"* ]]
  [[ "$output" == *"memory_bytes=32768"* ]]
  [[ "$output" == *"quota_mb=100"* ]]
  [[ "$output" == *"read_only=false"* ]]
}

@test "service_info reports read_only=true when marker present and links csv" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'app1\napp2\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker '{"results":[]}'
  run service_info "demo"
  [[ "$output" == *"read_only=true"* ]]
  [[ "$output" == *"linked_apps=app1,app2"* ]]
}

@test "service_info errors when tenant is missing" {
  run service_info "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}
