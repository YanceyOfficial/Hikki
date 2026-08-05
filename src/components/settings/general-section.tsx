import { open as openDialog } from '@tauri-apps/plugin-dialog'
import { revealItemInDir } from '@tauri-apps/plugin-opener'
import { Laptop, Moon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'

import { Button } from '#components/ui/button'
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldTitle
} from '#components/ui/field'
import { backend, isTauri } from '#lib/backend/index'
import { reportError } from '#lib/errors'

const APPEARANCE_MODES = [
  { value: 'system', label: 'System', icon: Laptop },
  { value: 'light', label: 'Light', icon: Sun },
  { value: 'dark', label: 'Dark', icon: Moon }
] as const

// Vercel-style pill switcher: sr-only radio inputs + peer-checked labels
// (per the reference), restyled onto this app's own tokens (bg-muted /
// text-muted-foreground / text-foreground) instead of Vercel's own
// site-specific gray/background-100 scale. `data-testid` lives on the
// <label> - the actual element a real click lands on - rather than the
// visually-hidden <input>, which native label-click delegation still
// correctly toggles (confirmed live and via the unit tests below).
function AppearanceSwitcher() {
  const { theme, setTheme } = useTheme()

  return (
    <div className="bg-muted inline-flex w-fit gap-0.5 rounded-full p-0.5">
      {APPEARANCE_MODES.map(({ value, label, icon: Icon }) => (
        <span key={value}>
          <input
            className="peer sr-only"
            type="radio"
            id={`appearance-mode-${value}`}
            name="appearance-mode"
            value={value}
            checked={theme === value}
            onChange={(e) => setTheme(e.target.value)}
          />
          <label
            htmlFor={`appearance-mode-${value}`}
            data-testid={`appearance-mode-${value}`}
            aria-label={label}
            className="text-muted-foreground peer-checked:bg-background peer-checked:text-foreground flex size-7 cursor-pointer items-center justify-center rounded-full transition-colors peer-checked:shadow-sm"
          >
            <Icon className="size-4" />
          </label>
        </span>
      ))}
    </div>
  )
}

export function GeneralSection() {
  const [vaultPath, setVaultPath] = useState('')
  const [rebuilding, setRebuilding] = useState(false)

  useEffect(() => {
    backend.getVaultInfo().then((info) => setVaultPath(info.vaultPath))
  }, [])

  const changeVaultPath = async () => {
    const selected = await openDialog({ directory: true })
    if (!selected) return
    try {
      const info = await backend.setVaultPath(selected)
      setVaultPath(info.vaultPath)
    } catch (err) {
      reportError('HK-1005', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  const revealVaultInFinder = async () => {
    await revealItemInDir(vaultPath)
  }

  const rebuildIndex = async () => {
    setRebuilding(true)
    try {
      await backend.rebuildIndex()
    } catch (err) {
      reportError('HK-2001', {
        message: err instanceof Error ? err.message : String(err)
      })
    } finally {
      setRebuilding(false)
    }
  }

  return (
    <FieldGroup>
      <Field>
        <FieldTitle>Appearance</FieldTitle>
        <div>
          <AppearanceSwitcher />
        </div>
      </Field>
      <Field>
        <FieldTitle>Vault location</FieldTitle>
        <FieldDescription data-testid="vault-path" className="truncate">
          {vaultPath}
        </FieldDescription>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={changeVaultPath}
            data-testid="change-vault-path"
          >
            Change…
          </Button>
          {isTauri() && (
            <Button
              variant="outline"
              size="sm"
              onClick={revealVaultInFinder}
              data-testid="reveal-vault-path"
            >
              Reveal in Finder
            </Button>
          )}
        </div>
      </Field>
      <Field>
        <FieldTitle>Search index</FieldTitle>
        <div>
          <Button
            variant="outline"
            size="sm"
            onClick={rebuildIndex}
            disabled={rebuilding}
            data-testid="rebuild-index"
          >
            {rebuilding ? 'Rebuilding…' : 'Rebuild index'}
          </Button>
        </div>
      </Field>
    </FieldGroup>
  )
}
