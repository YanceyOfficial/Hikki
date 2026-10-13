import { act, cleanup, fireEvent, screen, waitFor } from '@testing-library/react'
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import {
  Ruby,
  rubyAt,
  rubySegmentsFrom,
  type RubyHost,
  type RubySegment
} from '../src/extensions/ruby'
import { stripIds } from './helpers'

let host: HTMLElement
let editor: Editor
let readings: RubyHost

/** What the native tokenizer would answer: a reading per kanji run, the kana left bare. */
const SUGGESTIONS: Record<string, RubySegment[]> = {
  漢字: [{ text: '漢字', reading: 'かんじ' }],
  この漢字を読む: [
    { text: 'この' },
    { text: '漢字', reading: 'かんじ' },
    { text: 'を' },
    { text: '読', reading: 'よ' },
    { text: 'む' }
  ]
}

const para = (text: string) => ({ type: 'paragraph', content: [{ type: 'text', text }] })

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  readings = { suggestReading: vi.fn(async (text: string) => SUGGESTIONS[text] ?? null) }
  editor = new Editor({
    element: host,
    content: { type: 'doc', content: [para('この漢字を読む')] },
    extensions: [StarterKit, Ruby(readings)]
  })
})
afterEach(() => {
  cleanup()
  editor.destroy()
  host.remove()
  document.querySelectorAll('.hk-ruby-panel').forEach((e) => e.remove())
})

describe('ruby (furigana)', () => {
  it('wraps the selected text with a reading, rendered as <ruby><rb>…</rb><rt>…</rt></ruby>', () => {
    editor.commands.setTextSelection({ from: 3, to: 5 }) // 漢字
    expect(editor.commands.setRuby('かんじ')).toBe(true)
    const json = editor.getJSON().content?.[0].content
    expect(json?.[1]).toMatchObject({
      type: 'ruby',
      attrs: { reading: 'かんじ' },
      content: [{ type: 'text', text: '漢字' }]
    })
    expect(editor.getHTML()).toContain('<rb>漢字</rb><rt>かんじ</rt></ruby>')
    expect(editor.getHTML()).toContain('data-reading="かんじ"')
    expect(editor.getText()).toBe('この漢字を読む')
  })

  it('refuses a selection across lines or with no text, and edits an existing reading in place', () => {
    editor.commands.setContent({ type: 'doc', content: [para('一'), para('二')] })
    editor.commands.setTextSelection({ from: 1, to: 5 })
    expect(editor.commands.setRuby('x')).toBe(false)
    editor.commands.setContent({ type: 'doc', content: [para('漢字')] })
    editor.commands.setTextSelection({ from: 1, to: 3 })
    editor.commands.setRuby('かんじ')
    editor.commands.setTextSelection(2) // inside the ruby's base text
    expect(rubyAt(editor.state.doc, 2)?.node.attrs.reading).toBe('かんじ')
    expect(editor.commands.setRuby('カンジ')).toBe(true)
    expect(editor.getJSON().content?.[0].content?.[0]).toMatchObject({
      attrs: { reading: 'カンジ' }
    })
    expect(editor.commands.unsetRuby()).toBe(true)
    expect(editor.getJSON().content?.[0].content).toEqual([{ type: 'text', text: '漢字' }])
  })

  it('parses pasted <ruby> markup, with and without <rb>', () => {
    editor.commands.setContent(
      '<p><ruby>東京<rp>(</rp><rt>とうきょう</rt><rp>)</rp></ruby>へ<ruby><rb>行</rb><rt>い</rt></ruby>く</p>'
    )
    const inline = editor.getJSON().content?.[0].content ?? []
    expect(inline[0]).toMatchObject({
      type: 'ruby',
      attrs: { reading: 'とうきょう' },
      content: [{ text: '東京' }]
    })
    expect(inline[2]).toMatchObject({
      type: 'ruby',
      attrs: { reading: 'い' },
      content: [{ text: '行' }]
    })
    expect(editor.getText()).toBe('東京へ行く')
  })

  it('the panel suggests a reading from the host and saves on Enter', async () => {
    editor.commands.setTextSelection({ from: 3, to: 5 })
    act(() => void editor.commands.editRuby())
    const input = (await screen.findByLabelText('Reading')) as HTMLInputElement
    await waitFor(() => expect(input.value).toBe('かんじ'))
    expect(readings.suggestReading).toHaveBeenCalledWith('漢字')
    fireEvent.change(input, { target: { value: 'かんじ' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(editor.getJSON().content?.[0].content?.[1]).toMatchObject({
      type: 'ruby',
      attrs: { reading: 'かんじ' }
    })
    expect(document.querySelector('.hk-ruby-panel')).toBeNull()
  })

  it('clicking a reading reopens the panel for that ruby; Remove takes the ruby off', async () => {
    editor.commands.setTextSelection({ from: 3, to: 5 })
    editor.commands.setRuby('かんじ')
    const rt = host.querySelector('rt') as HTMLElement
    act(() => void fireEvent.mouseDown(rt))
    const input = (await screen.findByLabelText('Reading')) as HTMLInputElement
    expect(input.value).toBe('かんじ')
    act(() => screen.getByRole('button', { name: 'Remove' }).click())
    expect(editor.getHTML()).not.toContain('<ruby')
    expect(editor.getText()).toBe('この漢字を読む')
  })

  it('a phrase is read kanji by kanji: one ruby per kanji run, the kana left bare', async () => {
    editor.commands.setTextSelection({ from: 1, to: 8 }) // この漢字を読む
    act(() => void editor.commands.editRuby())
    const kanji = (await screen.findByLabelText('Reading for 漢字')) as HTMLInputElement
    const yomu = screen.getByLabelText('Reading for 読') as HTMLInputElement
    expect([kanji.value, yomu.value]).toEqual(['かんじ', 'よ'])
    fireEvent.change(yomu, { target: { value: 'よみ' } })
    fireEvent.keyDown(yomu, { key: 'Enter' })
    expect(stripIds(editor.getJSON().content?.[0].content)).toEqual([
      { type: 'text', text: 'この' },
      { type: 'ruby', attrs: { reading: 'かんじ' }, content: [{ type: 'text', text: '漢字' }] },
      { type: 'text', text: 'を' },
      { type: 'ruby', attrs: { reading: 'よみ' }, content: [{ type: 'text', text: '読' }] },
      { type: 'text', text: 'む' }
    ])
    expect(editor.getText()).toBe('この漢字を読む')
    expect(document.querySelector('.hk-ruby-panel')).toBeNull()
  })

  it('"Whole" puts one reading over the phrase instead', async () => {
    editor.commands.setTextSelection({ from: 1, to: 8 })
    act(() => void editor.commands.editRuby())
    await screen.findByLabelText('Reading for 漢字')
    act(() => screen.getByRole('tab', { name: 'Whole' }).click())
    const input = screen.getByLabelText('Reading') as HTMLInputElement
    expect(input.value).toBe('このかんじをよむ')
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(editor.getJSON().content?.[0].content).toHaveLength(1)
    expect(editor.getJSON().content?.[0].content?.[0]).toMatchObject({
      type: 'ruby',
      attrs: { reading: 'このかんじをよむ' },
      content: [{ type: 'text', text: 'この漢字を読む' }]
    })
  })

  it('reads the native reply: null readings mean none, anything else is no suggestion', () => {
    expect(
      rubySegmentsFrom([
        { text: '役', reading: 'やく' },
        { text: 'に', reading: null },
        { text: '立', reading: 'た' },
        { text: 'ちます' }
      ])
    ).toEqual([
      { text: '役', reading: 'やく' },
      { text: 'に' },
      { text: '立', reading: 'た' },
      { text: 'ちます' }
    ])
    expect(rubySegmentsFrom('かんじ')).toBeNull()
    expect(rubySegmentsFrom([])).toBeNull()
    expect(rubySegmentsFrom([{ text: '', reading: 'x' }])).toBeNull()
    expect(rubySegmentsFrom([{ text: '役', reading: 1 }])).toBeNull()
  })

  it('setRubySegments refuses segments that do not spell the selection', () => {
    editor.commands.setTextSelection({ from: 3, to: 5 })
    expect(editor.commands.setRubySegments([{ text: '漢', reading: 'かん' }])).toBe(false)
    expect(editor.commands.setRubySegments([{ text: '漢字' }])).toBe(false)
    expect(editor.getHTML()).not.toContain('<ruby')
  })
})
