#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'key_rw_token' >"$PLUGIN_DATA_ROOT/demo/KEY_RW"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
}

@test "service_link sets MEILISEARCH_URL and MEILISEARCH_API_KEY on the app" {
  service_link "demo" "myapp"
  assert_stub_called_with dokku "config:set --no-restart myapp MEILISEARCH_URL=http://dokku-shared-meilisearch:7700 MEILISEARCH_API_KEY=key_rw_token"
}

@test "service_link records the app in LINKS" {
  service_link "demo" "myapp"
  run cat "$PLUGIN_DATA_ROOT/demo/LINKS"
  [[ "$output" == "myapp" ]]
}

@test "service_link is idempotent (no duplicate LINKS entries)" {
  service_link "demo" "myapp"
  service_link "demo" "myapp"
  run grep -c '^myapp$' "$PLUGIN_DATA_ROOT/demo/LINKS"
  [[ "$output" == "1" ]]
}

@test "service_link errors when tenant missing or app empty" {
  run service_link "ghost" "myapp"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
  run service_link "demo" ""
  [[ "$status" -ne 0 ]]
}

@test "service_unlink unsets both env vars and drops the LINKS entry" {
  printf 'myapp\nother\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  service_unlink "demo" "myapp"
  assert_stub_called_with dokku "config:unset --no-restart myapp MEILISEARCH_URL MEILISEARCH_API_KEY"
  run cat "$PLUGIN_DATA_ROOT/demo/LINKS"
  [[ "$output" == "other" ]]
}

@test "service_unlink is a no-op for an app that was never linked" {
  printf 'other\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  service_unlink "demo" "never-linked"
  run cat "$PLUGIN_DATA_ROOT/demo/LINKS"
  [[ "$output" == "other" ]]
}
