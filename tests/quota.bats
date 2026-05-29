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
