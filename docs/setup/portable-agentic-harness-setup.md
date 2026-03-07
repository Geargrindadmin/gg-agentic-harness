# Portable Agentic Harness Setup

Use this guide to install the GGV3 harness into a different repository without repeating manual setup.

## Prerequisites

- Node.js >= 20
- `gg` CLI scaffold built in the source harness repo

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

## 4. Verify target harness

```bash
cd /absolute/path/to/target-repo
node /absolute/path/to/GGV3/packages/gg-cli/dist/index.js doctor
node /absolute/path/to/GGV3/packages/gg-cli/dist/index.js --json doctor
```

## 5. IDE integration

- Open the target repo in your IDE/agent runtime.
- Ensure runtime reads target `.mcp.json`.
- Validate `gg-skills` catalog loading.

## Notes

- `symlink` mode centralizes updates in one source harness.
- `copy` mode is safer for long-lived divergence.
- Generated `PORTABLE_AGENTIC_SETUP.md` inside target includes exact next steps.
- `workflow run` has executable adapters for `paperclip-extracted`, `symphony-lite`, and `visual-explainer`.
