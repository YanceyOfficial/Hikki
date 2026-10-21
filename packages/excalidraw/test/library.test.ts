import { describe, expect, it, vi } from 'vitest'

import { libraryKeeper } from '../src/library'
import { LIBRARY_LIMIT, storedLibraryItems } from '../src/scene'

const rect = { id: 'r1', type: 'rectangle', x: 0, y: 0, width: 10, height: 10 }
const item = (id: string, elements: unknown[] = [rect]) => ({
  id,
  status: 'unpublished',
  created: 1,
  elements
})

describe('a Library', () => {
  it('keeps items as Excalidraw shapes them, their elements checked like a drawing', () => {
    const frame = { id: 'f1', type: 'embeddable', link: 'https://evil.example' }
    const linked = { ...rect, id: 'r2', link: 'javascript:alert(1)', customData: { x: 1 } }
    const items = storedLibraryItems([
      { ...item('a', [rect, frame]), name: 'Box', status: 'published', extra: 'dropped' },
      item('b', [linked]),
      item('only-frames', [frame]),
      item('__proto__'),
      { id: 'c', elements: [rect], created: Number.NaN },
      [rect],
      'nonsense'
    ])
    expect(items.map((i) => i.id)).toEqual(['a', 'b', 'c'])
    expect(items[0]).toEqual({
      id: 'a',
      status: 'published',
      created: 1,
      name: 'Box',
      elements: [rect]
    })
    expect(items[1].elements[0].link ?? null).toBeNull()
    expect(items[1].elements[0]).not.toHaveProperty('customData')
    expect(items[2]).toEqual({ id: 'c', status: 'unpublished', created: 0, elements: [rect] })
    expect(storedLibraryItems({ items: [] })).toEqual([])
  })

  it(`keeps at most ${LIBRARY_LIMIT} items`, () => {
    const many = Array.from({ length: LIBRARY_LIMIT + 5 }, (_, n) => item(`i${n}`))
    expect(storedLibraryItems(many)).toHaveLength(LIBRARY_LIMIT)
  })

  it('reads the stored items, and writes changes back checked — only when something changed', async () => {
    const save = vi.fn()
    const keeper = libraryKeeper({ load: async () => [item('a')], save })
    expect((await keeper.load()).map((i) => i.id)).toEqual(['a'])
    keeper.changed([item('a')])
    expect(save).not.toHaveBeenCalled()
    keeper.changed([item('a'), item('b'), item('frame', [{ id: 'f', type: 'iframe' }])])
    expect(save).toHaveBeenCalledTimes(1)
    expect(save.mock.calls[0][0].map((i: { id: string }) => i.id)).toEqual(['a', 'b'])
  })

  it("never writes over a Library it couldn't read, nor before reading it", async () => {
    const save = vi.fn()
    const keeper = libraryKeeper({ load: () => Promise.reject(new Error('unreadable')), save })
    keeper.changed([item('early')])
    expect(await keeper.load()).toEqual([])
    keeper.changed([item('a')])
    expect(save).not.toHaveBeenCalled()
  })
})
