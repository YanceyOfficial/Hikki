import type { Context, MiddlewareHandler } from 'hono'

import { errorBody, requestIdOf } from './http.js'

export type RateLimitOptions = {
  /** Requests one address may make per window. */
  limit: number
  windowMs: number
  /** The clock (tests). */
  now?: () => number
  /** Addresses kept at most; past it the oldest windows are dropped (memory stays bounded under a flood). */
  maxClients?: number
}

/**
 * The caller's address as Vercel reports it: `x-real-ip`, else the first `x-forwarded-for` hop (Vercel overwrites
 * both, a client can't choose them there). Elsewhere (local dev) everyone is one caller.
 */
export function clientAddress(c: Context): string {
  const real = c.req.header('x-real-ip')?.trim()
  if (real) return real
  const forwarded = c.req.header('x-forwarded-for')?.split(',')[0]?.trim()
  return forwarded || 'local'
}

/**
 * A fixed-window limit per address, so no one caller can spend the app's Unsplash quota (every search is an
 * upstream request under the operator's key). In memory, per function instance: Vercel runs several instances and
 * recycles them, so this caps a burst against one instance, not a distributed flood — that is the Vercel Firewall's
 * rate limiting, configured in the project (an owner step). Over the limit: 429, `Retry-After`, the `rateLimited`
 * code in the BFF's error shape.
 */
export function rateLimit({
  limit,
  windowMs,
  now = Date.now,
  maxClients = 10_000
}: RateLimitOptions): MiddlewareHandler {
  const windows = new Map<string, { start: number; count: number }>()
  return async (c, next) => {
    const at = now()
    const key = clientAddress(c)
    let window = windows.get(key)
    if (!window || at - window.start >= windowMs) {
      windows.delete(key)
      window = { start: at, count: 0 }
      windows.set(key, window)
      // Insertion order is age order: the first entries are the oldest windows.
      while (windows.size > maxClients) {
        const oldest = windows.keys().next().value
        if (oldest === undefined) break
        windows.delete(oldest)
      }
    }
    window.count += 1
    if (window.count > limit) {
      const retryAfter = Math.max(1, Math.ceil((window.start + windowMs - at) / 1000))
      c.header('Retry-After', String(retryAfter))
      c.set('failure' as never, 'rate limited' as never)
      return c.json(errorBody('rateLimited', requestIdOf(c)), 429)
    }
    await next()
  }
}
