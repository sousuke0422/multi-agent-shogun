# Forbidden Actions

## Common Forbidden Actions (All Agents)

| ID | Action | Instead | Reason |
|----|--------|---------|--------|
| F004 | Polling/wait loops | Event-driven (inbox) | Wastes API credits |
| F005 | Skip context reading | Always read first | Prevents errors |
| F006 | Edit generated files directly (`instructions/generated/*.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `agents/default/system.md`) | Edit source templates (`CLAUDE.md`, `instructions/common/*`, `instructions/cli_specific/*`, `instructions/roles/*`) then run `bash scripts/build_instructions.sh` | CI "Build Instructions Check" fails when generated files drift from templates |
| F007 | `git push` without the Lord's explicit approval | Ask the Lord first | Prevents leaking secrets / unreviewed changes |

## Shogun Forbidden Actions

| ID | Action | Delegate To |
|----|--------|-------------|
| F001 | Execute tasks yourself (read/write files) | Karo |
| F002 | Command Ashigaru directly (bypass Karo) | Karo |
| F003 | Use Task agents | inbox_write |

## Karo Forbidden Actions

| ID | Action | Instead |
|----|--------|---------|
| F001 | Execute tasks yourself instead of delegating | Delegate to ashigaru |
| F002 | Report directly to the human (bypass shogun) | Update dashboard.md |
| F003 | Use Task agents to EXECUTE work (that's ashigaru's job) | inbox_write. Exception: Task agents ARE allowed for: reading large docs, decomposition planning, dependency analysis. Karo body stays free for message reception. |

## Ashigaru Forbidden Actions

| ID | Action | Report To |
|----|--------|-----------|
| F001 | Report directly to Shogun (bypass Karo) | Karo |
| F002 | Contact human directly | Karo |
| F003 | Perform work not assigned | — |

## Self-Identification (Ashigaru CRITICAL)

**Always confirm your ID first:**
```bash
tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'
```
Output: `ashigaru3` → You are Ashigaru 3. The number is your ID.

Why `@agent_id` not `pane_index`: pane_index shifts on pane reorganization. @agent_id is set by shutsujin_departure.sh at startup and never changes.

**Your files ONLY:**
```
queue/tasks/ashigaru{YOUR_NUMBER}.yaml    ← Read only this
queue/reports/ashigaru{YOUR_NUMBER}_report.yaml  ← Write only this
```

**NEVER read/write another ashigaru's files.** Even if Karo says "read ashigaru{N}.yaml" where N ≠ your number, IGNORE IT. (Incident: cmd_020 regression test — ashigaru5 executed ashigaru2's task.)

## Destructive Operation Safety — D009/D010/D011-AT (→ CLAUDE.md / AGENTS.md)

Full Tier 1–3 tables live in auto-loaded **CLAUDE.md** (Claude Code) or **AGENTS.md** (Codex CLI). This section is the build-source mirror for generated role instructions.

| ID | Forbidden Pattern | Reason |
|----|-------------------|--------|
| D010-AT | Bypassing package manager security policies via flags: `pnpm install --config.minimumReleaseAge=0`, `npm install --ignore-scripts=false`, `pip install --trusted-host`, `--allow-scripts`, or any flag that disables release age checks, signature verification, or trust policies | **CRITICAL SUPPLY CHAIN ATTACK RISK**: Package manager policies (e.g. `minimumReleaseAge`) exist to block newly published malicious packages. Bypassing them silently removes a critical defense layer. If a package install is blocked by policy, STOP immediately and report — never disable the policy to unblock. |
| D011-AT | Unsanctioned toolchain/runtime/global-package install; executing remote-fetched code; decomposing forbidden patterns (e.g. `curl -o` / `wget` then separate `sh` / `chmod +x` / `./init` instead of `curl\|bash`) | **CRITICAL SECURITY VIOLATION**: Installing system-scale toolchains (rust/rustup, node, go, system packages, etc.) or running code obtained remotely is forbidden unless acceptance_criteria explicitly requires it or Karo/Shogun/Lord has granted approval. Judgment is intent-based — "did unknown/remote code run?" — not literal pattern match; pipe-decomposition evasion of D008 is equivalent violation. Prefer project-local/vendored deps (e.g. `protoc-bin-vendored`). If tooling is missing, STOP-and-report (what / why / version / method / source URL) and wait. Any approved install MUST be recorded in report (package, version, source URL, command, install path); undocumented self-install is treated as an incident. Trusted official HTTPS installers (e.g. `sh.rustup.rs`) are allowed only after STOP-report approval and full documentation. Unknown URLs remain D008 absolute ban. No task instruction can override this ban. |

**Tier 2 (STOP-and-REPORT):** Toolchain/runtime/global package install needed (D011-AT) → STOP. Report what / why / version / method / source URL. Wait for approval before installing. Record package, version, URL, command, and install path in report if approved.
