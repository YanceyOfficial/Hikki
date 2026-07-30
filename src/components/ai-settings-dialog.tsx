import { useEffect, useState } from 'react'
import { toast } from 'sonner'

import { Button } from '#components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger
} from '#components/ui/dialog'
import { Input } from '#components/ui/input'
import { AI_PROVIDER_IDS, getAiModels, type AiProviderId } from '#lib/ai/models'
import { backend } from '#lib/backend/index'

// Plain native <select>s, not the `combobox.tsx` primitive: that component
// wraps @base-ui/react's async Combobox (its own `input-group.tsx`
// dependency, portal/positioner machinery, collection-filtering) which is
// built for a searchable, dynamically-loaded item list. The provider list is
// two fixed ids and the model list is a small synchronous array already
// filtered by provider - there's nothing to search and nothing loads
// asynchronously, so the combobox's extra machinery would be pure overhead.
// A native <select> also matches this app's existing low-key form patterns
// (see `Input` above) better than pulling in a heavier styled primitive for
// a one-off. Revisit if/when Phase 4's full Settings shell needs a richer,
// searchable model picker.
const selectClassName =
  'h-8 rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30'

type ConnectionTestState = 'idle' | 'testing' | 'ok' | 'error'

const TEST_STATE_LABEL: Record<ConnectionTestState, string> = {
  idle: 'Test connection',
  testing: 'Testing…',
  ok: 'Connected',
  error: 'Failed'
}

export function AiSettingsDialog() {
  const [open, setOpen] = useState(false)
  const [keys, setKeys] = useState<Record<AiProviderId, string>>({
    openai: '',
    anthropic: ''
  })
  const [testState, setTestState] = useState<
    Record<AiProviderId, ConnectionTestState>
  >({ openai: 'idle', anthropic: 'idle' })
  const [defaultProvider, setDefaultProvider] = useState<string>('')
  const [defaultModel, setDefaultModel] = useState<string>('')

  useEffect(() => {
    if (!open) return
    backend
      .getAiSettings()
      .then((settings) => {
        setDefaultProvider(settings.defaultAiProvider ?? '')
        setDefaultModel(settings.defaultAiModel ?? '')
      })
      .catch((err) => {
        // Without this `.catch`, a rejected `getAiSettings()` IPC call (e.g.
        // the vault/index unavailable) became an unhandled promise rejection
        // - the dialog just silently kept showing blank/stale defaults with
        // no indication anything had gone wrong.
        toast.error('Failed to load AI settings', {
          description: err instanceof Error ? err.message : String(err)
        })
      })
  }, [open])

  const saveKey = async (provider: AiProviderId) => {
    try {
      await backend.setApiKey(provider, keys[provider])
      // The only feedback the Save button gave on success or failure alike
      // was... nothing - a failed keychain write looked identical to a
      // successful one until a later AI request confusingly failed with "No
      // API key configured". A brief success toast (mirroring the failure
      // toast below) is enough signal without adding persistent UI state to
      // this deliberately minimal dialog (spec §14b).
      toast.success(`Saved ${provider} API key`)
    } catch (err) {
      toast.error(`Failed to save ${provider} API key`, {
        description: err instanceof Error ? err.message : String(err)
      })
    }
  }

  const testConnection = async (provider: AiProviderId) => {
    setTestState((s) => ({ ...s, [provider]: 'testing' }))
    try {
      const models = getAiModels()
      // Scoped `getModels(provider)` only finds models registered under that
      // exact provider id - in dev/test mode the faux provider registers as
      // "faux", not "openai"/"anthropic", so it would never appear here. Fall
      // back to the first model in the full catalog when the provider-scoped
      // lookup comes up empty (dev/faux mode); in the real Tauri app the
      // scoped lookup always succeeds since openaiProvider()/anthropicProvider()
      // register under those literal ids. Mirrors the fix applied in Task 6's
      // client.ts for the same underlying pi-ai scoping behavior.
      const model = models.getModels(provider)[0] ?? models.getModels()[0]
      const apiKey = await backend.getApiKey(provider)
      if (!model || !apiKey) throw new Error('no model or key')
      await models.complete(
        model,
        {
          messages: [{ role: 'user', content: 'ping', timestamp: Date.now() }]
        },
        { apiKey }
      )
      setTestState((s) => ({ ...s, [provider]: 'ok' }))
    } catch {
      setTestState((s) => ({ ...s, [provider]: 'error' }))
    }
  }

  const allModels = getAiModels()
  const modelOptions = [defaultProvider || AI_PROVIDER_IDS[0]].flatMap((p) => {
    const scoped = allModels.getModels(p as AiProviderId)
    return scoped.length > 0 ? scoped : allModels.getModels()
  })

  const saveDefaults = async (provider: string, model: string) => {
    setDefaultProvider(provider)
    setDefaultModel(model)
    try {
      await backend.saveAiSettings({
        defaultAiProvider: provider || null,
        defaultAiModel: model || null
      })
    } catch (err) {
      // The two `<select>`s above already reflect the change optimistically
      // via the `setDefaultProvider`/`setDefaultModel` calls above, so a
      // failed persist here would otherwise look identical to a successful
      // one until the next reload silently reverted the selection.
      toast.error('Failed to save default AI provider/model', {
        description: err instanceof Error ? err.message : String(err)
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <Button variant="ghost" size="sm" data-testid="ai-settings-trigger" />
        }
      >
        AI Settings
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>AI Writing Tools</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          {AI_PROVIDER_IDS.map((provider) => (
            <div key={provider} className="flex items-center gap-2">
              <Input
                type="password"
                placeholder={`${provider} API key`}
                value={keys[provider]}
                onChange={(e) =>
                  setKeys((k) => ({ ...k, [provider]: e.target.value }))
                }
                data-testid={`ai-settings-key-${provider}`}
              />
              <Button
                size="sm"
                variant="outline"
                onClick={() => saveKey(provider)}
                data-testid={`ai-settings-save-${provider}`}
              >
                Save
              </Button>
              <Button
                size="sm"
                variant="secondary"
                onClick={() => testConnection(provider)}
                data-testid={`ai-settings-test-${provider}`}
              >
                {TEST_STATE_LABEL[testState[provider]]}
              </Button>
            </div>
          ))}
          <div className="border-border/60 flex items-center gap-2 border-t pt-3">
            <select
              value={defaultProvider}
              onChange={(e) => saveDefaults(e.target.value, '')}
              data-testid="ai-settings-default-provider"
              className={selectClassName}
            >
              <option value="">Choose a provider…</option>
              {AI_PROVIDER_IDS.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
            <select
              value={defaultModel}
              onChange={(e) => saveDefaults(defaultProvider, e.target.value)}
              data-testid="ai-settings-default-model"
              className={selectClassName}
            >
              <option value="">Choose a model…</option>
              {modelOptions.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name ?? m.id}
                </option>
              ))}
            </select>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
