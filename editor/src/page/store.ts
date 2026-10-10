/** Minimal external store for React's useSyncExternalStore. */
export class Store<T> {
  private listeners = new Set<() => void>()
  constructor(private state: T) {}

  get = (): T => this.state

  set = (patch: Partial<T>): void => {
    this.state = { ...this.state, ...patch }
    this.listeners.forEach((l) => l())
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }
}
