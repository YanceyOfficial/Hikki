import { AppStoreButton } from './app-store-button'
import { row } from './row'
import { ThemeSwitch } from './theme-switch'

export function Header() {
  return (
    <header class={`${row} grid-cols-1 md:grid-cols-12`}>
      <a href="/" class="cell flex items-center gap-3 p-5 md:col-span-3" aria-label="Hikki home">
        <img src="/icon.png" alt="" width="44" height="44" class="rounded-[10px]" />
        <img src="/wordmark.svg" alt="Hikki" class="wordmark h-11 w-auto" />
      </a>
      <nav class="cell flex flex-wrap items-center gap-x-8 gap-y-2 p-5 text-[15px] font-semibold md:col-span-6">
        <a href="#local-first" class="underline-offset-4 hover:underline">
          Local-first
        </a>
        <a href="#devices" class="underline-offset-4 hover:underline">
          iPhone, iPad, Mac
        </a>
        <a href="#ai" class="underline-offset-4 hover:underline">
          AI
        </a>
        <a href="#features" class="underline-offset-4 hover:underline">
          Features
        </a>
      </nav>
      <div class="cell flex flex-wrap items-center gap-3 p-5 md:col-span-3 md:justify-end">
        <ThemeSwitch />
        <AppStoreButton />
      </div>
    </header>
  )
}
