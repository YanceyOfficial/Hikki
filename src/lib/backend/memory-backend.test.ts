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

test('save does not resurrect a deleted document', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'Note')
  await b.deleteDocument(doc.id)
  const saved = await b.saveDocument({ ...doc, title: 'stale edit' })
  expect(saved.deletedAt).not.toBeNull()
  expect((await b.loadDocument(doc.id)).deletedAt).not.toBeNull()
})

test('delete terminates on parent cycle', async () => {
  const b = new MemoryBackend()
  const a = await b.createDocument(null, 'A')
  const c = await b.createDocument(a.id, 'C')
  await b.saveDocument({ ...(await b.loadDocument(a.id)), parentId: c.id })
  const affected = await b.deleteDocument(a.id)
  expect(affected.sort()).toEqual([a.id, c.id].sort())
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

test('importAsset returns a url and assetUrl resolves it later', async () => {
  const b = new MemoryBackend()
  const doc = await b.createDocument(null, 'D')
  const file = new File([new Uint8Array([9])], 'pic.png')
  const imported = await b.importAsset(doc.id, file)
  expect(imported.fileName).toBe('pic.png')
  expect(imported.url).toBeTruthy()
  expect(b.assetUrl(doc.id, 'pic.png')).toBe(imported.url)
})

test('api key round-trips through set/get/delete', async () => {
  const b = new MemoryBackend()
  expect(await b.getApiKey('openai')).toBeNull()
  await b.setApiKey('openai', 'sk-test-123')
  expect(await b.getApiKey('openai')).toBe('sk-test-123')
  await b.deleteApiKey('openai')
  expect(await b.getApiKey('openai')).toBeNull()
})

test('ai settings persist in memory across calls', async () => {
  const b = new MemoryBackend()
  const initial = await b.getAiSettings()
  expect(initial).toEqual({ defaultAiProvider: null, defaultAiModel: null })

  const saved = await b.saveAiSettings({
    defaultAiProvider: 'anthropic',
    defaultAiModel: 'claude-test'
  })
  expect(saved).toEqual({
    defaultAiProvider: 'anthropic',
    defaultAiModel: 'claude-test'
  })
  expect(await b.getAiSettings()).toEqual(saved)
})
