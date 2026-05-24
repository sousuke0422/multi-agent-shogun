All git commits — whether in the shogun repository or in external projects (Coder workspaces, etc.) — MUST include the following trailer:

```
Assisted-by: multi-agent-shogun-aki-tweak
```

Rules:
- Place the trailer at the end of the commit message body, after a blank line.
- This applies to `git commit` executed via `bash scripts/coder_mount.sh exec` and any other path.
- Do NOT use `Co-Authored-By:`; `Assisted-by:` is the correct tag per the Linux kernel convention.
