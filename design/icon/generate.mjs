// Hikki app icon → layered SVGs for Icon Composer, plus a composite preview and a menu bar glyph.
// The mark is Hi✦ (`concepts`); the explored alternatives stay in `alternatives` and are written with --all.
// Run: node design/icon/generate.mjs [--all]   (rewrites design/icon/<concept>/…)
//
// Icon Composer rules we follow (Apple, "Creating your app icon using Icon Composer", WWDC25 361):
//  - 1024×1024 canvas; every layer is exported at full canvas size so it lands in place when dropped in.
//  - Flat fills only: no gradients, blur, shadow or opacity in a layer — Liquid Glass adds those per layer.
//  - No background in the layers; the background (solid / gradient) is set in Icon Composer's inspector.
//  - Files are numbered in Z order (01 = back) so Icon Composer stacks them automatically.
import { mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'

const here = import.meta.dirname
const S = 1024
const CORNER = 229 // ≈ 22.37 % — preview only; the system masks the real icon

export const palette = {
  // Brand colour: Kurenai (紅, safflower crimson). Background gradient, Icon Composer: Background → Gradient, top → bottom.
  inkTop: '#FF6478',
  inkBottom: '#D7003A',
  inkDarkTop: '#C2324A', // the Dark appearance's background
  inkDarkBottom: '#86001F',
  ink: '#D7003A', // kurenai as a shape fill (page fold, the nearest Flow stroke)
  inkMid: '#FF6478', // the lighter kurenai (Flow's middle stroke)
  mist: '#FFB1BA', // mid tint (Leaves' back sheets, Flow's far stroke)
  haze: '#FFD6DB', // pale tint (the overlapping second layer: ensō dot, h arch)
  white: '#FFFFFF',
  paperTop: '#FFFFFF', // the white-background concepts
  paperBottom: '#F6F1F2',
  tint: '#FFC9CF', // notebook band
  rule: '#E6D9DC', // ruled lines
  shade: '#E3D5D8' // under the folded corner
}

// Layers carry an explicit 1024 × 1024 size (as exodus's do) so Icon Composer places them at canvas size.
const svgOpen = (vb = `0 0 ${S} ${S}`, extra = ` width="${S}" height="${S}"`) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}"${extra}>`
const layerFile = (body) => `${svgOpen()}\n${body}\n</svg>\n`
const rot = (deg, body, dy = 0) =>
  `<g transform="translate(0 ${dy}) rotate(${deg} 512 512)">${body}</g>`

// ---------- A. Pen — fountain pen at 40°, one written line under the tip ----------
// Drawn upright (tip down) and rotated; the nib overlaps the barrel's end.
const PEN_TILT = 40
const barrel = `<rect x="434" y="118" width="156" height="560" rx="78" fill="${palette.white}"/>`
const nibPath = [
  'M 440 650', // left shoulder
  'C 440 630 460 616 480 616', // rounded top-left
  'L 544 616',
  'C 564 616 584 630 584 650',
  'C 584 760 548 830 512 900', // right side to the tip
  'C 476 830 440 760 440 650',
  'Z',
  'M 512 700 m -20 0 a 20 20 0 1 0 40 0 a 20 20 0 1 0 -40 0 Z', // breather hole
  'M 501 722 h 22 v 136 a 11 11 0 0 1 -22 0 Z' // slit
].join(' ')
const nib = `<path fill="${palette.white}" fill-rule="evenodd" d="${nibPath}"/>`
// After rotation the tip lands near (262, 773); the line runs right from under it.
const penLine = `<rect x="246" y="804" width="430" height="56" rx="28" fill="${palette.white}"/>`

// ---------- B. Hi — hiragana ひ (hikki, 筆記), two strokes: the bar and the bowl ----------
const HI_W = 104
const hiBar = 'M 272 356 L 440 344'
const hiBowl = [
  'M 440 344',
  'C 420 430 330 540 296 612', // the near-straight descent to the bottom-left
  'C 272 690 330 748 450 752', // round the bottom-left corner
  'C 590 756 720 720 748 610', // along the bottom and up the right arm
  'C 768 530 750 462 704 440', // the arm's top bends inward
  'C 676 428 650 440 642 464' // a short ending hook
].join(' ')
const stroke = (d, color = palette.white) =>
  `<path fill="none" stroke="${color}" stroke-width="${HI_W}" stroke-linecap="round" stroke-linejoin="round" d="${d}"/>`

// ---------- C. Notebook — white cover, spine band, three ruled lines ----------
const nb = { x: 242, y: 182, w: 540, h: 660, r: 66, band: 96 }
const nbCover = `<rect x="${nb.x}" y="${nb.y}" width="${nb.w}" height="${nb.h}" rx="${nb.r}" fill="${palette.white}"/>`
const nbBand = `<path fill="${palette.tint}" d="M ${nb.x + nb.r} ${nb.y} H ${nb.x + nb.band} V ${nb.y + nb.h} H ${nb.x + nb.r} A ${nb.r} ${nb.r} 0 0 1 ${nb.x} ${nb.y + nb.h - nb.r} V ${nb.y + nb.r} A ${nb.r} ${nb.r} 0 0 1 ${nb.x + nb.r} ${nb.y} Z"/>`
const nbLines = [292, 176].map(
  (w, i) =>
    `<rect x="${nb.x + nb.band + 96}" y="${nb.y + 230 + i * 120}" width="${w}" height="32" rx="16" fill="${palette.rule}"/>`
)
nbLines.splice(
  1,
  0,
  `<rect x="${nb.x + nb.band + 96}" y="${nb.y + 350}" width="292" height="32" rx="16" fill="${palette.rule}"/>`
)
nbLines[2] = nbLines[2].replace(`y="${nb.y + 230 + 120}"`, `y="${nb.y + 470}"`)

// ---------- D. Page — the whole icon is the sheet; a brand-blue folded corner ----------
const F = 400 // the fold's size along each edge
const pageCorner = `<path fill="${palette.shade}" d="M ${S - F} ${S} L ${S} ${S - F} L ${S} ${S} Z"/>` // what shows under the lifted corner
const pageFold = `<path fill="${palette.ink}" d="M ${S - F} ${S} L ${S} ${S - F} L ${S - F + 44} ${S - F} Q ${S - F} ${S - F} ${S - F} ${S - F + 44} Z"/>` // the corner's underside, flipped over (apex softened)
const pageLines = [
  [232, 268, 544],
  [232, 396, 432],
  [232, 524, 312]
].map(
  ([x, y, w]) => `<rect x="${x}" y="${y}" width="${w}" height="40" rx="20" fill="${palette.rule}"/>`
)

const f = (p) => p.map((n) => n.toFixed(1)).join(' ')
const rad = (d) => (d * Math.PI) / 180

// ======================= set 2: abstract =======================

// E. Leaves — three sheets fanned around a pivot below the icon (petals / a notebook's pages).
const sheet = (fill, deg) =>
  `<rect x="332" y="285" width="360" height="470" rx="72" fill="${fill}" transform="rotate(${deg} 512 1150)"/>`

// F. Ensō — a brush circle, thick at the lower left and thin at the gap, plus a dot in the opening.
const ensoPath = (() => {
  const C = [512, 512]
  const Ro = 330
  const Ri = 218
  const gapDeg = -35 // the opening, upper right
  const k = 58 // inner circle offset toward the gap → taper
  const Ci = [C[0] + k * Math.cos(rad(gapDeg)), C[1] + k * Math.sin(rad(gapDeg))]
  const a1 = gapDeg + 22 // end after the gap
  const a2 = gapDeg - 22 + 360 // end before the gap
  const po = (a) => [C[0] + Ro * Math.cos(rad(a)), C[1] + Ro * Math.sin(rad(a))]
  const pi = (a) => [Ci[0] + Ri * Math.cos(rad(a)), Ci[1] + Ri * Math.sin(rad(a))]
  const cap = (a) => {
    const [o, i] = [po(a), pi(a)]
    return Math.hypot(o[0] - i[0], o[1] - i[1]) / 2
  }
  return [
    `M ${f(po(a1))}`,
    `A ${Ro} ${Ro} 0 1 1 ${f(po(a2))}`, // outer edge, clockwise
    `A ${cap(a2).toFixed(1)} ${cap(a2).toFixed(1)} 0 0 1 ${f(pi(a2))}`, // round end
    `A ${Ri} ${Ri} 0 1 0 ${f(pi(a1))}`, // inner edge back
    `A ${cap(a1).toFixed(1)} ${cap(a1).toFixed(1)} 0 0 1 ${f(po(a1))}`, // round end
    'Z'
  ].join(' ')
})()
const ensoDot = (() => {
  const a = (-35 * Math.PI) / 180
  const r = 292
  return `<circle cx="${(512 + r * Math.cos(a)).toFixed(1)}" cy="${(512 + r * Math.sin(a)).toFixed(1)}" r="54" fill="${palette.haze}"/>`
})()

// G. H — a geometric lowercase h: a stem and an arch, round-capped, the arch laid over the stem.
const H_W = 140
const hStem = `<path fill="none" stroke="${palette.white}" stroke-width="${H_W}" stroke-linecap="round" d="M 362 235 L 362 789"/>`
const hArch = `<path fill="none" stroke="${palette.haze}" stroke-width="${H_W}" stroke-linecap="round" stroke-linejoin="round" d="M 362 525 A 150 150 0 0 1 662 525 L 662 789"/>`

// H. Flow — three wave strokes in three blues on paper: lines of writing, loosened.
const wave = (x0, len, y, amp, color) =>
  `<path fill="none" stroke="${color}" stroke-width="96" stroke-linecap="round" d="M ${x0} ${y} C ${x0 + len * 0.3} ${y - amp} ${x0 + len * 0.6} ${y + amp} ${x0 + len} ${y}"/>`

// ======================= set 3: with the AI sparkle =======================

// A four-point sparkle (✦) with concave sides; k pulls the controls toward the centre (thinner arms).
export const sparkle = (cx, cy, R, fill, k = 0.24) => {
  const c = R * k
  return `<path fill="${fill}" d="M ${cx} ${cy - R} Q ${cx + c} ${cy - c} ${cx + R} ${cy} Q ${cx + c} ${cy + c} ${cx} ${cy + R} Q ${cx - c} ${cy + c} ${cx - R} ${cy} Q ${cx - c} ${cy - c} ${cx} ${cy - R} Z"/>`
}

// I. Hi✦ — the geometric h, and the sparkles where the dot of an "i" would be: h + ✦ = hi (ひ).
// Stem 312, arch 312→612, main sparkle at (764, 300); the mass centre lands near x ≈ 490.
const hsStem = `<path fill="none" stroke="${palette.white}" stroke-width="${H_W}" stroke-linecap="round" d="M 312 250 L 312 790"/>`
const hsArch = `<path fill="none" stroke="${palette.haze}" stroke-width="${H_W}" stroke-linecap="round" stroke-linejoin="round" d="M 312 525 A 150 150 0 0 1 612 525 L 612 790"/>`
const hsStar = sparkle(764, 300, 116, palette.white) + sparkle(866, 432, 44, palette.white)

// J. Hi✦ light — the same mark on paper: kurenai h, lighter arch, kurenai sparkle (the inspiration's white-ground style).
const hlStem = `<path fill="none" stroke="${palette.ink}" stroke-width="${H_W}" stroke-linecap="round" d="M 312 250 L 312 790"/>`
const hlArch = `<path fill="none" stroke="${palette.inkMid}" stroke-width="${H_W}" stroke-linecap="round" stroke-linejoin="round" d="M 312 525 A 150 150 0 0 1 612 525 L 612 790"/>`
const hlStar = sparkle(764, 300, 116, palette.ink) + sparkle(866, 432, 44, palette.ink)

// K. Ensō✦ — the brush circle with the sparkle in its opening.
const ensoWidePath = (() => {
  const C = [512, 512]
  const Ro = 330
  const Ri = 218
  const gapDeg = -35
  const k = 58
  const Ci = [C[0] + k * Math.cos(rad(gapDeg)), C[1] + k * Math.sin(rad(gapDeg))]
  const a1 = gapDeg + 29
  const a2 = gapDeg - 29 + 360
  const po = (a) => [C[0] + Ro * Math.cos(rad(a)), C[1] + Ro * Math.sin(rad(a))]
  const pi = (a) => [Ci[0] + Ri * Math.cos(rad(a)), Ci[1] + Ri * Math.sin(rad(a))]
  const cap = (a) => {
    const [o, i] = [po(a), pi(a)]
    return (Math.hypot(o[0] - i[0], o[1] - i[1]) / 2).toFixed(1)
  }
  return `M ${f(po(a1))} A ${Ro} ${Ro} 0 1 1 ${f(po(a2))} A ${cap(a2)} ${cap(a2)} 0 0 1 ${f(pi(a2))} A ${Ri} ${Ri} 0 1 0 ${f(pi(a1))} A ${cap(a1)} ${cap(a1)} 0 0 1 ${f(po(a1))} Z`
})()
const ensoStar = (() => {
  const a = (-35 * Math.PI) / 180
  const r = 292
  return sparkle(
    +(512 + r * Math.cos(a)).toFixed(1),
    +(512 + r * Math.sin(a)).toFixed(1),
    104,
    palette.white
  )
})()

// L. Note✦ — a white sheet, two lines, and a kurenai sparkle on it (the doc-with-sparkle from the inspiration).
const nsSheet = `<rect x="262" y="212" width="500" height="600" rx="72" fill="${palette.white}"/>`
const nsLines = [
  [352, 352, 300],
  [352, 446, 300],
  [352, 540, 170]
]
  .map(
    ([x, y, w]) =>
      `<rect x="${x}" y="${y}" width="${w}" height="38" rx="19" fill="${palette.haze}"/>`
  )
  .join('\n')
const nsStar = sparkle(640, 690, 92, palette.ink) + sparkle(728, 776, 34, palette.ink)

// menu bar sparkle (18-grid units)
const mbSparkle = (cx, cy, R) => sparkle(cx, cy, R, '#000', 0.24)

// ---------- concepts ----------

const earlier = [
  {
    slug: 'pen',
    name: 'Pen',
    tagline: '钢笔 — 写作工具本身，像 Pages / Freeform 一族',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'line', body: penLine },
      { name: 'barrel', body: rot(PEN_TILT, barrel, -36) },
      { name: 'nib', body: rot(PEN_TILT, nib, -36) }
    ],
    menubar: `<g transform="translate(9 9) scale(0.0192) translate(-512 -512)">${rot(PEN_TILT, `<rect x="434" y="118" width="156" height="560" rx="78" fill="#000"/><path fill="#000" fill-rule="evenodd" d="${nibPath}"/>`)}<rect x="246" y="836" width="430" height="64" rx="32" fill="#000"/></g>`
  },
  {
    slug: 'hi',
    name: 'Hi',
    tagline: 'ひ — hikki 的第一个音，一笔写成的品牌字形',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'bar', body: stroke(hiBar) },
      { name: 'bowl', body: stroke(hiBowl) }
    ],
    menubar:
      `<g transform="translate(9 9) scale(0.0268) translate(-514 -552)">${stroke(hiBar, '#000')}${stroke(hiBowl, '#000')}</g>`.replaceAll(
        `stroke-width="${HI_W}"`,
        'stroke-width="68"'
      )
  },
  {
    slug: 'notebook',
    name: 'Notebook',
    tagline: '笔记本 — 封面、书脊、横线，像 Books / Journal 一族',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'cover', body: nbCover },
      { name: 'band', body: nbBand },
      { name: 'lines', body: nbLines.join('\n') }
    ],
    menubar: [
      `<rect x="3.75" y="2.25" width="10.5" height="13.5" rx="1.9" fill="none" stroke="#000" stroke-width="1.5"/>`,
      `<path fill="#000" d="M 4.9 1.5 H 6.6 V 16.5 H 4.9 A 1.9 1.9 0 0 1 3 14.6 V 3.4 A 1.9 1.9 0 0 1 4.9 1.5 Z"/>`,
      `<rect x="8.4" y="6.4" width="4" height="1.3" rx="0.65" fill="#000"/>`,
      `<rect x="8.4" y="9" width="4" height="1.3" rx="0.65" fill="#000"/>`,
      `<rect x="8.4" y="11.6" width="2.5" height="1.3" rx="0.65" fill="#000"/>`
    ].join('\n')
  },
  {
    slug: 'page',
    name: 'Page',
    tagline: '折角页 — 整个图标就是一张纸，像 Notes / Stickies 一族',
    background: { top: palette.paperTop, bottom: palette.paperBottom },
    layers: [
      { name: 'corner', body: pageCorner },
      { name: 'fold', body: pageFold },
      { name: 'lines', body: pageLines.join('\n') }
    ],
    menubar: [
      `<path fill="none" stroke="#000" stroke-width="1.5" stroke-linejoin="round" d="M 5.25 2.25 H 10.5 L 14.25 6 V 14 A 1.75 1.75 0 0 1 12.5 15.75 H 5.25 A 1.75 1.75 0 0 1 3.5 14 V 4 A 1.75 1.75 0 0 1 5.25 2.25 Z"/>`,
      `<path fill="#000" d="M 10.5 2.25 L 14.25 6 H 11.5 A 1 1 0 0 1 10.5 5 Z"/>`,
      `<rect x="6" y="8.5" width="5.8" height="1.3" rx="0.65" fill="#000"/>`,
      `<rect x="6" y="11.2" width="3.8" height="1.3" rx="0.65" fill="#000"/>`
    ].join('\n')
  }
]

const abstract = [
  {
    slug: 'leaves',
    name: 'Leaves',
    tagline: '三枚 — 三张纸扇开，像 Shortcuts / Journal 的叠片',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'left', body: sheet(palette.mist, -12) },
      { name: 'right', body: sheet(palette.mist, 12) },
      { name: 'front', body: sheet(palette.white, 0) }
    ],
    menubar: [-14, 0, 14]
      .map(
        (d) =>
          `<path stroke="#000" stroke-width="1.7" stroke-linecap="round" d="M 9 15 L 9 3.6" transform="rotate(${d} 9 24)"/>`
      )
      .join('\n')
  },
  {
    slug: 'enso',
    name: 'Ensō',
    tagline: '円相 — 一笔画的圆，粗细有起收，开口处一点',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'ring', body: `<path fill="${palette.white}" d="${ensoPath}"/>` },
      { name: 'dot', body: ensoDot }
    ],
    menubar: [
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M 13.1 4.4 A 6 6 0 1 0 14.5 7.2"/>`,
      `<circle cx="14.3" cy="4.3" r="1.35" fill="#000"/>`
    ].join('\n')
  },
  {
    slug: 'h',
    name: 'H',
    tagline: 'h — 几何小写 h，竖和拱两层相叠',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'stem', body: hStem },
      { name: 'arch', body: hArch }
    ],
    menubar: [
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M 5.6 3.2 L 5.6 14.8"/>`,
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M 5.6 9.4 A 3.4 3.4 0 0 1 12.4 9.4 L 12.4 14.8"/>`
    ].join('\n')
  },
  {
    slug: 'flow',
    name: 'Flow',
    tagline: '流 — 三行松开的字行，三种蓝落在纸上',
    background: { top: palette.paperTop, bottom: palette.paperBottom },
    layers: [
      { name: 'far', body: wave(232, 324, 652, 26, palette.mist) },
      { name: 'mid', body: wave(232, 444, 512, 26, palette.inkMid) },
      { name: 'near', body: wave(232, 560, 372, 26, palette.ink) }
    ],
    menubar: [
      [12, 5.2],
      [9, 9],
      [6, 12.8]
    ]
      .map(
        ([w, y]) =>
          `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M 3.4 ${y} C ${3.4 + w * 0.3} ${y - 0.7} ${3.4 + w * 0.6} ${y + 0.7} ${3.4 + w} ${y}"/>`
      )
      .join('\n')
  }
]

export const concepts = [
  {
    slug: 'hi-star',
    name: 'Hi✦',
    tagline: 'h + ✦ — 星芒落在 i 的点上，h 就读成了 hi',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    backgroundDark: { top: palette.inkDarkTop, bottom: palette.inkDarkBottom },
    layers: [
      { name: 'stem', body: hsStem },
      { name: 'arch', body: hsArch },
      { name: 'star', body: hsStar }
    ],
    menubar: [
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M 4.2 3.2 L 4.2 14.8"/>`,
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M 4.2 9.4 A 3.2 3.2 0 0 1 10.6 9.4 L 10.6 14.8"/>`,
      mbSparkle(14.2, 5.2, 2.6)
    ].join('\n')
  }
]

export const alternatives = [
  {
    slug: 'hi-light',
    name: 'Hi✦ light',
    tagline: '同一个 h✦ 落在白底上 — 紅色的 h，像灵感图的白底风格',
    background: { top: palette.paperTop, bottom: palette.paperBottom },
    layers: [
      { name: 'stem', body: hlStem },
      { name: 'arch', body: hlArch },
      { name: 'star', body: hlStar }
    ],
    menubar: [
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M 4.2 3.2 L 4.2 14.8"/>`,
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M 4.2 9.4 A 3.2 3.2 0 0 1 10.6 9.4 L 10.6 14.8"/>`,
      mbSparkle(14.2, 5.2, 2.6)
    ].join('\n')
  },
  {
    slug: 'enso-star',
    name: 'Ensō✦',
    tagline: '円相 + ✦ — 一笔画的圆，开口处是星芒',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'ring', body: `<path fill="${palette.white}" d="${ensoWidePath}"/>` },
      { name: 'star', body: ensoStar }
    ],
    menubar: [
      `<path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M 12.4 3.9 A 6 6 0 1 0 14.6 7.9"/>`,
      mbSparkle(14.4, 4.0, 2.4)
    ].join('\n')
  },
  {
    slug: 'note-star',
    name: 'Note✦',
    tagline: '纸 + ✦ — 白纸、两行字、一颗紅色星芒',
    background: { top: palette.inkTop, bottom: palette.inkBottom },
    layers: [
      { name: 'sheet', body: nsSheet },
      { name: 'lines', body: nsLines },
      { name: 'star', body: nsStar }
    ],
    menubar: [
      `<rect x="3.75" y="2.25" width="10.5" height="13.5" rx="2" fill="none" stroke="#000" stroke-width="1.5"/>`,
      `<rect x="6.2" y="5.6" width="5.6" height="1.3" rx="0.65" fill="#000"/>`,
      `<rect x="6.2" y="8.3" width="3.6" height="1.3" rx="0.65" fill="#000"/>`,
      mbSparkle(11.2, 12.2, 2.3)
    ].join('\n')
  },
  ...abstract,
  ...earlier
]

// ---------- output ----------

export const previewSvg = (c, bg = c.background) => `${svgOpen()}
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${bg.top}"/><stop offset="1" stop-color="${bg.bottom}"/></linearGradient>
<clipPath id="icon"><rect width="${S}" height="${S}" rx="${CORNER}"/></clipPath>
</defs>
<g clip-path="url(#icon)">
<rect width="${S}" height="${S}" fill="url(#bg)"/>
${c.layers.map((l) => l.body).join('\n')}
</g>
</svg>
`

/** A full-canvas background layer (the one thing with a gradient): drop it in first, or set it in the inspector. */
export const backgroundSvg = (bg) => `${svgOpen()}
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${bg.top}"/><stop offset="1" stop-color="${bg.bottom}"/></linearGradient></defs>
<rect width="${S}" height="${S}" fill="url(#bg)"/>
</svg>
`

export const menubarSvg = (c) => `${svgOpen('0 0 18 18', ' width="18" height="18"')}
${c.menubar}
</svg>
`

if (process.argv[1] === import.meta.filename) {
  const all = process.argv.includes('--all')
  const write = all ? [...concepts, ...alternatives] : concepts
  for (const c of write) {
    const dir = join(here, c.slug)
    rmSync(dir, { recursive: true, force: true })
    mkdirSync(dir, { recursive: true })
    writeFileSync(join(dir, '00-background.svg'), backgroundSvg(c.background))
    if (c.backgroundDark)
      writeFileSync(join(dir, '00-background-dark.svg'), backgroundSvg(c.backgroundDark))
    c.layers.forEach((l, i) =>
      writeFileSync(join(dir, `${String(i + 1).padStart(2, '0')}-${l.name}.svg`), layerFile(l.body))
    )
    writeFileSync(join(dir, 'preview.svg'), previewSvg(c))
    writeFileSync(join(dir, 'menubar.svg'), menubarSvg(c))
  }
  if (!all)
    for (const c of alternatives) rmSync(join(here, c.slug), { recursive: true, force: true })
  for (const stale of ['nib', 'sumi', 'slant'])
    rmSync(join(here, stale), { recursive: true, force: true })
  console.log(write.map((c) => `${c.slug}: ${c.layers.map((l) => l.name).join(' → ')}`).join('\n'))
}
