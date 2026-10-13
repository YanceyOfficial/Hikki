import { writeFileSync } from 'node:fs'

import { wordmark, lockup, fonts } from '../logo/generate.mjs'
// Exploration page: the chosen mark first, every alternative collapsed below. Run:
//   node design/icon/build-concepts-page.mjs <out.html>
import { concepts, alternatives, previewSvg, menubarSvg, palette } from './generate.mjs'

const uri = (svg) => 'data:image/svg+xml;utf8,' + encodeURIComponent(svg)
const layerSvg = (body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${body}</svg>`
const byOrder = concepts
const pick = (slugs) => slugs.map((s) => alternatives.find((c) => c.slug === s))
const sparkleOrder = pick(['enso-star', 'note-star', 'hi-light'])
const abstractOrder = pick(['enso', 'leaves', 'h', 'flow'])
const earlierOrder = pick(['notebook', 'page', 'pen', 'hi'])

const notes = {
  'enso-star': {
    zh: '円相 + ✦',
    why: '上一轮推荐的円相，开口里换成星芒：一笔画的圆是"笔记"，星芒是 AI。两层，形状最独特，也最像一个"会发光"的东西。',
    risk: '白圈 + 红底仍有日之丸联想；星芒把它拉向"AI 工具"而不是国旗。',
    sizes: '32 px 下环和星芒都还在。'
  },
  'hi-star': {
    zh: 'h + ✦',
    why: '把上一轮太素的 h 补足：星芒放在 i 的点的位置，h✦ 读成 hi（也是 ひ）。竖、拱、星芒三层，拱压竖、星芒浮在最上。',
    risk: '字母标最"产品化"；靠星芒和紅色和系统应用拉开。',
    sizes: '32 px 下 h 和大星芒都清楚，小星芒退成一点光。'
  },
  'note-star': {
    zh: '纸 + ✦',
    why: '灵感图右上那格的 Apple 化：白纸、两行字、一颗紅色星芒压在纸上。一眼就是"AI 笔记"。',
    risk: '最直白，也最容易和别的 AI 笔记应用撞车。',
    sizes: '32 px 下纸和星芒都清楚。'
  },
  'hi-light': {
    zh: 'h + ✦ 白底',
    why: '同一个 h✦ 换到白底上：紅色的竖、浅紅的拱、紅色星芒。灵感图里那种"白底 + 一个彩色标"的气质，Dock 里和 Reminders / Freeform 同族。',
    risk: '白底图标在浅色桌面上存在感弱一些；Liquid Glass 的玻璃感在白底上也淡。',
    sizes: '各尺寸都清楚。'
  },
  leaves: {
    zh: '三枚',
    why: '三张纸绕着图标下方的一个轴扇开，就是你说的"花瓣"：两张淡红在后、白色在前，叠压处正是 Liquid Glass 最好看的地方。笔记本的纸页，抽象到只剩三个圆角矩形。',
    risk: '三张卡片也可能被读成 Wallet / 相册；靠竖长的纸页比例和单一色相区分。',
    sizes: '32 px 仍是"一叠纸"的剪影。'
  },
  enso: {
    zh: '円相',
    why: '一笔画的圆：左下起笔最粗，到开口处收细，开口里落一点。最有书法感、最独特，白圈落在紅色上也最"日本"。',
    risk: '白圈在红底上会让人想到日之丸或"录制"键；靠缺口、粗细变化和那一点避开。',
    sizes: '32 px 下仍是一个有缺口的环。'
  },
  h: {
    zh: 'h',
    why: 'hikki 的小写 h 拆成竖和拱两层，拱压在竖上。几何、干净，像 Font Book 那样用一个字母做图标。',
    risk: '字母图标最"产品化"、最不像系统应用；h 本身也不带"笔记"含义。',
    sizes: '各尺寸都清楚。'
  },
  notebook: {
    zh: '笔记本',
    why: '封面、书脊、横线三层叠压，最直白地对应"筆記"。',
    risk: 'Tinted 模式里书脊和横线接近白色，可能和封面融在一起。',
    sizes: '32 px 仍能看出一本书。'
  },
  page: {
    zh: '折角页',
    why: '整个图标是一张纸，紅色折角是唯一的识别点。',
    risk: '折角是通用的"文档"隐喻。',
    sizes: '32 px 下折角依然清楚。'
  },
  pen: {
    zh: '钢笔',
    why: '笔尖叠在笔杆上，划线在最底层。',
    risk: '题材最接近 Pages。',
    sizes: '各尺寸都清楚是一支笔。'
  },
  hi: {
    zh: 'ひ',
    why: 'hikki 的第一个音写成两笔。',
    risk: '不认识假名的人会读成钩子或 G。',
    sizes: '32 px 下是一个干净的环。'
  },
  flow: {
    zh: '流',
    why: '三行字松开成三条波纹，三种紅由深到浅落在白纸上，走 Freeform 的白底彩笔路线。',
    risk: '三条波纹容易读成水波或 Wi-Fi；它是四个里最"图形"、最不像笔记的。',
    sizes: '32 px 下三条线仍分得开。'
  }
}

const alts = [
  { name: 'Kurenai（默认）', top: palette.inkTop, bottom: palette.inkBottom },
  { name: 'Kurenai deep', top: '#E8405A', bottom: '#A80030' },
  { name: 'Vermilion', top: '#FF7A4D', bottom: '#E8401A' },
  { name: 'Ink', top: '#6B8AFB', bottom: '#3350E0' },
  { name: 'Graphite', top: '#6C7183', bottom: '#30333F' }
]

const css = `
<title>Hikki Icon Concepts</title>
<style>
/* layout: one column of concept sheets, each a grid of preview / sizes / layers; the dock strips are real icon sizes */
:root{
  --bg:#f6f6f4; --fg:#37352f; --fg-2:rgba(55,53,47,.62); --fg-3:rgba(55,53,47,.42);
  --card:#ffffff; --line:rgba(55,53,47,.1); --well:#e9eaf0; --well-deep:#8d93a8;
  --dock:#2a2b31; --dock-light:#dfe2ea; --accent:#D7003A; --accent-soft:#ffe3e7;
  --font:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Hiragino Sans",system-ui,sans-serif;
  --mono:ui-monospace,"SF Mono",Menlo,monospace;
}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){
  --bg:#191919; --fg:rgba(255,255,255,.86); --fg-2:rgba(255,255,255,.6); --fg-3:rgba(255,255,255,.42);
  --card:#232326; --line:rgba(255,255,255,.1); --well:#2f3038; --well-deep:#5c6070;
  --dock:#111114; --dock-light:#c9ccd6; --accent:#ff8a9a; --accent-soft:#4a1f27; color-scheme:dark}}
:root[data-theme="dark"]{
  --bg:#191919; --fg:rgba(255,255,255,.86); --fg-2:rgba(255,255,255,.6); --fg-3:rgba(255,255,255,.42);
  --card:#232326; --line:rgba(255,255,255,.1); --well:#2f3038; --well-deep:#5c6070;
  --dock:#111114; --dock-light:#c9ccd6; --accent:#ff8a9a; --accent-soft:#4a1f27; color-scheme:dark}
body{background:var(--bg);color:var(--fg);font-family:var(--font);font-size:15px;line-height:1.55;padding-inline:20px;padding-block:32px 64px}
main{max-width:1040px;margin:0 auto;display:flex;flex-direction:column;gap:40px}
h1{font-size:30px;line-height:1.15;letter-spacing:-.02em;margin:0 0 6px;text-wrap:balance}
h2{font-size:21px;letter-spacing:-.015em;margin:0}
h3{font-size:16px;margin:0}
p{margin:0}
.lede{color:var(--fg-2);max-width:62ch}
.eyebrow{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--fg-3);font-weight:600}
.sheet{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:22px;display:grid;gap:22px;grid-template-columns:minmax(0,1fr) minmax(0,1.4fr)}
.sheet>*{min-width:0}
.sheet .head{grid-column:1/-1;display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
.sheet .head .zh{color:var(--fg-2)}
.pick{margin-left:auto;font-size:12px;font-weight:600;color:var(--accent);background:var(--accent-soft);padding:3px 10px;border-radius:999px}
.hero{display:flex;flex-direction:column;gap:14px;align-items:flex-start}
.hero img.big{width:100%;max-width:320px;aspect-ratio:1;border-radius:22%;box-shadow:0 10px 30px rgba(0,0,0,.14)}
.dock{display:flex;gap:16px;align-items:flex-end;padding:12px 14px;border-radius:14px;background:var(--dock-light)}
.dock.dark{background:var(--dock)}
.dock img{display:block;border-radius:22%}
.side{display:flex;flex-direction:column;gap:18px}
.notes{display:grid;gap:8px;font-size:14px}
.notes b{font-weight:600}
.layers{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-start}
.layer{display:flex;flex-direction:column;gap:6px;align-items:center;font-size:12px;color:var(--fg-2)}
.layer img{width:96px;height:96px;border-radius:14px;background:var(--well-deep)}
.layer.light img{background:var(--well)}
.layer code{font-family:var(--mono);font-size:11px;color:var(--fg-3)}
.arrow{align-self:center;color:var(--fg-3);font-size:18px;padding-bottom:22px}
.menubar{display:flex;flex-direction:column;gap:8px}
.bar{display:flex;align-items:center;gap:14px;height:30px;padding:0 12px;border-radius:8px;background:rgba(255,255,255,.78);color:#222;font-size:13px}
.bar.dark{background:rgba(32,32,36,.95);color:#eee}
.bar img{width:18px;height:18px}
.bar.dark img{filter:invert(1)}
.bar .time{margin-left:auto;font-variant-numeric:tabular-nums}
.bgs{display:flex;gap:14px;flex-wrap:wrap}
.bgs figure{margin:0;display:flex;flex-direction:column;gap:6px;align-items:center;font-size:12px;color:var(--fg-2)}
.bgs img{width:96px;height:96px;border-radius:22%}
.bgs code{font-family:var(--mono);font-size:11px;color:var(--fg-3)}
ol{margin:0;padding-left:22px;display:grid;gap:6px;max-width:72ch}
code.k{font-family:var(--mono);font-size:13px;background:var(--well);padding:1px 5px;border-radius:5px}
.two{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:22px}
@media (max-width:720px){.sheet{grid-template-columns:1fr}.pick{margin-left:0}}
@media (prefers-reduced-motion:no-preference){.hero img.big{transition:transform .25s}.hero img.big:hover{transform:translateY(-2px)}}
</style>`

const sheet = (c, i) => {
  const n = notes[c.slug]
  const pv = uri(previewSvg(c))
  const mb = uri(menubarSvg(c))
  const lightLayers = c.slug === 'page' || c.slug === 'flow' || c.slug === 'hi-light'
  return `<section class="sheet" id="${c.slug}">
  <div class="head"><h2>${c.name}</h2><span class="zh">${n.zh} · ${c.tagline.split(' — ')[1]}</span>${i === 0 ? '<span class="pick">选定</span>' : ''}</div>
  <div class="hero">
    <img class="big" src="${pv}" alt="${c.name} icon">
    <div class="dock"><img src="${pv}" width="128" height="128" alt=""><img src="${pv}" width="64" height="64" alt=""><img src="${pv}" width="32" height="32" alt=""></div>
    <div class="dock dark"><img src="${pv}" width="128" height="128" alt=""><img src="${pv}" width="64" height="64" alt=""><img src="${pv}" width="32" height="32" alt=""></div>
  </div>
  <div class="side">
    <div class="notes"><p><b>为什么</b> ${n.why}</p><p><b>风险</b> ${n.risk}</p><p><b>小尺寸</b> ${n.sizes}</p></div>
    <div><div class="eyebrow" style="margin-bottom:8px">图层（拖入顺序 · <span style="text-transform:none">design/icon/${c.slug}/</span>）</div>
      <div class="layers">${c.layers
        .map(
          (l, k) =>
            `<div class="layer${lightLayers ? ' light' : ''}"><img src="${uri(layerSvg(l.body))}" alt="layer ${k + 1}: ${l.name}"><span>${k + 1} · ${l.name}</span><code>0${k + 1}-${l.name}.svg</code></div>`
        )
        .join('<span class="arrow">→</span>')}</div>
    </div>
    <div class="menubar"><div class="eyebrow">菜单栏（template image，18 pt）</div>
      <div class="bar"><img src="${mb}" alt="menu bar glyph">Hikki<span class="time">15:52</span></div>
      <div class="bar dark"><img src="${mb}" alt="">Hikki<span class="time">15:52</span></div>
    </div>
  </div>
</section>`
}

const nbk = byOrder[0]
const uriSvg = (svg) => uri(svg)
const wordSection = `<section>
  <div class="eyebrow" style="margin-bottom:6px">字标</div>
  <h2 style="margin-bottom:6px">hikki，星芒做最后一个 i 的点</h2>
  <p class="lede" style="margin-bottom:16px">小写几何无衬线，字距略收。推荐 Outfit（k 的形状更有辨识度），Poppins 最接近灵感图。文件在 design/logo/。</p>
  <div class="two">
    ${Object.keys(fonts)
      .map(
        (
          f
        ) => `<div style="display:flex;flex-direction:column;gap:10px"><div class="eyebrow">${f}${f === 'outfit' ? ' · 推荐' : ''}</div>
      <div style="background:#fff;border:1px solid var(--line);border-radius:14px;padding:22px 28px"><img src="${uriSvg(wordmark(f, 'light').svg)}" alt="hikki wordmark, ${f}" style="height:64px;display:block"></div>
      <div style="background:#1c1c1c;border-radius:14px;padding:22px 28px"><img src="${uriSvg(wordmark(f, 'dark').svg)}" alt="" style="height:64px;display:block"></div></div>`
      )
      .join('')}
  </div>
  <div class="eyebrow" style="margin:22px 0 8px">组合（图标 + 字标）</div>
  <div class="two">
    ${concepts
      .map((c) => {
        return `<div style="display:flex;flex-direction:column;gap:10px">
      <div style="background:#fff;border:1px solid var(--line);border-radius:14px;padding:22px 28px"><img src="${uriSvg(lockup(c, 'outfit', 'light'))}" alt="lockup ${c.slug}" style="height:64px;display:block"></div>
      <div style="background:#1c1c1c;border-radius:14px;padding:22px 28px"><img src="${uriSvg(lockup(c, 'outfit', 'dark'))}" alt="" style="height:64px;display:block"></div></div>`
      })
      .join('')}
  </div>
</section>`

const sparkleSection = `<details><summary style="cursor:pointer;color:var(--fg-2)">同轮的其它三个（Ensō✦、Note✦、Hi✦ light）</summary><div style="display:flex;flex-direction:column;gap:24px;margin-top:20px">${sparkleOrder.map((c) => sheet(c, -1)).join('\n')}</div></details>`

const abstractSection = `<details><summary style="cursor:pointer;color:var(--fg-2)">抽象的四个（Ensō、Leaves、H、Flow）</summary><div style="display:flex;flex-direction:column;gap:24px;margin-top:20px">${abstractOrder.map((c) => sheet(c, -1)).join('\n')}</div></details>`

const earlierSection = `<details><summary style="cursor:pointer;color:var(--fg-2)">第一组（具象的四个，留作对比）</summary><div style="display:flex;flex-direction:column;gap:24px;margin-top:20px">${earlierOrder.map((c) => sheet(c, -1)).join('\n')}</div></details>`

const bgSection = `<section>
  <div class="eyebrow" style="margin-bottom:6px">底色</div>
  <h2 style="margin-bottom:6px">背景在 Icon Composer 里设，不在图层里</h2>
  <p class="lede" style="margin-bottom:16px">默认是 Kurenai 的竖向渐变：顶部 ${palette.inkTop}，底部 ${palette.inkBottom}（紅 #D7003A）。图层只有白和两级淡红，换底色只改两个色值。</p>
  <div class="bgs">${alts.map((a) => `<figure><img src="${uri(previewSvg(nbk, a))}" alt="${a.name}"><figcaption>${a.name}</figcaption><code>${a.top} → ${a.bottom}</code></figure>`).join('')}</div>
</section>`

const steps = `<section class="two">
  <div>
    <div class="eyebrow" style="margin-bottom:6px">Icon Composer</div>
    <ol>
      <li>File → New，保留 iOS / iPadOS / macOS（方形）。</li>
      <li>把一个方案的 <code class="k">01-… 02-… 03-…</code> 一起拖到画布上，编号即叠放顺序（01 在最底）。</li>
      <li>Background → Fill → Gradient，填上面的两个色值（或 Automatic Gradient 只填底部色）。</li>
      <li>Group 先用 Specular 开、Shadow neutral ≈ 0.5、Translucency ≈ 0.3（exodus 的参数），Leaves 的后两张可以略加 Blur 拉开前后。</li>
      <li>切到 Dark / Clear / Tinted 检查：Tinted 按图层亮度生成，淡红层和白层亮度接近时给淡红层单独指定深一点的填色。</li>
      <li>存成 <code class="k">Hikki/Resources/AppIcon.icon</code>，Project.swift 加进资源并设 <code class="k">ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon</code>。</li>
    </ol>
  </div>
  <div>
    <div class="eyebrow" style="margin-bottom:6px">菜单栏图标</div>
    <p style="max-width:48ch">每个方案的 <code class="k">menubar.svg</code> 是黑色模板图：18 × 18 pt、1.5 pt 线宽。放进 asset catalog（Single Scale、Preserve Vector Data、Render As → Template Image），由 <code class="k">MenuBarExtra</code> 引用，系统自动适配亮暗菜单栏。</p>
  </div>
</section>`

const html = `${css}
<main>
  <header>
    <div class="eyebrow" style="margin-bottom:8px">Hikki · app icon</div>
    <h1>Hi✦：h 加星芒，紅色底</h1>
    <p class="lede">选定的方向。品牌色 Kurenai（紅），AI 的星芒（✦）是独立的最上层。图层按 Icon Composer 的规矩做：1024 画布、纯色平涂、按编号拖入后由 Liquid Glass 给每层和叠压处上效果。下面还有 hikki 字标（星芒做最后一个 i 的点）和图标 + 字标的组合；探索过的其它方向折叠在最后。</p>
  </header>
  ${byOrder.map(sheet).join('\n')}
  ${wordSection}
  ${bgSection}
  ${steps}
  ${sparkleSection}
  ${abstractSection}
  ${earlierSection}
</main>`
writeFileSync(process.argv[2], html)
console.log('page bytes', html.length)
