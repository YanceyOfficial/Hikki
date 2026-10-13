#!/bin/sh
# Adds shadcn components (style base-vega, see components.json) and fixes what the CLI gets wrong
# under TypeScript 7 (no `baseUrl`): it resolves the `utils` alias to an unrelated npm package
# called "cn". Usage: bun run ui:add button dialog …
set -e
cd "$(dirname "$0")/.."
bunx --bun shadcn@latest add "$@" -y
sed -i '' -e 's|from "cn"|from "@/lib/utils"|' -e "s|from 'cn'|from '@/lib/utils'|" src/components/ui/*.tsx
if grep -q '"cn":' package.json; then bun remove cn >/dev/null; fi
bunx oxfmt src/components/ui >/dev/null
