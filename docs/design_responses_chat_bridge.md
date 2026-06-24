# Responses to Chat Completions Bridge Design

## Purpose

`cmd_359` defines how to run opencode-go through Codex CLI after Codex removes practical `wire_api = "chat"` support. The target path is:

```text
Codex CLI (`codex -p opencode_go`)
  -> local bridge `/v1/responses`
  -> opencode-go OpenAI-compatible `/v1/chat/completions`
```

This is a design-only phase. It does not install a bridge, change secrets, or start a long-running service.

## Constraints

- Use an existing bridge. Do not build an in-house protocol translator in this phase.
- Do not use LiteLLM.
- Keep Codex profile configuration as the source of truth for Codex endpoint selection.
- Keep API keys in environment variables only.
- Preserve upstream model ids by default; use explicit model mapping only when an upstream requires an alias.
- The bridge must support streaming SSE and function/tool calls.
- The bridge must allow an arbitrary upstream `base_url`, because opencode-go is not a hard-coded public provider preset.

## Current State

`cmd_358` established that Shogun-side YAML should only assign a Codex profile name to an agent. The endpoint details belong in Codex TOML, launched as:

```bash
codex -p opencode_go
```

For `cmd_359`, the profile must continue to use `wire_api = "responses"` and point at a local bridge. The bridge is responsible for translating Codex's Responses-shaped requests into the upstream Chat Completions API.

## Source Notes

- OpenAI Codex discussion #7782 documents the migration pressure away from `chat/completions` and includes a working bridge pattern: Codex sends `/v1/responses`, a local API bridge maps to `/v1/chat/completions`, and streaming chunks are mapped back to Responses SSE events. It also calls out function tool calls and DeepSeek-style `reasoning_content` replay as relevant edge cases. Source: https://github.com/openai/codex/discussions/7782
- LiteLLM documents a `/responses` to `/chat/completions` bridge, including an opt-in mode for custom OpenAI-compatible endpoints, but LiteLLM is explicitly out of scope for this task. Source: https://docs.litellm.ai/docs/response_api
- `MetaFARS/codex-relay` is a Rust bridge for Codex CLI that accepts an arbitrary upstream Chat Completions base URL, supports streaming, tool calls, model catalog proxying, model mapping, and config generation with model metadata. Source: https://github.com/MetaFARS/codex-relay
- `wujfeng712-ui/codex-bridge` is a single-file, zero-dependency Node proxy for Codex CLI to Chat Completions backends. It supports streaming, tool calls, thinking round trips, and session continuity, but it is more provider-preset oriented and includes a built-in `web_fetch` tool. Source: https://github.com/wujfeng712-ui/codex-bridge
- `va-ai-api-bridge` provides Rust translation primitives and is intentionally not an HTTP gateway; it does not own networking, credentials, routing, retry, or history. Source: https://github.com/jazzenchen/va-ai-api-bridge

## Candidate Evaluation

| Candidate | Fit | Decision |
| --- | --- | --- |
| `MetaFARS/codex-relay` | Direct Codex Responses -> upstream Chat Completions bridge; arbitrary `CODEX_RELAY_UPSTREAM`; `CODEX_RELAY_MODEL_MAP`; streaming and tool-call debug logs; model metadata generation. | Adopt for phase 2 pilot. |
| `wujfeng712-ui/codex-bridge` | Minimal runtime footprint and no npm install, but provider routing is model-name/preset oriented and built-in `web_fetch` adds a boundary that Shogun should not expose by default. | Keep as fallback if Rust relay is rejected. |
| `va-ai-api-bridge` | Strong protocol translation library, but not a runnable gateway. It would require us to build the HTTP host, auth, routing, and lifecycle around it. | Defer; use only if a later task approves owning a bridge wrapper. |
| `codex-proxy` family | Several projects target ChatGPT OAuth/Codex backend reuse or opposite direction APIs. These do not match "Codex client -> opencode-go Chat Completions" cleanly. | Reject for this phase. |
| LiteLLM | Technically capable, but task constraint says no. It also has active bridge edge-case issues around streaming tool calls in public issue traffic. | Reject. |

## Selected Design

Use `codex-relay` as a local sidecar process. Codex sees a local OpenAI Responses endpoint; opencode-go sees normal OpenAI-compatible Chat Completions traffic.

```text
ashigaru1 settings.yaml
  cli.agents.ashigaru1.profile = opencode_go

Codex profile: $CODEX_HOME/opencode_go.config.toml
  model = "deepseek-v4-flash"
  model_provider = "opencode_go_relay"
  base_url = "http://127.0.0.1:4446/v1"
  wire_api = "responses"
  env_key = "OPENCODE_GO_API_KEY"

Relay process:
  CODEX_RELAY_PORT=4446
  CODEX_RELAY_UPSTREAM=https://opencode.ai/zen/go/v1
  CODEX_RELAY_API_KEY=$OPENCODE_GO_API_KEY
  CODEX_RELAY_MODEL_MAP="" unless a future relay version needs an explicit alias
```

If opencode-go requires a model id different from the Codex-visible id, set an explicit map rather than changing Shogun's assignment semantics:

```text
CODEX_RELAY_MODEL_MAP=opencode-go/deepseek-v4-flash:deepseek-v4-flash
```

The default should be the upstream model id returned by `/v1/models`; for the current opencode-go endpoint that is `deepseek-v4-flash`. Mapping is a compatibility escape hatch, not the normal path.

## Codex Profile Template

The exact file path depends on `CODEX_HOME`; the profile name is `opencode_go`.

```toml
model = "deepseek-v4-flash"
model_provider = "opencode_go_relay"

[model_providers.opencode_go_relay]
name = "opencode_go_relay"
base_url = "http://127.0.0.1:4446/v1"
env_key = "OPENCODE_GO_API_KEY"
wire_api = "responses"

[model_properties."deepseek-v4-flash"]
context_window = 262144
max_context_window = 262144
supports_parallel_tool_calls = true
supports_reasoning_summaries = false
input_modalities = ["text"]
```

`model_properties` should be replaced with `codex-relay --print-config --upstream ...` output when opencode-go's `/v1/models` gives authoritative metadata. Until then, conservative context values are safer than over-advertising capacity.

## Runtime Contract

1. The relay listens only on loopback.
2. The relay receives no filesystem or shell capability.
3. The relay process owns upstream auth through `OPENCODE_GO_API_KEY`; no key is written to repo files.
4. Disk-backed relay history is disabled by default. If enabled for debugging, its directory is sensitive and must be gitignored.
5. Tool-call debug mode may log tool names, but must not log prompts, arguments, tool outputs, or secrets.

## Verification Plan

Phase 2 should run these checks before assigning production agent traffic:

1. Preflight:
   - `codex --version` is compatible with `wire_api = "responses"`.
   - `codex-relay --help` prints `--upstream`, `--api-key`, and `--print-config`.
   - `OPENCODE_GO_API_KEY` exists in the agent environment.
   - `curl http://127.0.0.1:4446/v1/models` through the relay returns opencode-go models.

2. Non-streaming smoke:
   - `codex -p opencode_go "Reply exactly OK"` completes.
   - Relay logs show the selected opencode-go model id without unintended remapping.

3. Streaming smoke:
   - A longer prompt streams partial output without stalling.
   - Codex receives a completed Responses event.

4. Tool smoke:
   - Run a harmless task requiring one local Codex tool call, for example reading a small file in a disposable fixture.
   - Relay debug logs preserve the tool name and show a returned function call.

5. Failure smoke:
   - Remove `OPENCODE_GO_API_KEY` from the relay environment and confirm failure is explicit.
   - Stop the relay and confirm Codex fails against `127.0.0.1:4446`, not by falling back to a different provider.

## Open Questions for Gunshi Review

- Whether opencode-go accepts provider-qualified model ids such as `opencode-go/deepseek-v4-flash` or requires relay `CODEX_RELAY_MODEL_MAP`.
- Whether opencode-go returns enough `/v1/models` metadata for `codex-relay --print-config`; if not, the conservative manual `model_properties` block needs review.
- Whether Shogun wants the relay supervised by an existing process manager or by a new script in a later implementation task.
- Whether relay disk history should remain forbidden or allowed behind an explicit debugging flag.

## Phase 2 Scope

Implement only the glue around the selected sidecar:

- Add or validate `profile` assignment in `config/settings.yaml`.
- Add tests for `build_cli_command ashigaru1` producing `codex -p opencode_go`.
- Add documentation for the operator-owned Codex TOML profile and relay environment variables.
- Do not vendor bridge source code.
- Do not commit secrets, generated history, or local `.env` files.
