import type { BridgeContext } from './bridge-types'
import { reportError } from './errors'
import type { Snapshot } from './protocol'

export type SaverOptions = {
  debounceMs: number
  /** Continuous typing still saves at least this often (the debounce alone would wait for a pause). */
  maxWaitMs?: number
}

/** Posts of one save before its failure is reported (the first try included). */
const SAVE_ATTEMPTS = 3

/** The pause before retry `attempt` + 1: 0.5 s, then 1 s… */
function retryPause(attempt: number): number {
  return 500 * 2 ** attempt
}

/**
 * Saving the open page: edits are handed to the app after a pause in typing (and at least every `maxWaitMs`), on a
 * page switch and a lock, or taken by the app through `flush()`. An edit counts as saved once the app has taken it;
 * a post that fails makes it pending again (see `postSnapshot`). Viewing a page never saves it.
 */
export class PageSaver {
  private timer: ReturnType<typeof setTimeout> | null = null
  /** When the oldest unsaved edit was made (for maxWaitMs); null when nothing is pending. */
  private pendingSince: number | null = null
  /**
   * User edits of the open page, counted; `handedOver` is the last one a snapshot carried to the app and
   * `accepted` the last one the app took (its reply came back, or it took `flush()`'s return). A post that fails
   * puts `handedOver` back to `accepted`, so the edit is pending again — never lost.
   */
  private edits = 0
  private handedOver = 0
  private accepted = 0
  /** Which page load the counters above belong to (a reply arriving after a page switch is about the old one). */
  private session = 0
  /** Failed posts of the open page in a row (bounded retries before the failure is reported). */
  private saveFailures = 0
  /** Snapshots of pages no longer open whose every attempt failed: sent again with the next save that gets through. */
  private readonly undelivered = new Map<string, Snapshot>()

  constructor(
    private readonly context: BridgeContext,
    private readonly options: SaverOptions,
    /** The open page as it would be saved now (null without a page). */
    private readonly snapshot: () => Snapshot | null
  ) {}

  /** True while the open page has an edit no snapshot has carried to the app. */
  get dirty(): boolean {
    return this.edits !== this.handedOver
  }

  /** Another page loaded: the counters start over for it. */
  startSession(): void {
    this.session += 1
    this.markSaved()
    this.saveFailures = 0
  }

  /** Words of page `docId` that never reached the app (newer than what it has), taken out of the retry list. */
  takeUndelivered(docId: string): Snapshot | undefined {
    const snapshot = this.undelivered.get(docId)
    this.undelivered.delete(docId)
    return snapshot
  }

  /** A user edit: saved after the debounce (or the max wait). */
  scheduleChanged(): void {
    if (this.context.frozen()) return
    // Once per save: the native indicator shows "Saving…" until the snapshot arrives.
    const docId = this.context.page.get().docId
    if (!this.dirty && docId) void this.context.send({ type: 'editing', docId })
    this.edits += 1
    this.saveFailures = 0
    const now = Date.now()
    this.pendingSince ??= now
    this.clearTimer()
    const { debounceMs, maxWaitMs = Infinity } = this.options
    const wait = Math.max(0, Math.min(debounceMs, this.pendingSince + maxWaitMs - now))
    this.timer = setTimeout(() => this.flushPending(), wait)
  }

  /**
   * Hands the pending edit to the app: when a save is scheduled (a debounce, a retry), or — `always` — whenever
   * there is an edit the app hasn't taken (a page switch, a lock).
   */
  flushPending(always = false): void {
    if (!this.timer && !(always && this.dirty)) return
    this.clearTimer()
    const snapshot = this.snapshot()
    const edit = this.edits
    this.markSaved()
    if (snapshot) this.postSnapshot(snapshot, edit)
  }

  /**
   * Returns the pending (unsaved) snapshot and cancels the debounce, or null when nothing changed —
   * the native side calls this on page switch / backgrounding and saves whatever it gets.
   */
  flush(): Snapshot | null {
    this.clearTimer()
    if (!this.dirty) return null
    const snapshot = this.snapshot()
    // The app saves what this returns: taken, not just handed over.
    this.markSaved()
    this.accepted = this.edits
    return snapshot
  }

  /**
   * Posts a save and follows it: the app's reply makes the edit taken; a failure (the message never reached the
   * app) makes it pending again and retries, `SAVE_ATTEMPTS` times in all with a growing pause, then reports
   * `editsNotDelivered`. The open page's edit stays pending after that (the next edit, flush or page switch hands
   * it over again); a page no longer open keeps its snapshot for the next save that gets through.
   */
  private postSnapshot(
    snapshot: Snapshot,
    edit: number,
    attempt = 0,
    session = this.session
  ): void {
    const isOpen = () => session === this.session
    this.context.transport.post({ type: 'changed', snapshot }).then(
      () => {
        if (isOpen()) {
          this.accepted = Math.max(this.accepted, edit)
          this.saveFailures = 0
        }
        this.undelivered.delete(snapshot.docId)
        this.sendUndelivered()
      },
      (error: unknown) => {
        // Can't route through the transport that just failed; ids only.
        console.error('[hikki] save not delivered', snapshot.docId, error)
        if (isOpen()) {
          // A later save, or a flush, got there meanwhile.
          if (this.accepted >= edit) return
          this.handedOver = this.accepted
          this.saveFailures += 1
          if (this.saveFailures < SAVE_ATTEMPTS) {
            // A retry is a scheduled save: it sends the page as it is then (this edit and any after it).
            if (!this.timer)
              this.timer = setTimeout(() => this.flushPending(), retryPause(this.saveFailures - 1))
          } else {
            reportError('editsNotDelivered', error, { docId: snapshot.docId })
          }
          return
        }
        if (attempt + 1 < SAVE_ATTEMPTS) {
          setTimeout(
            () => this.postSnapshot(snapshot, edit, attempt + 1, session),
            retryPause(attempt)
          )
        } else {
          this.undelivered.set(snapshot.docId, snapshot)
          reportError('editsNotDelivered', error, { docId: snapshot.docId })
        }
      }
    )
  }

  /** Snapshots of closed pages that never got through, sent again now that a save did. */
  private sendUndelivered(): void {
    const open = this.context.page.get().docId
    for (const [docId, snapshot] of this.undelivered) {
      if (docId === open) continue
      this.undelivered.delete(docId)
      this.postSnapshot(snapshot, 0, SAVE_ATTEMPTS - 1, -1)
    }
  }

  private clearTimer(): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  /** Called whenever the pending edit is handed over (debounce fired, flush, page switch). */
  private markSaved(): void {
    this.handedOver = this.edits
    this.pendingSince = null
  }
}
