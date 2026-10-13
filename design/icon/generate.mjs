// Hikki app icon concepts → layered SVGs for Icon Composer (+ composite preview + menu bar glyph).
// Run: node design/icon/generate.mjs   (writes design/icon/<concept>/…)
//
// Icon Composer rules we follow (Apple, "Creating your app icon using Icon Composer" + WWDC25 361):
//  - 1024×1024 canvas; every layer exported at full canvas size so it lands in place.
//  - Flat fills only: no gradients, blur, shadow or opacity in layers — the glass adds those.
//  - No background in the layers; the background (solid / gradient) is set in Icon Composer.
//  - Files numbered in Z order so Icon Composer stacks them automatically.
import { mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const S = 1024
const CORNER = 229 // ≈ 22.37 % — preview only; the system masks the real icon

export const palette = {
  inkTop: '#6B8AFB',
  inkBottom: '#3350E0',
  ink: '#3350E0',
  white: '#FFFFFF',
  paperTop: '#FFFFFF',
  paperBottom: '#F1F3F8',
  tint: '#C9D4FF', // light brand tint (band, fold)
  rule: '#D5DAEA' // notebook lines
}

const svgOpen = (vb = `0 0 ${S} ${S}`, extra = '') =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}"${extra}>`
const layerFile = (body) => `${svgOpen()}\n${body}\n</svg>\n`

// ---------- geometry ----------

// A. Nib — fountain-pen nib, tip down, breather hole + slit cut out (even-odd).
const nibPath = (() => {
  const cx = 512
  const top = 212
  const shoulderY = 420
  const halfW = 218
  const tipY = 812
  return [
    `M ${cx - halfW} ${shoulderY}`,
    `A ${halfW} ${halfW} 0 0 1 ${cx + halfW} ${shoulderY}`.replace(
      `${halfW} ${halfW}`,
      `${halfW} ${shoulderY - top}`
    ),
    `C ${cx + halfW} 585 ${cx + 118} 700 ${cx} ${tipY}`,
    `C ${cx - 118} 700 ${cx - halfW} 585 ${cx - halfW} ${shoulderY}`,
    'Z',
    // breather hole
    `M ${cx} 418 m -48 0 a 48 48 0 1 0 96 0 a 48 48 0 1 0 -96 0 Z`,
    // slit (rounded)
    `M ${cx - 15} 470 h 30 v 262 a 15 15 0 0 1 -30 0 Z`
  ].join(' ')
})()

// B. Hi — hiragana ひ as one monoline stroke (first syllable of hikki, 筆記).
const hiPath = [
  'M 318 338',
  'L 462 338',
  'C 448 428 328 510 300 606',
  'C 272 704 344 758 452 758',
  'C 578 758 700 736 744 634',
  'C 780 548 752 474 692 450',
  'C 656 436 626 452 616 484'
].join(' ')
const hiStroke = 118

// C. Notebook — white cover, spine band, three lines.
const nb = { x: 252, y: 192, w: 520, h: 640, r: 64, band: 92 }

// D. Sumi — one calligraphic 一 stroke, ink on paper.
const sumiPath = [
  'M 228 522',
  'C 298 436 428 476 556 460',
  'C 672 446 744 410 806 428',
  'C 862 444 858 516 812 548',
  'C 736 600 614 578 512 590',
  'C 410 602 304 648 240 610',
  'C 190 582 186 548 228 522',
  'Z'
].join(' ')

// ---------- concepts ----------

const concepts = [
  {
    slug: 'nib',
    name: 'Nib',
    background: { kind: 'gradient', top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'nib', body: `<path fill="${palette.white}" fill-rule="evenodd" d="${nibPath}"/>` }
    ],
    menubar: `<path fill="#000" fill-rule="evenodd" transform="translate(9 9) scale(0.0225) translate(-512 -512)" d="${nibPath}"/>`
  },
  {
    slug: 'hi',
    name: 'Hi',
    background: { kind: 'gradient', top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      {
        name: 'hi',
        body: `<path fill="none" stroke="${palette.white}" stroke-width="${hiStroke}" stroke-linecap="round" stroke-linejoin="round" d="${hiPath}"/>`
      }
    ],
    menubar: `<path fill="none" stroke="#000" stroke-width="${hiStroke * 0.9}" stroke-linecap="round" stroke-linejoin="round" transform="translate(9 9.2) scale(0.0245) translate(-522 -548)" d="${hiPath}"/>`
  },
  {
    slug: 'notebook',
    name: 'Notebook',
    background: { kind: 'gradient', top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      {
        name: 'cover',
        body: `<rect x="${nb.x}" y="${nb.y}" width="${nb.w}" height="${nb.h}" rx="${nb.r}" fill="${palette.white}"/>`
      },
      {
        name: 'band',
        body: `<path fill="${palette.tint}" d="M ${nb.x + nb.r} ${nb.y} H ${nb.x + nb.band} V ${nb.y + nb.h} H ${nb.x + nb.r} A ${nb.r} ${nb.r} 0 0 1 ${nb.x} ${nb.y + nb.h - nb.r} V ${nb.y + nb.r} A ${nb.r} ${nb.r} 0 0 1 ${nb.x + nb.r} ${nb.y} Z"/>`
      },
      {
        name: 'lines',
        body: [0, 1, 2]
          .map(
            (i) =>
              `<rect x="${nb.x + nb.band + 92}" y="${nb.y + 196 + i * 124}" width="${i === 2 ? 190 : 288}" height="30" rx="15" fill="${palette.rule}"/>`
          )
          .join('\n')
      }
    ],
    menubar: [
      `<rect x="3.75" y="2.25" width="10.5" height="13.5" rx="1.75" fill="none" stroke="#000" stroke-width="1.5"/>`,
      `<rect x="3.75" y="2.25" width="2.6" height="13.5" rx="0" fill="#000" clip-path="inset(0 round 1.75px 0 0 1.75px)"/>`,
      `<rect x="8.4" y="6.2" width="4" height="1.3" rx="0.65" fill="#000"/>`,
      `<rect x="8.4" y="8.85" width="4" height="1.3" rx="0.65" fill="#000"/>`,
      `<rect x="8.4" y="11.5" width="2.6" height="1.3" rx="0.65" fill="#000"/>`
    ].join('\n')
  },
  {
    slug: 'sumi',
    name: 'Sumi',
    background: { kind: 'gradient', top: palette.paperTop, bottom: palette.paperBottom },
    layers: [{ name: 'stroke', body: `<path fill="${palette.ink}" d="${sumiPath}"/>` }],
    menubar: [
      `<rect x="2.25" y="2.25" width="13.5" height="13.5" rx="3.5" fill="none" stroke="#000" stroke-width="1.5"/>`,
      `<path fill="#000" transform="translate(9 9) scale(0.0155) translate(-518 -516)" d="${sumiPath}"/>`
    ].join('\n')
  }
]

// ---------- output ----------

const previewSvg = (c) => {
  const bg =
    c.background.kind === 'gradient'
      ? `<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c.background.top}"/><stop offset="1" stop-color="${c.background.bottom}"/></linearGradient></defs><rect width="${S}" height="${S}" fill="url(#bg)"/>`
      : `<rect width="${S}" height="${S}" fill="${c.background.color}"/>`
  return `${svgOpen()}
<defs><clipPath id="icon"><rect width="${S}" height="${S}" rx="${CORNER}"/></clipPath></defs>
<g clip-path="url(#icon)">
${bg}
${c.layers.map((l) => l.body).join('\n')}
</g>
</svg>
`
}

const menubarSvg = (c) => `${svgOpen('0 0 18 18', ' width="18" height="18"')}
${c.menubar}
</svg>
`

for (const c of concepts) {
  const dir = join(here, c.slug)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  c.layers.forEach((l, i) =>
    writeFileSync(join(dir, `${String(i + 1).padStart(2, '0')}-${l.name}.svg`), layerFile(l.body))
  )
  writeFileSync(join(dir, 'preview.svg'), previewSvg(c))
  writeFileSync(join(dir, 'menubar.svg'), menubarSvg(c))
}
console.log(concepts.map((c) => `${c.slug}: ${c.layers.length} layer(s)`).join('\n'))
