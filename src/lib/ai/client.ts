import { getAiModels, type AiProviderId } from '#lib/ai/models'
import { buildContext, type WritingToolAction } from '#lib/ai/prompts'
import { backend } from '#lib/backend/index'

export type WritingToolStreamEvent =
  | { type: 'delta'; text: string }
  | { type: 'done' }
  | { type: 'error'; message: string }

export async function* streamWritingTool(
  action: WritingToolAction,
  selectedText: string,
  options: { provider: AiProviderId; modelId: string }
): AsyncGenerator<WritingToolStreamEvent> {
  const models = getAiModels()

  // `Models.getModel(provider, id)` only searches inside that provider's own
  // registered bucket. That's fine in the real Tauri app, where `getAiModels()`
  // registers providers under the literal ids "openai"/"anthropic" - but in
  // dev/test mode the entire catalog is served by a single provider
  // registered as "faux" (see models.ts), so a provider-scoped lookup keyed
  // on the caller's nominal `options.provider` ('openai'/'anthropic') would
  // never find it there. `Models.stream()` resolves the actual provider to
  // dispatch to from the model's own `.provider` field internally, not from
  // `options.provider`, so searching the full combined catalog by id alone
  // is correct in both modes; `options.provider` is only needed below to
  // fetch the right API key.
  const model = models
    .getModels()
    .find((candidate) => candidate.id === options.modelId)

  if (!model) {
    yield {
      type: 'error',
      message: `Model not found: ${options.provider}/${options.modelId}`
    }
    return
  }

  let apiKey: string | null
  try {
    apiKey = await backend.getApiKey(options.provider)
  } catch (err) {
    yield {
      type: 'error',
      message: err instanceof Error ? err.message : String(err)
    }
    return
  }
  if (!apiKey) {
    yield {
      type: 'error',
      message: `No API key configured for ${options.provider}`
    }
    return
  }

  const context = buildContext(action, selectedText)

  try {
    const stream = models.stream(model, context, { apiKey })
    for await (const event of stream) {
      if (event.type === 'text_delta') {
        yield { type: 'delta', text: event.delta }
      } else if (event.type === 'error') {
        yield {
          type: 'error',
          message: event.error.errorMessage ?? 'Unknown error'
        }
        return
      } else if (event.type === 'done') {
        yield { type: 'done' }
        return
      }
    }
  } catch (err) {
    yield {
      type: 'error',
      message: err instanceof Error ? err.message : String(err)
    }
  }
}
