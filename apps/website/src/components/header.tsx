import { row } from './row'
import { StoreStatus } from './store'
import { ThemeSwitch } from './theme-switch'
import { Wordmark } from './wordmark'

/**
 * One row: the mark, the sections, the appearance switch and where the app stands. The cells take their own widths
 * (a 12-column split broke the trailing cell at laptop widths). On a phone it is one short cell: mark and switch.
 */
export function Header() {
  return (
    <header class={`${row} md:grid-cols-[auto_1fr_auto]`}>
      <div class="cell flex items-center justify-between gap-3 p-3 md:p-5">
        <a href="/" class="flex items-center gap-3" aria-label="Hikki home">
          <img src="/icon.png" alt="" width="44" height="44" class="rounded-[10px]" />
          <Wordmark class="h-10 w-auto md:h-11" />
        </a>
        <ThemeSwitch class="md:hidden" />
      </div>
      <nav
        class="cell text-caption hidden items-center gap-x-6 p-5 font-semibold md:flex"
        aria-label="Sections"
      >
        <a href="/#local-first" class="underline-offset-4 hover:underline">
          Local-first
        </a>
        <a href="/#devices" class="underline-offset-4 hover:underline">
          Devices
        </a>
        <a href="/#ai" class="underline-offset-4 hover:underline">
          AI
        </a>
        <a href="/#features" class="underline-offset-4 hover:underline">
          Features
        </a>
        <a href="/#price" class="underline-offset-4 hover:underline">
          Price
        </a>
      </nav>
      <div class="cell hidden items-center gap-4 p-5 md:flex">
        <ThemeSwitch />
        <StoreStatus class="hidden lg:inline-flex" />
      </div>
    </header>
  )
}
