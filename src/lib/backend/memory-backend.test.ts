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

test('setVaultPath returns updated vault info, and later getVaultInfo calls reflect it too', async () => {
  const backend = new MemoryBackend()
  const info = await backend.setVaultPath('/tmp/some-vault')
  expect(info.vaultPath).toBe('/tmp/some-vault')
  expect((await backend.getVaultInfo()).vaultPath).toBe('/tmp/some-vault')
})

test('appendLog/readLogs/clearLogs round-trip in memory', async () => {
  const backend = new MemoryBackend()
  await backend.appendLog({
    level: 'error',
    scope: 'test',
    message: 'boom',
    timestamp: new Date().toISOString()
  })
  const logs = await backend.readLogs({})
  expect(logs).toHaveLength(1)
  expect(logs[0].message).toBe('boom')

  const filtered = await backend.readLogs({ level: 'info' })
  expect(filtered).toHaveLength(0)

  await backend.clearLogs()
  expect(await backend.readLogs({})).toHaveLength(0)
})

describe('dashboard stats', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  test('totals reflect alive documents only', async () => {
    const b = new MemoryBackend()
    const alive = await b.createDocument(null, 'Alive')
    await b.saveDocument({
      ...alive,
      blocks: [
        {
          type: 'paragraph',
          content: [{ type: 'text', text: 'one two three' }]
        }
      ]
    })
    const trashed = await b.createDocument(null, 'Trashed')
    await b.deleteDocument(trashed.id)

    const stats = await b.getDashboardStats()
    expect(stats.totalDocuments).toBe(1)
    expect(stats.totalWords).toBe(3)
  })

  test('streak counts backward from yesterday when today has no activity yet', async () => {
    const b = new MemoryBackend()
    vi.setSystemTime(new Date('2026-01-10T12:00:00Z'))
    const doc = await b.createDocument(null, 'D')
    vi.setSystemTime(new Date('2026-01-11T12:00:00Z'))
    await b.saveDocument({
      ...doc,
      blocks: [{ type: 'paragraph', content: [{ type: 'text', text: 'x' }] }]
    })
    vi.setSystemTime(new Date('2026-01-12T09:00:00Z')) // "today" - no activity yet

    const stats = await b.getDashboardStats()
    expect(stats.streakDays).toBe(2)
  })

  test('streak breaks on a full gap day', async () => {
    const b = new MemoryBackend()
    vi.setSystemTime(new Date('2026-01-01T12:00:00Z'))
    await b.createDocument(null, 'D')
    vi.setSystemTime(new Date('2026-01-04T12:00:00Z')) // 3 days later, a full gap

    const stats = await b.getDashboardStats()
    expect(stats.streakDays).toBe(0)
  })

  test('docsEditedThisWeek counts distinct documents, not distinct saves', async () => {
    const b = new MemoryBackend()
    const doc = await b.createDocument(null, 'D')
    await b.saveDocument({
      ...doc,
      blocks: [{ type: 'paragraph', content: [{ type: 'text', text: 'a' }] }]
    })
    await b.saveDocument({
      ...doc,
      blocks: [{ type: 'paragraph', content: [{ type: 'text', text: 'a b' }] }]
    })

    const stats = await b.getDashboardStats()
    expect(stats.docsEditedThisWeek).toBe(1)
  })

  test('dailyWords has exactly 30 entries and dailyActivity has exactly 35', async () => {
    const b = new MemoryBackend()
    const stats = await b.getDashboardStats()
    expect(stats.dailyWords).toHaveLength(30)
    expect(stats.dailyActivity).toHaveLength(35)
  })
})

describe('getRecentDocuments', () => {
  test('orders by updatedAt desc, excludes deleted, respects the limit', async () => {
    const b = new MemoryBackend()
    const a = await b.createDocument(null, 'A')
    const bDoc = await b.createDocument(null, 'B')
    const c = await b.createDocument(null, 'C')
    await b.saveDocument({ ...a, title: 'A' }) // bumps A's updatedAt to be latest
    await b.deleteDocument(c.id)

    const recent = await b.getRecentDocuments(1)
    expect(recent).toHaveLength(1)
    expect(recent[0].id).toBe(a.id)
    void bDoc
  })
})
