import { getVersion } from '@tauri-apps/api/app'
import { useEffect, useState } from 'react'

import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldTitle
} from '#components/ui/field'

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
    <FieldGroup>
      <Field>
        <FieldTitle>Hikki</FieldTitle>
        <FieldDescription data-testid="app-version">
          Version {version}
        </FieldDescription>
      </Field>
    </FieldGroup>
  )
}
