import { MemoryBackend } from '#lib/backend/memory-backend'

test('create, list, load round trip', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'Hello')
  expect(doc.id).toBeTruthy()
  expect(await b.listDocuments()).toHaveLength(1)
  expect((await b.loadDocument(doc.id)).title).toBe('Hello')
})

test('load missing rejects with HK-1003 code', async () => {
  const b = new MemoryBackend()
  await expect(b.loadDocument('nope')).rejects.toMatchObject({
    code: 'HK-1003'
  })
})

test('save bumps updatedAt and persists changes', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'v1')
  const saved = await b.saveDocument({ ...doc, title: 'v2' })
  expect(saved.title).toBe('v2')
  expect(saved.updatedAt >= doc.updatedAt).toBe(true)
  expect((await b.loadDocument(doc.id)).title).toBe('v2')
})

test('delete is soft and recursive', async () => {
  const b = new MemoryBackend()
  const parent = await b.createDocument(null, 'P')
  const child = await b.createDocument(parent.id, 'C')
  const affected = await b.deleteDocument(parent.id)
  expect(affected.sort()).toEqual([parent.id, child.id].sort())
  const metas = await b.listDocuments()
  expect(metas.every((m) => m.deletedAt !== null)).toBe(true)
})

test('search matches title and body case-insensitively, skipping deleted', async () => {
  const b = new MemoryBackend()
  await b.createDocument(null, 'Groceries')
  const trashed = await b.createDocument(null, 'Trashed')
  await b.deleteDocument(trashed.id)
  expect(await b.search('gro')).toHaveLength(1)
  expect(await b.search('trashed')).toHaveLength(0)
  expect(await b.search('  ')).toHaveLength(0)
})
