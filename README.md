# Hikki

A Notion-like, local-first note-taking app for macOS.

- **Your files, yours** — documents live as plain JSON + assets in `~/Hikki` (relocatable, iCloud-friendly). A derived SQLite FTS5 index powers instant search and is always rebuildable.
- **Editor** — BlockNote block editor with slash commands, images and file attachments stored inside your vault, syntax-highlighted code blocks (shiki, ~26 languages, auto-detected on paste), comments, a table of contents, and AI Writing Tools — Proofread, Rewrite, tone rewrites, transforms (summary, key points, list, table), and free-form Compose, backed by your choice of OpenAI or Anthropic. Configure an API key via the AI Settings entry in the titlebar before using it. Voice input (Phase 7) is next.
- **Appearance** — light/dark toggle in the titlebar (native window chrome follows along); a dedicated Appearance settings panel is still planned for Phase 4.
- **Stack** — Tauri 2 (Rust), React 19, BlockNote, shadcn/ui, Jotai, Vite.

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
