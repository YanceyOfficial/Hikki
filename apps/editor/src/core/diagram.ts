import { mermaidFromAnswer } from '@hikki/excalidraw'

import { aiErrorText } from '../components/ai-review'
import type { ErrorId } from '../generated/errors'
import type { AIStreamEvent, ToNativeMessage } from './protocol'

/** A diagram that didn't come, with its message and the code it is reported under. */
export class DiagramError extends Error {
  constructor(
    message: string,
    readonly id: ErrorId
  ) {
    super(message)
  }
}

/** The error code of an AI failure the native side named (`AIError`'s names). */
const ERROR_IDS: Record<string, ErrorId> = {
  missingKey: 'aiMissingKey',
  badBaseURL: 'aiBadBaseURL',
  unauthorized: 'aiUnauthorized',
  rateLimited: 'aiRateLimited',
  unavailable: 'aiUnavailable',
  offline: 'aiOffline',
  rejected: 'aiRejected',
  refused: 'aiPictureRefused'
}

type Pending = { reply: string; resolve: (mermaid: string) => void; reject: (error: Error) => void }

/**
 * A drawing's Text to diagram: the user's words go to the native AI as an `aiRequest` with the action `diagram`
 * (AIPrompts' diagram instructions: Mermaid only), and the streamed answer comes back as Mermaid for Excalidraw to
 * turn into shapes. Failures reject with the same message the page's AI panel shows.
 */
export class DiagramRequests {
  private readonly pending = new Map<string, Pending>()
  private seq = 0

  constructor(private readonly send: (message: ToNativeMessage) => void) {}

  request(prompt: string, title: string): Promise<string> {
    const id = `diagram-${Date.now().toString(36)}-${++this.seq}`
    return new Promise((resolve, reject) => {
      this.pending.set(id, { reply: '', resolve, reject })
      this.send({
        type: 'aiRequest',
        id,
        action: 'diagram',
        instruction: prompt,
        answer: true,
        units: [],
        context: { title, before: '', after: '' }
      })
    })
  }

  /** Takes an AI event if it belongs to a diagram request (true), else leaves it to the page's AI. */
  handle(event: AIStreamEvent): boolean {
    const request = this.pending.get(event.id)
    if (!request) return false
    switch (event.type) {
      case 'text':
        request.reply += event.delta
        break
      case 'done': {
        this.pending.delete(event.id)
        const mermaid = mermaidFromAnswer(request.reply)
        if (mermaid) request.resolve(mermaid)
        else
          request.reject(
            new DiagramError(aiErrorText({ code: 'invalidResponse' }), 'aiInvalidResponse')
          )
        break
      }
      case 'error':
        this.pending.delete(event.id)
        request.reject(
          new DiagramError(aiErrorText(event), ERROR_IDS[event.code] ?? 'aiInvalidResponse')
        )
        break
      default:
        break
    }
    return true
  }
}
