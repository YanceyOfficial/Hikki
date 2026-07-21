import {
  DefaultThreadStoreAuth,
  ThreadStore,
  type CommentBody,
  type CommentData,
  type CommentReactionData,
  type ThreadData
} from '@blocknote/core/comments'

// v1 scope: a single local user, no auth/roles - every comment is authored
// by (and every action permitted for) this one fixed identity. See the task
// brief's "Scope for v1" note.
const LOCAL_USER_ID = 'local-user'

/** JSON-safe mirror of `CommentReactionData` (`createdAt` as an ISO string). */
export interface SerializedReaction {
  emoji: string
  createdAt: string
  userIds: string[]
}

/** JSON-safe mirror of `CommentData` (`Date` fields as ISO strings). */
export interface SerializedComment {
  type: 'comment'
  id: string
  userId: string
  createdAt: string
  updatedAt: string
  deletedAt?: string
  reactions: SerializedReaction[]
  metadata: unknown
  body: CommentBody | undefined
}

/** JSON-safe mirror of `ThreadData` (`Date` fields as ISO strings). */
export interface SerializedThread {
  type: 'thread'
  id: string
  createdAt: string
  updatedAt: string
  resolved: boolean
  resolvedUpdatedAt?: string
  resolvedBy?: string
  metadata: unknown
  deletedAt?: string
  comments: SerializedComment[]
}

function serializeReaction(reaction: CommentReactionData): SerializedReaction {
  return {
    emoji: reaction.emoji,
    createdAt: reaction.createdAt.toISOString(),
    userIds: [...reaction.userIds]
  }
}

function deserializeReaction(
  reaction: SerializedReaction
): CommentReactionData {
  return {
    emoji: reaction.emoji,
    createdAt: new Date(reaction.createdAt),
    userIds: [...reaction.userIds]
  }
}

function serializeComment(comment: CommentData): SerializedComment {
  return {
    type: 'comment',
    id: comment.id,
    userId: comment.userId,
    createdAt: comment.createdAt.toISOString(),
    updatedAt: comment.updatedAt.toISOString(),
    deletedAt: comment.deletedAt?.toISOString(),
    reactions: comment.reactions.map(serializeReaction),
    metadata: comment.metadata,
    body: comment.body
  }
}

function deserializeComment(comment: SerializedComment): CommentData {
  return {
    type: 'comment',
    id: comment.id,
    userId: comment.userId,
    createdAt: new Date(comment.createdAt),
    updatedAt: new Date(comment.updatedAt),
    deletedAt: comment.deletedAt ? new Date(comment.deletedAt) : undefined,
    reactions: comment.reactions.map(deserializeReaction),
    metadata: comment.metadata,
    body: comment.body
  } as CommentData
}

function serializeThread(thread: ThreadData): SerializedThread {
  return {
    type: 'thread',
    id: thread.id,
    createdAt: thread.createdAt.toISOString(),
    updatedAt: thread.updatedAt.toISOString(),
    resolved: thread.resolved,
    resolvedUpdatedAt: thread.resolvedUpdatedAt?.toISOString(),
    resolvedBy: thread.resolvedBy,
    metadata: thread.metadata,
    deletedAt: thread.deletedAt?.toISOString(),
    comments: thread.comments.map(serializeComment)
  }
}

function deserializeThread(thread: SerializedThread): ThreadData {
  return {
    type: 'thread',
    id: thread.id,
    createdAt: new Date(thread.createdAt),
    updatedAt: new Date(thread.updatedAt),
    resolved: thread.resolved,
    resolvedUpdatedAt: thread.resolvedUpdatedAt
      ? new Date(thread.resolvedUpdatedAt)
      : undefined,
    resolvedBy: thread.resolvedBy,
    metadata: thread.metadata,
    deletedAt: thread.deletedAt ? new Date(thread.deletedAt) : undefined,
    comments: thread.comments.map(deserializeComment)
  } as ThreadData
}

function notFound(kind: 'thread' | 'comment', id: string): Error {
  return new Error(`${kind} not found: ${id}`)
}

/**
 * A `ThreadStore` (BlockNote's abstraction for comment-thread persistence,
 * see `@blocknote/core/comments`) backed by nothing more than a plain array
 * handed in at construction time and an `onChange` callback invoked after
 * every mutation - no server, no CRDT. The vault is the only persistence
 * layer: `document-page.tsx` owns one instance per document, seeds it from
 * `doc.threads`, and feeds `onChange`'s output straight back into the same
 * debounced autosave path `blocks`/`title` already use.
 *
 * Every `ThreadData`/`CommentData` handed out by `getThread`/`getThreads`
 * uses real `Date` instances, per the abstract class's contract - only the
 * `onChange` snapshot (and the `initial` constructor argument) use the
 * JSON-safe `SerializedThread` shape with ISO-string dates.
 */
export class VaultThreadStore extends ThreadStore {
  private threads = new Map<string, ThreadData>()
  private subscribers = new Set<(threads: Map<string, ThreadData>) => void>()

  constructor(
    initial: SerializedThread[],
    private readonly onChange: (serialized: SerializedThread[]) => void
  ) {
    super(new DefaultThreadStoreAuth(LOCAL_USER_ID, 'editor'))
    for (const thread of initial) {
      this.threads.set(thread.id, deserializeThread(thread))
    }
  }

  // Storing the thread's position (the mark in the document) is handled by
  // BlockNote's own default TipTap-mark-based behavior - see the doc
  // comment on this method in `ThreadStore` itself. No custom
  // implementation needed here.
  addThreadToDocument = undefined

  async createThread(options: {
    initialComment: { body: CommentBody; metadata?: unknown }
    metadata?: unknown
  }): Promise<ThreadData> {
    const now = new Date()
    const comment: CommentData = {
      type: 'comment',
      id: crypto.randomUUID(),
      userId: LOCAL_USER_ID,
      createdAt: now,
      updatedAt: now,
      reactions: [],
      metadata: options.initialComment.metadata,
      body: options.initialComment.body
    }
    const thread: ThreadData = {
      type: 'thread',
      id: crypto.randomUUID(),
      createdAt: now,
      updatedAt: now,
      comments: [comment],
      resolved: false,
      metadata: options.metadata
    }
    this.threads.set(thread.id, thread)
    this.notify()
    return thread
  }

  async addComment(options: {
    comment: { body: CommentBody; metadata?: unknown }
    threadId: string
  }): Promise<CommentData> {
    const thread = this.requireThread(options.threadId)
    const now = new Date()
    const comment: CommentData = {
      type: 'comment',
      id: crypto.randomUUID(),
      userId: LOCAL_USER_ID,
      createdAt: now,
      updatedAt: now,
      reactions: [],
      metadata: options.comment.metadata,
      body: options.comment.body
    }
    thread.comments = [...thread.comments, comment]
    thread.updatedAt = now
    this.notify()
    return comment
  }

  async updateComment(options: {
    comment: { body: CommentBody; metadata?: unknown }
    threadId: string
    commentId: string
  }): Promise<void> {
    const thread = this.requireThread(options.threadId)
    const now = new Date()
    let found = false
    thread.comments = thread.comments.map((comment) => {
      if (comment.id !== options.commentId) return comment
      found = true
      return {
        ...comment,
        body: options.comment.body,
        metadata: options.comment.metadata,
        updatedAt: now
      } as CommentData
    })
    if (!found) throw notFound('comment', options.commentId)
    thread.updatedAt = now
    this.notify()
  }

  async deleteComment(options: {
    threadId: string
    commentId: string
  }): Promise<void> {
    const thread = this.requireThread(options.threadId)
    thread.comments = thread.comments.filter(
      (comment) => comment.id !== options.commentId
    )
    thread.updatedAt = new Date()
    this.notify()
  }

  async deleteThread(options: { threadId: string }): Promise<void> {
    this.threads.delete(options.threadId)
    this.notify()
  }

  async resolveThread(options: { threadId: string }): Promise<void> {
    const thread = this.requireThread(options.threadId)
    const now = new Date()
    thread.resolved = true
    thread.resolvedUpdatedAt = now
    thread.resolvedBy = LOCAL_USER_ID
    thread.updatedAt = now
    this.notify()
  }

  async unresolveThread(options: { threadId: string }): Promise<void> {
    const thread = this.requireThread(options.threadId)
    const now = new Date()
    thread.resolved = false
    thread.resolvedUpdatedAt = now
    thread.resolvedBy = LOCAL_USER_ID
    thread.updatedAt = now
    this.notify()
  }

  async addReaction(options: {
    threadId: string
    commentId: string
    emoji: string
  }): Promise<void> {
    const thread = this.requireThread(options.threadId)
    const comment = thread.comments.find((c) => c.id === options.commentId)
    if (!comment) throw notFound('comment', options.commentId)
    const existing = comment.reactions.find((r) => r.emoji === options.emoji)
    if (existing) {
      if (!existing.userIds.includes(LOCAL_USER_ID)) {
        existing.userIds = [...existing.userIds, LOCAL_USER_ID]
      }
    } else {
      comment.reactions = [
        ...comment.reactions,
        {
          emoji: options.emoji,
          createdAt: new Date(),
          userIds: [LOCAL_USER_ID]
        }
      ]
    }
    this.notify()
  }

  async deleteReaction(options: {
    threadId: string
    commentId: string
    emoji: string
  }): Promise<void> {
    const thread = this.requireThread(options.threadId)
    const comment = thread.comments.find((c) => c.id === options.commentId)
    if (!comment) throw notFound('comment', options.commentId)
    comment.reactions = comment.reactions
      .map((reaction) =>
        reaction.emoji === options.emoji
          ? {
              ...reaction,
              userIds: reaction.userIds.filter((id) => id !== LOCAL_USER_ID)
            }
          : reaction
      )
      .filter((reaction) => reaction.userIds.length > 0)
    this.notify()
  }

  getThread(threadId: string): ThreadData {
    return this.requireThread(threadId)
  }

  getThreads(): Map<string, ThreadData> {
    return new Map(this.threads)
  }

  subscribe(cb: (threads: Map<string, ThreadData>) => void): () => void {
    this.subscribers.add(cb)
    return () => {
      this.subscribers.delete(cb)
    }
  }

  private requireThread(threadId: string): ThreadData {
    const thread = this.threads.get(threadId)
    if (!thread) throw notFound('thread', threadId)
    return thread
  }

  private notify(): void {
    const snapshot = this.getThreads()
    for (const cb of this.subscribers) cb(snapshot)
    this.onChange([...this.threads.values()].map(serializeThread))
  }
}
