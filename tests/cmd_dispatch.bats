#!/usr/bin/env bats
load test_helper

setup() { setup_plugin_env; }

@test "create rejects empty name and names the command" {
  run "$REPO_ROOT/subcommands/create" "shared-meilisearch:create"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"shared-meilisearch:create"* ]]
}

@test "destroy requires -f and treats positional 1 as the tenant name" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  run "$REPO_ROOT/subcommands/destroy" "shared-meilisearch:destroy" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"refusing to destroy"* ]]
}

@test "list runs cleanly with no tenants" {
  run "$REPO_ROOT/subcommands/list" "shared-meilisearch:list"
  [[ "$status" -eq 0 ]]
}

@test "set-quota parses the mb positional" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  run "$REPO_ROOT/subcommands/set-quota" "shared-meilisearch:set-quota" "demo" "250"
  [[ "$status" -eq 0 ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "250" ]]
}

@test "info errors when tenant is missing" {
  run "$REPO_ROOT/subcommands/info" "shared-meilisearch:info" "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "export errors with stretch-goal message" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  run "$REPO_ROOT/subcommands/export" "shared-meilisearch:export" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"v0.2 stretch goal"* ]]
}

@test "commands dispatcher routes unknown subcommand to error" {
  run "$REPO_ROOT/commands" "shared-meilisearch:does-not-exist"
  [[ "$status" -ne 0 ]]
}
