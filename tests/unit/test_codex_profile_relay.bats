#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export CLI_ADAPTER_PROJECT_ROOT="$PROJECT_ROOT"
  export CLI_ADAPTER_SETTINGS="$TEST_TMP/settings.yaml"
  export CODEX_HOME="$TEST_TMP/codex_home"
  mkdir -p "$CODEX_HOME"

  cat > "$CLI_ADAPTER_SETTINGS" <<'YAML'
cli:
  agents:
    ashigaru1:
      type: codex
      profile: opencode_go
      model: ignored-by-profile
YAML

  : > "$CODEX_HOME/config.toml"
  cat > "$CODEX_HOME/opencode_go.config.toml" <<'TOML'
model = "deepseek-v4-flash"
model_provider = "opencode_go_relay"

[model_providers.opencode_go_relay]
base_url = "http://127.0.0.1:4446/v1"
env_key = "OPENCODE_GO_API_KEY"
wire_api = "responses"
TOML

  source "$PROJECT_ROOT/lib/cli_adapter.sh"
}

teardown() {
  rm -r "$TEST_TMP"
}

@test "build_cli_command uses codex profile for opencode_go relay" {
  export OPENCODE_GO_API_KEY="test-secret"

  run build_cli_command ashigaru1

  [ "$status" -eq 0 ]
  [[ "$output" == codex\ -p\ opencode_go\ --search\ --dangerously-bypass-approvals-and-sandbox\ --no-alt-screen* ]]
  [[ "$output" != *"ignored-by-profile"* ]]
  [[ "$output" != *"test-secret"* ]]
}

@test "build_cli_command fails when relay profile env key is missing" {
  unset OPENCODE_GO_API_KEY

  run build_cli_command ashigaru1

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires env var OPENCODE_GO_API_KEY"* ]]
}

@test "codex relay runbook keeps upstream key out of argv" {
  run grep -n -- "--api-key \"\\$CODEX_RELAY_API_KEY\"" "$PROJECT_ROOT/docs/codex_relay_opencode_go.md"

  [ "$status" -ne 0 ]
}
