# Progress Tracker — Modular Extraction

Legend:
- ✅ done
- 🟡 in progress
- ⬜ todo

Context:
`bin/free-coding-models.js` is ~5k lines with TUI, overlays, ping infra, proxy management, OpenCode/OpenClaw integrations, telemetry, and a complex keypress state machine. A `src/` directory now exists, but the bin file still carries most logic.

Goal:
Rename `lib/` → `src/`, then extract remaining logic from `bin/` into focused `src/` modules, leaving `bin/free-coding-models.js` as a clean ~500-line orchestrator. No behavior changes — pure refactor.

Final `src/` structure:

Moved (renamed from `lib/` as-is, 13 files):
- ✅ src/utils.js
- ✅ src/config.js
- ✅ src/model-merger.js
- ✅ src/proxy-server.js
- ✅ src/opencode-sync.js
- ✅ src/usage-reader.js
- ✅ src/log-reader.js
- ✅ src/provider-quota-fetchers.js
- ✅ src/quota-capabilities.js
- ✅ src/request-transformer.js
- ✅ src/token-stats.js
- ✅ src/account-manager.js
- ✅ src/error-classifier.js

New (extracted from `bin/`, 15 files):
- ✅ src/constants.js — terminal/TUI constants
- ✅ src/tier-colors.js — tier color map
- ✅ src/provider-metadata.js — provider metadata + env names + platform flags
- ✅ src/telemetry.js — PostHog + Discord telemetry
- ✅ src/favorites.js — favorite helpers
- ✅ src/updater.js — update checks/install
- ✅ src/setup.js — first-run API key wizard
- ✅ src/ping.js — ping and quota helpers
- ✅ src/analysis.js — fiable mode + tier filter + OpenRouter fetch
- ✅ src/render-helpers.js — render utilities
- ✅ src/render-table.js — main table renderer
- ✅ src/opencode.js — OpenCode integration
- ✅ src/openclaw.js — OpenClaw integration
- ✅ src/overlays.js — overlay renderers factory
- ✅ src/key-handler.js — key handler factory

Execution order (safest sequence):
- ✅ Phase 0 — Rename `lib/` → `src/` (imports updated, `lib/` removed, `package.json` files updated)
- ✅ Phase 1 — Extract constants, tier colors, provider metadata
- ✅ Phase 2 — Extract telemetry, favorites, updater, setup
- ✅ Phase 3 — Extract ping + analysis
- ✅ Phase 4 — Extract render helpers + render table
- ✅ Phase 5 — Integrations (OpenCode + OpenClaw extracted)
- ✅ Phase 6 — Move `tierFilterMode` + `originFilterMode` into state object
- ✅ Phase 7 — Extract overlays + key-handler via factory pattern
- ✅ Phase 8 — Docs (JSDoc sweep, update `AGENTS.md`, update `CHANGELOG.md`)

Verification:
- ✅ `pnpm test` after Phase 4
- ✅ `pnpm start` after Phase 4
- ✅ Re-run `pnpm test` + `pnpm start` after Phase 5+
- ⬜ Final `wc -l bin/free-coding-models.js` ≤ 550
