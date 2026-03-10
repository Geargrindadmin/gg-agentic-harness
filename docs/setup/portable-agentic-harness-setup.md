# Portable Agentic Harness Setup

Use this guide to install the GG Agentic Harness into a different repository without repeating manual setup.

## Prerequisites

- Node.js >= 20
- `gg` CLI scaffold built in the source harness repo
- Git (for worktree management and portable installs)
- Optional live `CodeGraphContext` pilot: host `cgc` CLI installed with Python `3.10+` and preferably Python `3.12+` on macOS

Verified host install command:

```bash
uv tool install --python python3.13 codegraphcontext
```

## Quick Start (One Command)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/scripts/install-from-github.sh) /absolute/path/to/target-repo symlink
```

This installs the harness, builds dependencies, activates the codex runtime adapter, and verifies the installation.

## 1. Build the CLI in the source repo

```bash
npm run gg:build
```

## 2. Initialize harness in target project

From the source harness repo:

```bash
node packages/gg-cli/dist/index.js portable init /absolute/path/to/target-repo --mode symlink
```

Use `--mode copy` if you want a fully independent copy instead of shared symlinks.

## 3. Build gg-skills in target project

```bash
npm --prefix /absolute/path/to/target-repo/mcp-servers/gg-skills install
npm --prefix /absolute/path/to/target-repo/mcp-servers/gg-skills run build
```

## 4. Activate runtime adapter for the target

```bash
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo runtime activate /absolute/path/to/target-repo --runtime codex
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo runtime status /absolute/path/to/target-repo --runtime codex
```

For `--runtime codex`, this step updates `~/.codex/config.toml` and `~/.codex/mcp.json` so repo-scoped MCPs (`gg-skills`, `filesystem`) point at the target project instead of whichever repo was active previously.

Restart Codex after activation so the active session reloads the updated repo-scoped MCP paths.

## 5. Verify Target Harness

### Basic Verification

```bash
cd /absolute/path/to/target-repo
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js doctor
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js --json doctor
```

### Structural Verification

```bash
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js \
  --project-root /absolute/path/to/gg-agentic-harness \
  portable verify /absolute/path/to/target-repo --runtime structure
```

### Runtime Parity and Persona Validation

```bash
npm run harness:runtime-parity
npm run harness:persona:audit
npm run harness:persona:benchmark
```

### Context Source Verification (Optional)

If `CodeGraphContext` is installed:

```bash
npm run gg -- --json workflow run prompt-improver "inspect agent routing" --context-source prefer
```

Expected output includes `contextSource: codegraphcontext` or `contextSource: hybrid`.

### Persona Resolution Test

```bash
node scripts/persona-registry-resolve.mjs \
  --prompt "document a portable harness rollout" \
  --classification TASK --json
```

## 6. IDE integration

- Open the target repo in your IDE/agent runtime.
- Ensure runtime reads target `.mcp.json`.
- Restart Codex after `runtime activate --runtime codex` so the new repo-scoped MCP config is loaded.
- Validate `gg-skills` catalog loading.

## Multi-Model Runtime Activation

The harness supports three runtime adapters: `codex`, `claude`, and `kimi`.

### Activate a Specific Runtime

```bash
# Codex (default)
npm run harness:runtime:activate
# Or explicitly:
node scripts/runtime-project-sync.mjs activate . --runtime codex

# Claude
node scripts/runtime-project-sync.mjs activate . --runtime claude

# Kimi
node scripts/runtime-project-sync.mjs activate . --runtime kimi
```

### Runtime Adapter Differences

| Runtime | Activation Behavior | Transport |
|---------|---------------------|-----------|
| `codex` | Rewrites `~/.codex/config.toml` and `~/.codex/mcp.json` | `background-terminal` |
| `claude` | Contract-only validation (no host mutation) | `background-terminal` or `contract-only` |
| `kimi` | Contract-only validation (no host mutation) | `cli-session` or `api-session` |

**Note**: Restart your runtime session after activation to pick up repo-scoped MCP changes.

## Troubleshooting

### Runtime Parity Warnings

If `npm run harness:runtime-parity` warns about activation:
- This is a **host-state warning**, not a repo install failure
- The local harness install is structurally correct
- Run `npm run harness:runtime:activate` to resolve

### Missing MCP Tools

If `gg-skills` or `filesystem` MCPs are unavailable:
1. Verify activation: `npm run harness:runtime:status`
2. Restart your runtime session
3. Check `~/.codex/mcp.json` for correct paths

### Persona Resolution Issues

If persona routing fails:
1. Run `npm run harness:persona:audit` to validate registry
2. Check `.agent/registry/persona-registry.json` exists
3. Check `.agent/registry/persona-compounds.json` exists

## Notes

- `symlink` mode centralizes updates in one source harness.
- `copy` mode is safer for long-lived divergence.
- Generated `PORTABLE_AGENTIC_SETUP.md` inside target includes exact next steps.
- `portable verify` exercises prompt mirrors, package scripts, persona benchmark coverage, project-context freshness, and runtime parity structure before you trust a new install.
- `portable verify` warns when the runtime adapter has not been activated for the target repo on the current machine.
- `workflow run` has executable adapters for `go`, `paperclip-extracted`, `prompt-improver`, `symphony-lite`, `visual-explainer`, `full-doc-update`, and `hydra-sidecar`.
- `CodeGraphContext` pilot mode requires the upstream `cgc` CLI on the host if you want live graph-backed context instead of the standard fallback path.
- The verified smoke for that path is `npm run gg -- --json workflow run prompt-improver "inspect agent routing" --context-source prefer`, which should emit `contextSource: codegraphcontext` or `contextSource: hybrid`.
- Portable installs now include `.agent/agents/`, `.agent/registry/persona-registry.json`, and `.agent/registry/persona-compounds.json` so new projects inherit deterministic persona routing on day one.
- The multi-model control plane (`packages/gg-control-plane-server`) is available in all portable installs for headless operation.
