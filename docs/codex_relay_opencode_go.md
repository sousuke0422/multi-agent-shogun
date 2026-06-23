# Codex Relay for opencode-go

This runbook wires Codex CLI to opencode-go through a local `codex-relay` sidecar:

```text
codex -p opencode_go -> http://127.0.0.1:4446/v1/responses -> opencode-go /v1/chat/completions
```

## Shogun Settings

`config/settings.yaml` stays a routing file only. Assign the Codex profile name to the agent:

```yaml
cli:
  agents:
    ashigaru1:
      type: codex
      profile: opencode_go
```

Do not put endpoint URLs, relay process flags, or API keys in `config/settings.yaml`.

## Codex Profile

Copy the tracked secret-free template:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}"
cp config/codex-opencode-go.config.toml.sample "${CODEX_HOME:-$HOME/.codex}/opencode_go.config.toml"
```

The profile intentionally uses `wire_api = "responses"` and points Codex at the local relay:

```toml
model = "deepseek-v4-flash"
model_provider = "opencode_go_relay"

[model_providers.opencode_go_relay]
base_url = "http://127.0.0.1:4446/v1"
env_key = "OPENCODE_GO_API_KEY"
wire_api = "responses"
```

## Relay Environment

Run `codex-relay` as an operator-owned sidecar. Keep it on loopback and keep the upstream key in the process environment. Do not pass the key with `--api-key`, because command-line arguments are visible in process listings.

```bash
export OPENCODE_GO_API_KEY=...
export CODEX_RELAY_PORT=4446
export CODEX_RELAY_UPSTREAM=https://opencode.ai/zen/go/v1
export CODEX_RELAY_API_KEY="$OPENCODE_GO_API_KEY"
codex-relay
```

`codex-relay --help` confirms `--port`, `--upstream`, and `--api-key` each have matching `CODEX_RELAY_*` environment variables. Prefer those variables for long-running relay processes so `ps` output contains no upstream key.

Use the model ids returned by `curl http://127.0.0.1:4446/v1/models`. If your installed relay version supports `CODEX_RELAY_MODEL_MAP`, map explicitly instead of changing Shogun routing semantics:

```bash
export CODEX_RELAY_MODEL_MAP=opencode-go/deepseek-v4-flash:deepseek-v4-flash
codex-relay
```

Relay history and debug logs are sensitive. Do not commit `.env`, relay history, prompts, tool arguments, or API keys.

## Smoke Checks

1. `codex-relay --help` prints `--upstream`, `--api-key`, and `--print-config`.
2. `OPENCODE_GO_API_KEY` is present in the shell that starts Codex, and `CODEX_RELAY_API_KEY` is present in the shell that starts the relay.
3. `ps -p <relay_pid> -o args=` shows `codex-relay` without an API key value.
4. `curl http://127.0.0.1:4446/v1/models` returns opencode-go models.
5. `codex -p opencode_go "Reply exactly OK"` completes through the relay.
6. A streaming prompt completes without stalling.
7. A harmless local tool-call task completes without leaking prompt or tool data to relay logs.
