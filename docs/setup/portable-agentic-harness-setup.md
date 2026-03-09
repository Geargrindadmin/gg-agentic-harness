# Portable Agentic Harness Setup

Use this guide to install the GGV3 harness into a different repository without repeating manual setup.

## Prerequisites

- Node.js >= 20
- `gg` CLI scaffold built in the source harness repo
- Optional live `CodeGraphContext` pilot: host `cgc` CLI installed with Python `3.10+` and preferably Python `3.12+` on macOS

Verified host install command:

```bash
uv tool install --python python3.13 codegraphcontext
```

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

## 5. Verify target harness

```bash
cd /absolute/path/to/target-repo
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js doctor
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js --json doctor
node /absolute/path/to/gg-agentic-harness/packages/gg-cli/dist/index.js --project-root /absolute/path/to/gg-agentic-harness portable verify /absolute/path/to/target-repo --runtime structure
npm run harness:runtime-parity
npm run harness:persona:audit
npm run harness:persona:benchmark
npm run gg -- --json workflow run prompt-improver "inspect agent routing" --context-source prefer
node scripts/persona-registry-resolve.mjs --prompt "document a portable harness rollout" --classification TASK --json
```

## 6. IDE integration

- Open the target repo in your IDE/agent runtime.
- Ensure runtime reads target `.mcp.json`.
- Restart Codex after `runtime activate --runtime codex` so the new repo-scoped MCP config is loaded.
- Validate `gg-skills` catalog loading.

## Notes

- `symlink` mode centralizes updates in one source harness.
- `copy` mode is safer for long-lived divergence.
- Generated `PORTABLE_AGENTIC_SETUP.md` inside target includes exact next steps.
- `portable verify` exercises prompt mirrors, package scripts, persona benchmark coverage, project-context freshness, and runtime parity structure before you trust a new install.
- `portable verify` warns when the codex runtime adapter has not been activated for the target repo on the current machine.
- `workflow run` has executable adapters for `go`, `paperclip-extracted`, `prompt-improver`, `symphony-lite`, `visual-explainer`, `full-doc-update`, and `hydra-sidecar`.
- `CodeGraphContext` pilot mode requires the upstream `cgc` CLI on the host if you want live graph-backed context instead of the standard fallback path.
- The verified smoke for that path is `npm run gg -- --json workflow run prompt-improver "inspect agent routing" --context-source prefer`, which should emit `contextSource: codegraphcontext` or `contextSource: hybrid`.
- Portable installs now include `.agent/agents/`, `.agent/registry/persona-registry.json`, and `.agent/registry/persona-compounds.json` so new projects inherit deterministic persona routing on day one.
