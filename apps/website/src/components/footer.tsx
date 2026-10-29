import { CONTACT_EMAIL, PRIVACY_PATH } from '../site'
import { row } from './row'
import { Wordmark } from './wordmark'

export function Footer() {
  return (
    <footer class={`${row} grid-cols-1 md:grid-cols-12`}>
      <div class="cell bg-red hidden md:col-span-2 md:block" aria-hidden="true" />
      <div class="cell text-caption flex flex-col gap-3 p-5 md:col-span-7 md:p-6">
        <p class="m-0 text-muted">Hikki keeps your notes on your devices. © 2026 Hikki.</p>
        <nav class="flex flex-wrap gap-x-6 gap-y-1 font-semibold" aria-label="More">
          <a href="/community" class="underline-offset-4 hover:underline">
            Hikki Community
          </a>
          <a href={PRIVACY_PATH} class="underline-offset-4 hover:underline">
            Privacy
          </a>
          <a href={`mailto:${CONTACT_EMAIL}`} class="underline-offset-4 hover:underline">
            Contact
          </a>
        </nav>
      </div>
      <div class="cell flex items-center p-5 md:col-span-3 md:justify-end md:p-6">
        <Wordmark class="h-6 w-auto" />
      </div>
    </footer>
  )
}
