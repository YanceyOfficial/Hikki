import { APP_STORE_URL, GITHUB_URL, notifyLink } from '../site'

/**
 * The download moment. Before the listing exists the status is a line, never a button: `StoreStatus` says so in the
 * header, and `StoreActions` at the foot gives the visitor something to do today — write to be told, or watch the
 * releases. Once `APP_STORE_URL` is set, both become the download link.
 */
export function StoreStatus(props: { class?: string }) {
  if (APP_STORE_URL) {
    return (
      <a class={`button ${props.class ?? ''}`} href={APP_STORE_URL}>
        <AppleGlyph />
        Download
      </a>
    )
  }
  return (
    <span class={`text-caption items-center gap-2 font-semibold text-muted ${props.class ?? ''}`}>
      <AppleGlyph />
      Coming to the App Store
    </span>
  )
}

export function StoreActions() {
  return (
    <div class="flex flex-wrap items-center gap-x-8 gap-y-4">
      {APP_STORE_URL ? (
        <a class="button" href={APP_STORE_URL}>
          <AppleGlyph />
          Download on the App Store
        </a>
      ) : (
        <a class="button" href={notifyLink('Tell me when Hikki ships')}>
          Tell me when it ships
        </a>
      )}
      <a href={GITHUB_URL} class="text-caption font-semibold underline underline-offset-4">
        Releases on GitHub
      </a>
    </div>
  )
}

function AppleGlyph() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
      <path
        fill="currentColor"
        d="M16.37 12.68c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.82-.81-3-.79-1.54.02-2.96.9-3.76 2.27-1.6 2.78-.41 6.9 1.15 9.16.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.77.74 2.98.72 1.24-.02 2.02-1.12 2.77-2.23.87-1.28 1.23-2.52 1.25-2.58-.03-.01-2.4-.92-2.38-3.68ZM14.1 5.92c.63-.77 1.06-1.83.94-2.89-.91.04-2.01.61-2.67 1.37-.58.67-1.09 1.75-.96 2.79 1.02.08 2.05-.52 2.69-1.27Z"
      />
    </svg>
  )
}
