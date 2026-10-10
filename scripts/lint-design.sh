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
check "SF Symbol — use the Phosphor Icon enum (design/icons.json, make icons)" '(systemImage|systemName): '
allowed_files=$(grep -rl 'design-lint: allow-file' editor/src | tr '\n' '|' | sed 's/|$//')
css=$(grep -nE '#[0-9a-fA-F]{3,8}\b|rgba?\(' editor/src --include='*.css' --include='*.tsx' --include='*.ts' -r | grep -v 'editor/src/theme.css' | grep -v 'design-lint: allow' | { if [ -n "$allowed_files" ]; then grep -vE "^($allowed_files):"; else cat; fi; })
if [ -n "$css" ]; then echo "✗ literal color in web code — use a Tailwind token class (bg-background, text-muted-foreground…)"; echo "$css" | sed 's/^/    /'; status=1; fi
[ $status -eq 0 ] && echo "design lint: ok"
exit $status
