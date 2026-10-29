import { row } from './row'
import { StoreStatus } from './store'
import { ThemeSwitch } from './theme-switch'
import { Wordmark } from './wordmark'

/**
 * One row: the mark, the sections, Hikki Community in a red cell of its own (another part of the site, not a section
 * of this page), the appearance switch and where the app stands. The cells take their own widths
 * (a 12-column split broke the trailing cell at laptop widths); below `lg` the sections keep two, and where
 * the app stands waits for `xl`. On a phone it is
 * one short cell: mark and switch.
 */
export function Header() {
  return (
    <header class={`${row} md:grid-cols-[auto_1fr_auto_auto]`}>
      <div class="cell flex items-center justify-between gap-3 p-3 md:p-5">
        <a href="/" class="flex items-center gap-3" aria-label="Hikki home">
          <img src="/icon.png" alt="" width="44" height="44" class="rounded-[10px]" />
          <Wordmark class="h-10 w-auto md:h-11" />
        </a>
        <ThemeSwitch class="md:hidden" />
      </div>
      <nav
        class="cell text-caption hidden items-center gap-x-5 p-5 font-semibold whitespace-nowrap md:flex lg:gap-x-6"
        aria-label="Sections"
      >
        <a href="/#local-first" class="hidden underline-offset-4 hover:underline lg:inline">
          Local-first
        </a>
        <a href="/#devices" class="underline-offset-4 hover:underline">
          Devices
        </a>
        <a href="/#ai" class="hidden underline-offset-4 hover:underline lg:inline">
          AI
        </a>
        <a href="/#features" class="underline-offset-4 hover:underline">
          Features
        </a>
        <a href="/#price" class="hidden underline-offset-4 hover:underline lg:inline">
          Price
        </a>
      </nav>
      <a
        href="/community"
        class="cell bg-red community-cell hidden items-center gap-2 px-4 py-5 md:flex lg:px-8"
      >
        Community
        <span aria-hidden="true">→</span>
      </a>
      <div class="cell hidden items-center gap-4 p-5 md:flex">
        <ThemeSwitch />
        <StoreStatus class="hidden xl:inline-flex" />
      </div>
    </header>
  )
}
