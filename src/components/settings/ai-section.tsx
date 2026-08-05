import { useEffect, useState } from 'react'
import { toast } from 'sonner'

import { Button } from '#components/ui/button'
import { Field, FieldGroup } from '#components/ui/field'
import { Input } from '#components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue
} from '#components/ui/select'
import { AI_PROVIDER_IDS, getAiModels, type AiProviderId } from '#lib/ai/models'
import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'

type ConnectionTestState = 'idle' | 'testing' | 'ok' | 'error'

const TEST_STATE_LABEL: Record<ConnectionTestState, string> = {
  idle: 'Test connection',
  testing: 'Testing…',
  ok: 'Connected',
  error: 'Failed'
}

export function AiSection() {
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
    backend
      .getAiSettings()
      .then((settings) => {
        setDefaultProvider(settings.defaultAiProvider ?? '')
        setDefaultModel(settings.defaultAiModel ?? '')
      })
      .catch((err) => {
        // Without this `.catch`, a rejected `getAiSettings()` IPC call (e.g.
        // the vault/index unavailable) became an unhandled promise rejection
        // - the section just silently kept showing blank/stale defaults with
        // no indication anything had gone wrong.
        reportError('HK-3002', {
          message: err instanceof Error ? err.message : String(err)
        })
      })
  }, [])

  const saveKey = async (provider: AiProviderId) => {
    try {
      await backend.setApiKey(provider, keys[provider])
      // The only feedback the Save button gave on success or failure alike
      // was... nothing - a failed keychain write looked identical to a
      // successful one until a later AI request confusingly failed with "No
      // API key configured". A brief success toast (mirroring the failure
      // toast below) is enough signal without adding persistent UI state to
      // this deliberately minimal section (spec §14b).
      toast.success(`Saved ${provider} API key`)
    } catch (err) {
      reportError('HK-3003', {
        provider,
        message: err instanceof Error ? err.message : String(err)
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
      reportError('HK-3004', {
        message: err instanceof Error ? err.message : String(err)
      })
    }
  }

  return (
    <FieldGroup>
      {AI_PROVIDER_IDS.map((provider) => (
        <Field key={provider} orientation="horizontal">
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
        </Field>
      ))}
      <Field
        orientation="horizontal"
        className="border-border/60 border-t pt-3"
      >
        <Select
          items={AI_PROVIDER_IDS.map((p) => ({ label: p, value: p }))}
          value={defaultProvider || null}
          onValueChange={(value) => saveDefaults(value ?? '', '')}
        >
          <SelectTrigger data-testid="ai-settings-default-provider" size="sm">
            <SelectValue placeholder="Choose a provider…" />
          </SelectTrigger>
          <SelectContent>
            {AI_PROVIDER_IDS.map((p) => (
              <SelectItem key={p} value={p}>
                {p}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select
          items={modelOptions.map((m) => ({
            label: m.name ?? m.id,
            value: m.id
          }))}
          value={defaultModel || null}
          onValueChange={(value) => saveDefaults(defaultProvider, value ?? '')}
        >
          <SelectTrigger data-testid="ai-settings-default-model" size="sm">
            <SelectValue placeholder="Choose a model…" />
          </SelectTrigger>
          <SelectContent>
            {modelOptions.map((m) => (
              <SelectItem key={m.id} value={m.id}>
                {m.name ?? m.id}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
    </FieldGroup>
  )
}
