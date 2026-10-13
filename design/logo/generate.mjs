import { writeFileSync } from 'node:fs'
import { join } from 'node:path'

// "hikki" wordmark and lockups. Text is converted to outlines with fontkit (root devDependency), the last i is
// dotless and gets the AI sparkle as its dot, in Kurenai. Run: node design/logo/generate.mjs
// Fonts (OFL): Outfit (design/logo/fonts/Outfit[wght].ttf, the pick) and Poppins SemiBold (the alternate).
import * as fontkit from 'fontkit'

import { concepts, palette, previewSvg, sparkle } from '../icon/generate.mjs'

const here = import.meta.dirname

export const fonts = {
  outfit: { file: 'fonts/Outfit[wght].ttf', wght: 600 },
  poppins: { file: 'fonts/Poppins-SemiBold.ttf' }
}
export const inks = {
  light: { ink: '#1C1C1C', star: palette.ink }, // on white: the app's primary + Kurenai
  dark: { ink: '#E6E4DF', star: palette.inkMid } // on dark: the dark-mode primary + the lighter Kurenai
}

/** The wordmark as an SVG string plus its metrics (100 units per em). */
export function wordmark(fontName, mode, { tracking = -0.012 } = {}) {
  const { file, wght } = fonts[fontName]
  const { ink, star } = inks[mode]
  let font = fontkit.openSync(join(here, file))
  if (wght && font.variationAxes?.wght) font = font.getVariation({ wght })
  const S = 100 / font.unitsPerEm
  const run = font.layout('hikkı') // dotless ı: the sparkle is its dot
  const iGlyph = font.layout('i').glyphs[0]
  const dotTop = iGlyph.bbox.maxY * S
  const dotH = dotTop - font.xHeight * S
  let x = 0
  const glyphs = []
  const centers = []
  run.glyphs.forEach((g, i) => {
    glyphs.push(
      `<path transform="translate(${(x * S).toFixed(2)} 0) scale(${S} ${-S})" d="${g.path.toSVG()}"/>`
    )
    centers.push(+((x + g.advanceWidth / 2) * S).toFixed(2))
    x += run.positions[i].xAdvance + tracking * font.unitsPerEm
  })
  const width = x * S
  const R = +Math.max(dotH * 0.95, 11).toFixed(2)
  const starAt = [centers[4], +(-dotTop + dotH * 0.42).toFixed(2)]
  const asc = font.ascent * S
  const desc = -font.descent * S
  const body = `<g fill="${ink}">\n${glyphs.join('\n')}\n</g>\n${sparkle(starAt[0], starAt[1], R, star)}`
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-R} ${-asc - R} ${(width + R * 2).toFixed(2)} ${(asc + desc + R * 2).toFixed(2)}">\n${body}\n</svg>\n`
  return { svg, body, width, asc, desc, R }
}

/** Icon mark + wordmark side by side; the mark is the concept's composite preview at the wordmark's cap height. */
export function lockup(concept, fontName, mode) {
  const w = wordmark(fontName, mode)
  const size = w.asc * 1.08 // the mark's edge
  const gap = size * 0.32
  const top = -w.asc - w.R
  const h = w.asc + w.desc + w.R * 2
  const markY = top + (h - size) / 2
  const mark = previewSvg(concept).replace(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">',
    `<svg x="0" y="${markY.toFixed(2)}" width="${size.toFixed(2)}" height="${size.toFixed(2)}" viewBox="0 0 1024 1024">`
  )
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 ${top.toFixed(2)} ${(size + gap + w.width + w.R * 2).toFixed(2)} ${h.toFixed(2)}">
${mark}
<g transform="translate(${(size + gap + w.R).toFixed(2)} 0)">
${w.body}
</g>
</svg>
`
}

if (process.argv[1] === import.meta.filename) {
  for (const f of Object.keys(fonts))
    for (const m of Object.keys(inks))
      writeFileSync(join(here, `wordmark-${f}-${m}.svg`), wordmark(f, m).svg)
  for (const c of concepts)
    for (const m of Object.keys(inks))
      writeFileSync(join(here, `lockup-${c.slug}-${m}.svg`), lockup(c, 'outfit', m))
  console.log('wordmarks + lockups written')
}
