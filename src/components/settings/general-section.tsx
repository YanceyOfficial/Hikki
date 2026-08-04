import { open as openDialog } from '@tauri-apps/plugin-dialog'
import { revealItemInDir } from '@tauri-apps/plugin-opener'
import { useEffect, useState } from 'react'

import { Button } from '#components/ui/button'
import { backend, isTauri } from '#lib/backend/index'
import { reportError } from '#lib/errors'

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
    <div className="flex flex-col gap-4">
      <div>
        <p className="text-sm font-medium">Vault location</p>
        <p
          data-testid="vault-path"
          className="text-muted-foreground mt-1 truncate text-sm"
        >
          {vaultPath}
        </p>
        <div className="mt-2 flex gap-2">
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
      </div>
      <div>
        <p className="text-sm font-medium">Search index</p>
        <Button
          variant="outline"
          size="sm"
          className="mt-2"
          onClick={rebuildIndex}
          disabled={rebuilding}
          data-testid="rebuild-index"
        >
          {rebuilding ? 'Rebuilding…' : 'Rebuild index'}
        </Button>
      </div>
    </div>
  )
}
