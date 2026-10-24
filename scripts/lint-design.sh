#!/bin/sh
# Fails when view code bypasses the design tokens (design/tokens.json): literal font sizes, colors,
# spacing or corner radii. Append `// design-lint: allow` to a line for a justified exception.
cd "$(dirname "$0")/.." || exit 2
status=0
check() {
  matches=$(grep -rnE "$2" Hikki/Sources HikkiUI/Sources --include='*.swift' | grep -v '/Generated/' | grep -v 'design-lint: allow')
  if [ -n "$matches" ]; then echo "✗ $1"; echo "$matches" | sed 's/^/    /'; status=1; fi
}
check "literal font size — use .font(.hk(.sm))" '\.system\(size: *[0-9]'
check "literal color — add a token to design/tokens.json" 'Color\((red|white|hue):|#[0-9a-fA-F]{6}\b|0x[0-9A-Fa-f]{6}'
check "literal spacing — use Spacing.*" '(spacing: *-?[0-9])|(\.padding\((\.[a-zA-Z]+|\[[^]]*\]), *-?[0-9])|(\.padding\(-?[0-9])|(\.padding\([^)]*\? *[0-9])'
check "literal corner radius — use Radius.*" 'cornerRadius: *[0-9]'
check "raw SF Symbol — go through the Icon enum (design/icons.json \"sf\", make icons)" '(systemImage|systemName): '
check "system colour — use Theme.* (Theme.destructive, Theme.favorite, Theme.mutedForeground)" '(^|[^A-Za-z0-9_])\.(red|yellow|secondary)\b'
check "system font — use .font(.hk(.sm))" '\.font\(\.(largeTitle|title[23]?|headline|subheadline|body|callout|footnote|caption2?)\b|Font\.system\(|\.font\(\.system\('
check "one-off animation — use Motion.easeOut() / Motion.easeInOut() (CLAUDE.md: Motion)" '\.(snappy|bouncy|smooth|spring|interactiveSpring)\b|Animation\.(easeIn|easeOut|easeInOut|linear)\b|\.animation\(\.(easeIn|easeOut|easeInOut|linear|default)\b|withAnimation\(\.(easeIn|easeOut|easeInOut|linear|default)\b'
# Web code: the editor and the shared packages it bundles (packages/*/src). Excalidraw's own stylesheet and motion stay
# in node_modules, out of reach of these checks — the package only restyles it with tokens (apps/editor/src/style.css).
web_dirs="apps/editor/src $(ls -d packages/*/src 2>/dev/null | tr '\n' ' ')"
allowed_files=$(grep -rl 'design-lint: allow-file' $web_dirs | tr '\n' '|' | sed 's/|$//')
css=$(grep -nE '#[0-9a-fA-F]{3,8}\b|rgba?\(' $web_dirs --include='*.css' --include='*.tsx' --include='*.ts' -r | grep -v 'apps/editor/src/theme.css' | grep -v 'design-lint: allow' | { if [ -n "$allowed_files" ]; then grep -vE "^($allowed_files):"; else cat; fi; })
if [ -n "$css" ]; then echo "✗ literal color in web code — use a Tailwind token class (bg-background, text-muted-foreground…)"; echo "$css" | sed 's/^/    /'; status=1; fi
motion=$(grep -rnE 'animate-(in|out)\b|\b(fade|zoom)-(in|out)-|\bslide-(in-from|out-to)-|\btransition-all\b|\bduration-[0-9]|[^a-zA-Z0-9_-][0-9]+ms\b' $web_dirs --include='*.css' --include='*.tsx' --include='*.ts' | grep -v 'apps/editor/src/theme.css' | grep -v 'design-lint: allow')
if [ -n "$motion" ]; then echo "✗ one-off motion in web code — hk-pop / hk-pop-toggle, duration-(--motion-pop-in), ease-out (CLAUDE.md: Motion)"; echo "$motion" | sed 's/^/    /'; status=1; fi
# Web UI is shadcn: rows are MenuRow (apps/editor/src/components/menu-row.tsx), the rest Button / Input… (CLAUDE.md).
bare=$(grep -rnE '<(button|input)\b' apps/editor/src/components apps/editor/src/page $(ls -d packages/*/src 2>/dev/null) --include='*.tsx' | grep -v '^apps/editor/src/components/ui/' | grep -v 'design-lint: allow')
if [ -n "$bare" ]; then echo "✗ bare <button> / <input> in web UI — use the shadcn components (MenuRow, Button, Input…)"; echo "$bare" | sed 's/^/    /'; status=1; fi
[ $status -eq 0 ] && echo "design lint: ok"
exit $status
