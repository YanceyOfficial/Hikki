import { getVersion } from '@tauri-apps/api/app'
import { useEffect, useState } from 'react'

export function AboutSection() {
  // `getVersion()` calls Tauri's IPC bridge (`window.__TAURI_INTERNALS__.invoke`),
  // which doesn't exist in a plain browser (Vite dev server, Playwright) - it
  // rejects there, so "dev" stays as a readable placeholder instead of
  // gating the call behind `isTauri()`, which would also skip it under the
  // mocked-`getVersion` unit test (jsdom never sets `__TAURI_INTERNALS__`).
  const [version, setVersion] = useState('dev')

  useEffect(() => {
    getVersion()
      .then(setVersion)
      .catch(() => {})
  }, [])

  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-medium">Hikki</p>
      <p data-testid="app-version" className="text-muted-foreground text-sm">
        Version {version}
      </p>
    </div>
  )
}
