// A Mac App Store screenshot (2880 × 1800) from a window capture (`screencapture -l <window id>`, shadow included):
// the window scaled to fit, centred on a quiet warm backdrop.
//
//   node design/store/mac-frame.mjs <window.png> <out.png>
import { createRequire } from 'node:module'

const sharp = createRequire(new URL('../../apps/website/package.json', import.meta.url))('sharp')
const [input, output] = process.argv.slice(2)
const W = 2880
const H = 1800
const backdrop = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
    <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#f6f1ea"/><stop offset="1" stop-color="#ead9d3"/>
    </linearGradient></defs>
    <rect width="100%" height="100%" fill="url(#g)"/>
  </svg>`
)
const window = await sharp(input)
  .resize({ width: W - 240, height: H - 140, fit: 'inside' })
  .toBuffer()
const { width, height } = await sharp(window).metadata()
await sharp(backdrop)
  .composite([
    { input: window, left: Math.round((W - width) / 2), top: Math.round((H - height) / 2) }
  ])
  .png()
  .toFile(output)
console.log(output)
