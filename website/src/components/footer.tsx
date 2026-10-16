import { row } from './row'

export function Footer() {
  return (
    <footer class={`${row} grid-cols-1 md:grid-cols-12`}>
      <div class="cell bg-red md:col-span-2" aria-hidden="true" />
      <p class="cell m-0 p-6 text-[15px] text-muted md:col-span-7">
        Hikki keeps your notes on your devices. © 2026 Hikki.
      </p>
      <div class="cell flex items-center p-6 md:col-span-3 md:justify-end">
        <img src="/wordmark.svg" alt="Hikki" class="h-6 w-auto" />
      </div>
    </footer>
  )
}
