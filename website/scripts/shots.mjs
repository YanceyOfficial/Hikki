// bun run shots <folder>: each capture named in shots.json → public/shots/<name>.webp (cropped, at most `width`
// wide, compressed). Captures stay out of the repository; the WebP files are what the page loads.
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

import sharp from 'sharp'

const root = new URL('..', import.meta.url).pathname
const folder = process.argv[2]
if (!folder) throw new Error('usage: bun run shots <folder of captures>')
const manifest = JSON.parse(readFileSync(join(root, 'shots.json'), 'utf8'))

for (const [name, options] of Object.entries(manifest)) {
  if (name.startsWith('$')) continue
  const source = join(folder, `${options.from ?? name}.png`)
  if (!existsSync(source)) {
    console.warn(`skip ${name}: no ${source}`)
    continue
  }
  // .rotate() applies the capture's orientation first (simulator captures in landscape carry one).
  let image = sharp(source).rotate()
  if (options.extract) image = sharp(await image.toBuffer()).extract(options.extract)
  if (options.width) image = image.resize({ width: options.width, withoutEnlargement: true })
  const out = join(root, 'public/shots', `${name}.webp`)
  const info = await image.webp({ quality: 86, smartSubsample: true, effort: 6 }).toFile(out)
  console.log(`${name}.webp ${info.width}×${info.height} ${Math.round(info.size / 1024)} KB`)
}
