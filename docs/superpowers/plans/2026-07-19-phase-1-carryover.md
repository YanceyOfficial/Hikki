# Phase 1 → later phases: deferred items (from final branch review, 2026-07-19)

Carry these into the named phase's plan; none block Phase 1, all were triaged in the whole-branch review.

## Phase 2 (Editor)

- **Atomic document writes**: replace `fs::write` with temp-file + rename in `document.rs` (and `vault.rs` settings) — durability becomes critical once blocks make writes large/frequent.
- **Corrupt-doc resilience**: `list_documents`/startup reconcile must skip-and-report unreadable `document.json` files instead of failing wholesale (partial iCloud sync / power loss must not brick launch).
- **Sidebar meta performance**: `list_documents` parses full `blocks` of every doc on every refresh; serve metas from the SQLite `documents` table (or split meta from blocks on disk).
- Assets + `asset://` protocol, CSP tightening (already planned for Phase 2).

## Phase 4 (Settings/errors/logging)

- Autosave and sidebar create/delete error handling (currently silent `.then()` chains; route through the Phase 4 `reportError` funnel).
- Vault-switch: rebuild-failure-after-persist leaves index stale (expose "Rebuild index" prominently); small race window between cloned vault path and concurrent `set_vault_path`.

## Phase 6 (Extras: trash UI, backlinks, ⌘K)

- `move_document` must reject `parentId` cycles at write time (spec §2 requirement; delete-walk is cycle-safe since `6378f48` but writes still accept cycles).
- MemoryBackend `search` snippet is hardcoded `''` — needs parity when the ⌘K search UI lands.
- `Index::remove` leaves orphaned `links` rows once links are populated.
- Adversarial-input test for `fts_query` (verified safe manually; pin with a test).

## Phase 8 (Updater/CI)

- Restore `forbidOnly`, CI `retries`, and `trace: 'on-first-retry'` in `playwright.config.ts`.

## Accepted (no action planned)

- `schemaVersion` written but not yet checked on load; index `meta` table unpopulated — needs an owner before any schema change.
- Non-canonical UUID forms accepted by `Uuid::parse_str`; double id-validation in `save_document`; `Index::upsert`/reconcile not transactional (index is rebuildable); `Doc.blocks: unknown[]` until zod (Phase 4); `createDoc` double-click guard.
