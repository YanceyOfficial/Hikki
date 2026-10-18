# Hikki website

The site at https://hikki.yancey.app: TanStack Start with Solid, rendered on the server (Nitro) and deployed to
Vercel (`vercel.json`). One page, `src/routes/index.tsx`, in a Mondrian grid (`src/styles.css`).

```sh
bun install            # from the repository root (a bun workspace)
bun run dev            # http://localhost:3000
bun run build          # .output/ — what Vercel deploys
bun run start          # the built server
bun run typecheck
```

- The App Store link lives in `src/site.ts` (`APP_STORE_URL`); until it is set the buttons say "Coming to the App
  Store".
- Screenshots in `public/shots/` come from the simulators and a Mac with an English demo workspace — never personal
  notes.
- TanStack's own skills ship in its packages: `bunx @tanstack/intent@latest list` (see `AGENTS.md`).
