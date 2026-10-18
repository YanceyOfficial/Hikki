import type { Context, ErrorHandler, MiddlewareHandler } from 'hono'

import { ERRORS, type ErrorId } from './generated/errors.js'

/** What every failure looks like on the wire: the code from design/errors.json and the request's id. */
export type ErrorBody = {
  error: { code: number; id: ErrorId; message: string }
  requestId: string | null
}

export function errorBody(id: ErrorId, requestId: string | null): ErrorBody {
  const { code, message } = ERRORS[id]
  return { error: { code, id, message }, requestId }
}

/** Answers with the code's status and body. */
export function fail(c: Context, id: ErrorId): Response {
  const status = ERRORS[id].status as 400 | 404 | 429 | 500 | 502 | 503
  return c.json(errorBody(id, requestIdOf(c)), status)
}

const REQUEST_ID = /^[\w-]{8,64}$/u

export const requestIdOf = (c: Context): string | null =>
  (c.get('requestId' as never) as string | undefined) ?? null

/**
 * Every request gets an id (the caller's `X-Request-Id` when it sent a sane one), echoed in the response header and
 * in error bodies, and one structured log line when it's done — method, path without the query (a search is the
 * user's words), status, duration. Vercel collects the lines; a user's report quotes the id.
 */
export function requestLog(log: (line: string) => void = console.log): MiddlewareHandler {
  return async (c, next) => {
    const sent = c.req.header('X-Request-Id')
    const id = sent && REQUEST_ID.test(sent) ? sent : crypto.randomUUID()
    c.set('requestId' as never, id as never)
    const started = Date.now()
    await next()
    const failed = c.get('failure' as never) as string | undefined
    c.res.headers.set('X-Request-Id', id)
    const status = c.res.status
    log(
      JSON.stringify({
        level: status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info',
        requestId: id,
        method: c.req.method,
        path: new URL(c.req.url).pathname,
        status,
        ms: Date.now() - started,
        ...(failed ? { error: failed } : {})
      })
    )
  }
}

/** A handler that threw: the `unknown` code with the request's id; the message goes to the log line only. */
export const onError: ErrorHandler = (error, c) => {
  c.set('failure' as never, (error instanceof Error ? error.message : String(error)) as never)
  return c.json(errorBody('unknown', requestIdOf(c)), 500)
}
