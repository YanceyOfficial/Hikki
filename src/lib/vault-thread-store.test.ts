import {
  VaultThreadStore,
  type SerializedThread
} from '#lib/vault-thread-store'

test('createThread returns ThreadData with a generated id and the initial comment', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const thread = await store.createThread({
    initialComment: { body: [{ type: 'paragraph', content: 'hi' }] }
  })

  expect(thread.id).toBeTruthy()
  expect(thread.type).toBe('thread')
  expect(thread.resolved).toBe(false)
  expect(thread.comments).toHaveLength(1)
  expect(thread.comments[0].id).toBeTruthy()
  expect(thread.comments[0].body).toEqual([
    { type: 'paragraph', content: 'hi' }
  ])
  expect(thread.comments[0].createdAt).toBeInstanceOf(Date)
  expect(thread.createdAt).toBeInstanceOf(Date)
  expect(store.getThreads().get(thread.id)).toEqual(thread)
})

test('addComment appends a comment to an existing thread', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const thread = await store.createThread({ initialComment: { body: 'first' } })

  const comment = await store.addComment({
    threadId: thread.id,
    comment: { body: 'second' }
  })

  const updated = store.getThread(thread.id)
  expect(updated.comments).toHaveLength(2)
  expect(updated.comments[1].id).toBe(comment.id)
  expect(updated.comments[1].body).toBe('second')
  expect(updated.comments[0].body).toBe('first')
})

test('resolveThread / unresolveThread flips resolved', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const thread = await store.createThread({ initialComment: { body: 'x' } })

  await store.resolveThread({ threadId: thread.id })
  expect(store.getThread(thread.id).resolved).toBe(true)

  await store.unresolveThread({ threadId: thread.id })
  expect(store.getThread(thread.id).resolved).toBe(false)
})

test('deleteThread removes it from getThreads()', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const thread = await store.createThread({ initialComment: { body: 'x' } })
  expect(store.getThreads().has(thread.id)).toBe(true)

  await store.deleteThread({ threadId: thread.id })
  expect(store.getThreads().has(thread.id)).toBe(false)
})

test('deleteComment removes just that comment from the thread', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const thread = await store.createThread({ initialComment: { body: 'first' } })
  const comment = await store.addComment({
    threadId: thread.id,
    comment: { body: 'second' }
  })

  await store.deleteComment({ threadId: thread.id, commentId: comment.id })
  expect(store.getThread(thread.id).comments).toHaveLength(1)
  expect(store.getThread(thread.id).comments[0].body).toBe('first')
})

test('addReaction / deleteReaction toggle a reaction on a comment', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const thread = await store.createThread({ initialComment: { body: 'x' } })
  const commentId = thread.comments[0].id

  await store.addReaction({ threadId: thread.id, commentId, emoji: '👍' })
  let comment = store.getThread(thread.id).comments[0]
  expect(comment.reactions).toHaveLength(1)
  expect(comment.reactions[0].emoji).toBe('👍')
  expect(comment.reactions[0].userIds).toEqual(['local-user'])

  await store.deleteReaction({ threadId: thread.id, commentId, emoji: '👍' })
  comment = store.getThread(thread.id).comments[0]
  expect(comment.reactions).toHaveLength(0)
})

test('subscribe fires with the updated map after each mutation, and unsubscribe stops future notifications', async () => {
  const store = new VaultThreadStore([], vi.fn())
  const cb = vi.fn()
  const unsubscribe = store.subscribe(cb)

  const thread = await store.createThread({ initialComment: { body: 'x' } })
  expect(cb).toHaveBeenCalledTimes(1)
  expect(cb.mock.calls[0][0]).toBeInstanceOf(Map)
  expect(cb.mock.calls[0][0].has(thread.id)).toBe(true)

  unsubscribe()
  await store.addComment({ threadId: thread.id, comment: { body: 'y' } })
  expect(cb).toHaveBeenCalledTimes(1)
})

test('onChange fires with a JSON-serializable snapshot after every mutation', async () => {
  const onChange = vi.fn()
  const store = new VaultThreadStore([], onChange)

  await store.createThread({ initialComment: { body: 'hi' } })

  expect(onChange).toHaveBeenCalledTimes(1)
  const snapshot = onChange.mock.calls[0][0]
  expect(Array.isArray(snapshot)).toBe(true)
  expect(snapshot).toHaveLength(1)
  // No Date instances or Maps anywhere in the snapshot - safe to hand
  // directly to `update({ threads: ... })`, which persists it as JSON.
  const roundTripped = JSON.parse(JSON.stringify(snapshot))
  expect(roundTripped).toEqual(snapshot)
  expect(typeof snapshot[0].createdAt).toBe('string')
  expect(typeof snapshot[0].comments[0].createdAt).toBe('string')

  await store.addComment({
    threadId: snapshot[0].id,
    comment: { body: 'again' }
  })
  expect(onChange).toHaveBeenCalledTimes(2)
})

test('constructing from a previously-serialized snapshot rehydrates Date fields', async () => {
  // Simulate the full round trip document-page.tsx relies on: a first store
  // serializes its state via `onChange` (as if handing it to `update({
  // threads: ... })`), and a fresh store is constructed from that exact
  // output (as if re-hydrating `doc.threads` after a reload).
  const onChange = vi.fn()
  const store1 = new VaultThreadStore([], onChange)
  const original = await store1.createThread({ initialComment: { body: 'hi' } })
  await store1.addReaction({
    threadId: original.id,
    commentId: original.comments[0].id,
    emoji: '🎉'
  })
  const serialized = onChange.mock.calls[
    onChange.mock.calls.length - 1
  ][0] as SerializedThread[]

  const store2 = new VaultThreadStore(serialized, vi.fn())
  const threads = store2.getThreads()
  expect(threads.size).toBe(1)
  const [thread] = [...threads.values()]
  expect(thread.id).toBe(original.id)
  expect(thread.createdAt).toBeInstanceOf(Date)
  expect(thread.updatedAt).toBeInstanceOf(Date)
  expect(thread.createdAt.toISOString()).toBe(serialized[0].createdAt)
  expect(thread.comments[0].createdAt).toBeInstanceOf(Date)
  expect(thread.comments[0].createdAt.toISOString()).toBe(
    serialized[0].comments[0].createdAt
  )
  expect(thread.comments[0].body).toBe('hi')
  expect(thread.comments[0].reactions[0].createdAt).toBeInstanceOf(Date)
})
