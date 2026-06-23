# Codex endpoint profile templates

These files are examples for Codex CLI endpoint profiles. Copy one template to `$CODEX_HOME/<profile>.config.toml`, then assign the profile name from `config/settings.yaml`:

```yaml
cli:
  agents:
    ashigaru1:
      type: codex
      profile: opencode-go-flash
```

The runtime command is `codex -p <profile>`. Do not inject `model_provider` with `-c`, and do not generate a shim TOML as the runtime source of truth.

API keys must stay in environment variables. The TOML files contain only `env_key` names such as `OPENCODE_GO_API_KEY` or `SAKANA_FUGU_API_KEY`; never commit key values or force-add ignored secret files.

Finance workloads continue to use model-name fences. Fugu is not approved for finance use, so its model name should remain in `finance.exclude_models`.

These templates also provide an escape route from provider-specific OpenCode TUI behavior: Codex owns the endpoint profile through its native `config.toml` profile layer, while the existing `type=opencode` path remains unchanged.
