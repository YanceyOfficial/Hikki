# Hikki

A Notion-like, local-first note-taking app for macOS.

- **Your files, yours** — documents live as plain JSON + assets in `~/Hikki` (relocatable, iCloud-friendly). A derived SQLite FTS5 index powers instant search and is always rebuildable.
- **Editor** — BlockNote block editor (Phase 2), AI Writing Tools in the style of Apple Intelligence (Phase 3), experimental voice input (Phase 7).
- **Stack** — Tauri 2 (Rust), React 19, shadcn/ui, Jotai, Vite.

## Development

```bash
pnpm install
pnpm tauri dev      # desktop app
pnpm dev            # browser-only mode (in-memory backend)
```

## Testing

```bash
pnpm test                                        # Vitest unit tests
cargo test --manifest-path src-tauri/Cargo.toml  # Rust tests
pnpm e2e                                         # Playwright e2e
```

## Project docs

- Design spec: `docs/superpowers/specs/2026-07-18-hikki-design.md`
- Implementation plans: `docs/superpowers/plans/`
