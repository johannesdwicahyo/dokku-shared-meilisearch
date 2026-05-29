#!/usr/bin/env bats
load test_helper

setup() { setup_plugin_env; }

@test "subcommands/help prints usage with all subcommands" {
  run "$REPO_ROOT/subcommands/help" "shared-meilisearch:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-meilisearch:"* ]]
  for cmd in create destroy link unlink list info connect set-quota unset-quota check-quotas export import help; do
    [[ "$output" == *"shared-meilisearch:$cmd"* ]] || { echo "missing in help: $cmd"; return 1; }
  done
}

@test "commands dispatcher routes :help to subcommands/help" {
  run "$REPO_ROOT/commands" "shared-meilisearch:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-meilisearch:"* ]]
}

@test "help mentions the index-prefix gotcha" {
  run "$REPO_ROOT/subcommands/help" "shared-meilisearch:help"
  [[ "$output" == *"<name>-"* ]]
  [[ "$output" == *"403"* ]]
}
