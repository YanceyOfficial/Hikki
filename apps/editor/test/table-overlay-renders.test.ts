import type { Editor } from '@tiptap/core'
import { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createEditor } from '../src/core/editor'
import { doc } from './helpers'

/** Counts the table overlay's renders (and still draws it). */
const renders = vi.hoisted(() => ({ count: 0 }))
vi.mock('../src/components/table-overlay', async (original) => {
  const actual = await original<typeof import('../src/components/table-overlay')>()
  return {
    ...actual,
    renderTableOverlay: (...args: Parameters<typeof actual.renderTableOverlay>) => {
      renders.count++
      actual.renderTableOverlay(...args)
    }
  }
})

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  editor = createEditor(host, doc('no tables here'))
})
afterEach(() => {
  editor.destroy()
  host.remove()
})

describe('table overlay', () => {
  it('draws nothing again while nothing table-related shows: typing and scrolling stay cheap', async () => {
    const before = renders.count
    for (const ch of 'typing') act(() => void editor.commands.insertContent(ch))
    for (let i = 0; i < 20; i++) window.dispatchEvent(new Event('scroll'))
    await new Promise((resolve) => requestAnimationFrame(() => resolve(null)))
    expect(renders.count).toBe(before)
  })

  it('scrolling over a table redraws once per frame, not once per event', async () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        {
          type: 'table',
          content: [
            {
              type: 'tableRow',
              content: [
                {
                  type: 'tableCell',
                  content: [{ type: 'paragraph', content: [{ type: 'text', text: 'a' }] }]
                }
              ]
            }
          ]
        }
      ]
    })
    const cell = host.querySelector('td') as HTMLElement
    act(() => void cell.dispatchEvent(new MouseEvent('mousemove', { bubbles: true })))
    await act(async () => {
      await new Promise((resolve) => requestAnimationFrame(() => resolve(null)))
    })
    const before = renders.count
    for (let i = 0; i < 20; i++) window.dispatchEvent(new Event('scroll'))
    await act(async () => {
      await new Promise((resolve) => requestAnimationFrame(() => resolve(null)))
    })
    expect(renders.count - before).toBe(1)
  })
})
