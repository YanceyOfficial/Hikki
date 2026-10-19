/** Gist embeds: GitHub's script on a page of ours, restyled to the page and sized to its content. */

/** The snippet `embedFromURL` stores for a gist: GitHub's script, nothing else. */
const GIST_SNIPPET =
  /^<script src="https:\/\/gist\.github\.com\/[\w-]+\/[0-9a-f]+\.js"><\/script>$/u

/** Whether an HTML embed is a gist (stored before or after gists were styled: the snippet is the same). */
export const isGistSnippet = (html: string | null | undefined): html is string =>
  !!html && GIST_SNIPPET.test(html.trim())

/**
 * The page's look, resolved for a frame that can't read the page's CSS variables: a `srcdoc` document only
 * sees its own. Values are the theme tokens as the page computes them now (light or dark).
 */
export type EmbedTheme = { dark: boolean; tokens: Record<string, string> }

/** The tokens a gist is drawn with: `--<name>` on the page becomes `--hk-<name>` in the frame. */
export const EMBED_THEME_TOKENS = [
  'foreground',
  'muted-foreground',
  'subtle-foreground',
  'border',
  'code',
  'selection',
  'ink-green',
  'ink-red',
  'wash-green',
  'wash-red',
  'syntax-comment',
  'syntax-string',
  'syntax-number',
  'syntax-keyword',
  'syntax-preprocessor',
  'syntax-url',
  'syntax-attribute',
  'syntax-declaration',
  'syntax-definition',
  'syntax-type',
  'syntax-function',
  'font-sans',
  'font-mono',
  'text-xs',
  'text-md',
  'text-base',
  'radius-md'
] as const

/** The page's tokens as computed now (empty strings where the page doesn't define one, as in tests). */
export function readEmbedTheme(dark: boolean): EmbedTheme {
  const style = getComputedStyle(document.documentElement)
  const tokens: Record<string, string> = {}
  for (const name of EMBED_THEME_TOKENS) {
    const value = style.getPropertyValue(`--${name}`).trim()
    if (value) tokens[name] = value
  }
  return { dark, tokens }
}

/**
 * The frame's theme rules: the tokens as `--hk-*` variables and the colour scheme. A value can't close the style
 * element or open a new rule (no `<`, `;`, braces), whatever the page computed.
 */
export function embedThemeCSS(theme: EmbedTheme): string {
  const scheme = theme.dark ? 'dark' : 'light'
  const vars = Object.entries(theme.tokens)
    .filter(([name]) => /^[a-z-]+$/u.test(name))
    .map(([name, value]) => `--hk-${name}:${value.replaceAll(/[<>;{}]/gu, '')};`)
    .join('')
  return `:root{color-scheme:${scheme};${vars}}`
}

/**
 * GitHub's gist stylesheet restyled to the page: our fonts and sizes, no box of its own (the embed's card is the
 * box), line numbers subdued, Xcode's colours from the `syntax-*` tokens for GitHub's `pl-*` classes, rendered
 * Markdown as page text, and the "hosted with ❤ by GitHub" bar reduced to the file's name and "view raw".
 * Everything is `!important`: GitHub's sheet arrives later, written in by the gist's script.
 */
const GIST_CSS = `
html,body{margin:0;padding:0;background:transparent;color:var(--hk-foreground);font-family:var(--hk-font-sans,system-ui,sans-serif);font-size:var(--hk-text-base,16px)}
.gist{color:var(--hk-foreground)!important;font-family:var(--hk-font-sans,system-ui,sans-serif)!important;font-size:var(--hk-text-base,16px)!important}
.gist .gist-file{margin:0!important;border:0!important;border-radius:0!important;background:transparent!important;font-family:inherit!important}
.gist .gist-file+.gist-file{border-top:1px solid var(--hk-border)!important}
.gist .gist-data,.gist .file,.gist .Box-body,.gist .blob-wrapper,.gist .highlight,.gist table,.gist tr,.gist td{background:transparent!important;border:0!important;border-radius:0!important;margin:0!important}
.gist .blob-wrapper{padding:12px 0!important;overflow-x:auto!important}
.gist .blob-wrapper table{border-collapse:collapse!important}
.gist .blob-num,.gist .blob-code,.gist .blob-code-inner{font-family:var(--hk-font-mono,ui-monospace,monospace)!important;font-size:var(--hk-text-md,13px)!important;line-height:1.6!important;padding-top:0!important;padding-bottom:0!important}
.gist .blob-num{min-width:0!important;width:1%!important;padding-left:16px!important;padding-right:12px!important;color:var(--hk-muted-foreground)!important;text-align:right!important;user-select:none}
.gist .blob-num:hover{color:var(--hk-subtle-foreground)!important}
.gist .blob-code,.gist .blob-code-inner{padding-left:4px!important;padding-right:16px!important;color:var(--hk-foreground)!important;white-space:pre!important}
.gist .gist-meta{display:flex!important;flex-direction:row-reverse!important;justify-content:flex-start!important;gap:12px!important;padding:8px 16px!important;border-top:1px solid var(--hk-border)!important;border-radius:0!important;background:transparent!important;color:transparent!important;font-size:0!important;line-height:1.5!important}
.gist .gist-meta a{float:none!important;color:var(--hk-muted-foreground)!important;font-family:var(--hk-font-sans,system-ui,sans-serif)!important;font-size:var(--hk-text-xs,12px)!important;font-weight:400!important;text-decoration:none!important}
.gist .gist-meta a:hover{color:var(--hk-foreground)!important}
.gist .gist-meta a:first-child{margin-left:auto!important}
.gist .gist-meta a[href="https://github.com"]{display:none!important}
.gist .pl-c,.gist .pl-c span{color:var(--hk-syntax-comment)!important}
.gist .pl-k,.gist .pl-ent{color:var(--hk-syntax-keyword)!important;font-weight:600}
.gist .pl-s,.gist .pl-pds,.gist .pl-sr,.gist .pl-sr .pl-cce,.gist .pl-sra{color:var(--hk-syntax-string)!important}
.gist .pl-c1,.gist .pl-mi1,.gist .pl-ml{color:var(--hk-syntax-number)!important}
.gist .pl-cce,.gist .pl-sre{color:var(--hk-syntax-preprocessor)!important}
.gist .pl-corl{color:var(--hk-syntax-url)!important;text-decoration:underline}
.gist .pl-e,.gist .pl-smi.pl-e{color:var(--hk-syntax-attribute)!important}
.gist .pl-v{color:var(--hk-syntax-declaration)!important}
.gist .pl-en,.gist .pl-mh,.gist .pl-mh .pl-en{color:var(--hk-syntax-definition)!important}
.gist .pl-smi,.gist .pl-s1,.gist .pl-s .pl-s1{color:var(--hk-foreground)!important}
.gist .pl-bu,.gist .pl-ii,.gist .pl-c2{color:var(--hk-ink-red)!important;background:transparent!important}
.gist .pl-mi{font-style:italic}
.gist .pl-mb{font-weight:600}
.gist .pl-mi1{color:var(--hk-ink-green)!important;background:var(--hk-wash-green)!important}
.gist .pl-md{color:var(--hk-ink-red)!important;background:var(--hk-wash-red)!important}
.gist .markdown-body{padding:16px 20px!important;background:transparent!important;color:var(--hk-foreground)!important;font-family:var(--hk-font-sans,system-ui,sans-serif)!important;font-size:var(--hk-text-base,16px)!important;line-height:1.5!important}
.gist .markdown-body h1,.gist .markdown-body h2{border-bottom:0!important;padding-bottom:0!important}
.gist .markdown-body a{color:inherit!important;text-decoration:underline!important;text-decoration-color:var(--hk-muted-foreground)!important;text-underline-offset:2px}
.gist .markdown-body code,.gist .markdown-body tt{background:var(--hk-code)!important;border-radius:var(--hk-radius-md,6px)!important;font-family:var(--hk-font-mono,ui-monospace,monospace)!important;font-size:85%!important}
.gist .markdown-body pre,.gist .markdown-body .highlight pre{background:var(--hk-code)!important;border-radius:var(--hk-radius-md,6px)!important}
.gist .markdown-body pre code{background:transparent!important}
.gist .markdown-body blockquote{color:var(--hk-muted-foreground)!important;border-left-color:var(--hk-border)!important}
.gist .markdown-body hr{background:var(--hk-border)!important;border:0!important;height:1px!important}
.gist .markdown-body table th,.gist .markdown-body table td{border:1px solid var(--hk-border)!important}
.gist .markdown-body table tr{background:transparent!important;border:0!important}
.gist .markdown-body img{background:transparent!important}
::selection{background:var(--hk-selection)}
`

/** A message from an embed's frame: its content's height. */
export type EmbedFrameSize = { hikkiEmbed: 'size'; height: number }

/** The height a frame reports, checked: a frame's message is untrusted. Null for anything else. */
export function embedFrameHeight(data: unknown): number | null {
  if (!data || typeof data !== 'object') return null
  const message = data as Record<string, unknown>
  if (message.hikkiEmbed !== 'size' || typeof message.height !== 'number') return null
  return Number.isFinite(message.height) && message.height > 0 ? Math.ceil(message.height) : null
}

/**
 * The frame's own script: reports its content's height to the page whenever it changes, and takes a new theme
 * from the page (light ↔ dark) without reloading the gist.
 */
const FRAME_SCRIPT = `(function(){
var last=0;function post(){var h=Math.ceil(document.documentElement.getBoundingClientRect().height);if(h!==last){last=h;parent.postMessage({hikkiEmbed:'size',height:h},'*')}}
if(typeof ResizeObserver==='function')new ResizeObserver(post).observe(document.documentElement);
addEventListener('load',post);
addEventListener('message',function(e){if(e.source!==parent)return;var d=e.data;if(!d||d.hikkiEmbed!=='theme'||typeof d.css!=='string')return;document.getElementById('hk-theme').textContent=d.css;document.querySelector('meta[name=color-scheme]').content=d.dark?'dark':'light'});
})()`

/** What the page posts into a gist's frame when its appearance changes. */
export const embedThemeMessage = (theme: EmbedTheme) => ({
  hikkiEmbed: 'theme' as const,
  css: embedThemeCSS(theme),
  dark: theme.dark
})

/**
 * The document a gist's frame shows: GitHub's script on a page of ours, with the stylesheet that makes it look
 * like the page and the script that sizes the frame to it. Links open outside (the host sends popups out).
 */
export function gistEmbedDocument(html: string, theme: EmbedTheme): string {
  const scheme = theme.dark ? 'dark' : 'light'
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="${scheme}"><base target="_blank"><style>${GIST_CSS}</style><style id="hk-theme">${embedThemeCSS(theme)}</style><script>${FRAME_SCRIPT}</script></head><body>${html}</body></html>`
}
