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
