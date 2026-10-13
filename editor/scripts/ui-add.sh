#!/bin/sh
# Adds shadcn components (style base-vega, see components.json) and formats them like the rest of the
# editor. The CLI imports `cn` from shadcn's own `cn` package (its clsx + tailwind-merge replacement);
# that is what the whole editor uses. Usage: bun run ui:add button dialog …
set -e
cd "$(dirname "$0")/.."
bunx --bun shadcn@latest add "$@" -y
bunx oxfmt src/components/ui >/dev/null
