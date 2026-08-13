import { clearMocks, mockIPC } from '@tauri-apps/api/mocks'

import { TauriBackend } from '#lib/backend/tauri-backend'
import type { Doc } from '#lib/types'

const fixture: Doc = {
  schemaVersion: 1,
  id: 'doc-1',
  parentId: null,
  title: 'Hello',
  icon: null,
  cover: null,
  blocks: [],
  threads: {},
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null
}

afterEach(() => clearMocks())

test('createDocument invokes create_document with camelCase args', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return fixture
  })
  const doc = await new TauriBackend().createDocument(null, 'Hello')
  expect(calls).toEqual([
    ['create_document', { parentId: null, title: 'Hello' }]
  ])
  expect(doc.title).toBe('Hello')
})

test('search and delete map their commands', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    if (cmd === 'search') return []
    if (cmd === 'delete_document') return ['doc-1']
    return null
  })
  const b = new TauriBackend()
  await b.search('fox')
  await b.deleteDocument('doc-1')
  expect(calls).toEqual([
    ['search', { query: 'fox' }],
    ['delete_document', { id: 'doc-1' }]
  ])
})

test('rust error payloads reject with code intact', async () => {
  mockIPC(() =>
    Promise.reject({ code: 'HK-1003', message: 'document not found: x' })
  )
  await expect(new TauriBackend().loadDocument('x')).rejects.toMatchObject({
    code: 'HK-1003'
  })
})

test('importAsset sends bytes and maps the stored name to a URL', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return 'stored-uuid.png'
  })
  const file = new File([new Uint8Array([1, 2, 3])], 'photo.png')
  const result = await new TauriBackend().importAsset('doc-1', file)
  expect(calls).toEqual([
    [
      'import_asset',
      { docId: 'doc-1', fileName: 'photo.png', bytes: [1, 2, 3] }
    ]
  ])
  expect(result).toEqual({
    fileName: 'stored-uuid.png',
    url: 'hikki-asset://localhost/doc-1/stored-uuid.png'
  })
})

test('getDashboardStats invokes dashboard_stats with the local UTC offset', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return {
      totalDocuments: 0,
      totalWords: 0,
      streakDays: 0,
      docsEditedThisWeek: 0,
      dailyWords: [],
      dailyActivity: []
    }
  })
  await new TauriBackend().getDashboardStats()
  expect(calls).toEqual([
    ['dashboard_stats', { utcOffsetMinutes: new Date().getTimezoneOffset() }]
  ])
})

test('getRecentDocuments invokes recent_documents with the limit', async () => {
  const calls: Array<[string, unknown]> = []
  mockIPC((cmd, args) => {
    calls.push([cmd, args])
    return []
  })
  await new TauriBackend().getRecentDocuments(8)
  expect(calls).toEqual([['recent_documents', { limit: 8 }]])
})
