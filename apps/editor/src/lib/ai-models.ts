import type { AIModelMenu } from '../core/protocol'

/** The models the AI panel offers for one request (`window.hikki.setAIModels`); none in a plain browser. */
let menu: AIModelMenu | null = null

export function setAIModels(next: AIModelMenu | null): void {
  menu = next
}

/** The menu, when there is something to choose (a provider has a key). */
export const aiModels = (): AIModelMenu | null => (menu?.auto ? menu : null)

/** A choice's name: a model's, or null for Auto (the panel words it). */
export function modelName(choice: string): string | null {
  for (const group of menu?.groups ?? []) {
    const model = group.models.find((m) => m.id === choice)
    if (model) return model.name
  }
  return null
}
