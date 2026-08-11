import { extractTocItems } from '#lib/toc'

const heading = (id: string, level: number, text: string) => ({
  id,
  type: 'heading',
  props: { level },
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

const paragraph = (id: string, text: string) => ({
  id,
  type: 'paragraph',
  props: {},
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

test('extracts heading text/depth and excludes non-heading blocks', () => {
  const items = extractTocItems([
    heading('h1', 1, 'Intro'),
    paragraph('p1', 'Just a paragraph'),
    heading('h2', 2, 'Details')
  ])
  expect(items).toEqual([
    { id: 'h1', text: 'Intro', depth: 1 },
    { id: 'h2', text: 'Details', depth: 2 }
  ])
})

test('walks nested children for headings inside container blocks', () => {
  const items = extractTocItems([
    {
      id: 'toggle1',
      type: 'toggleListItem',
      props: {},
      content: [{ type: 'text', text: 'Toggle', styles: {} }],
      children: [heading('nested-h', 3, 'Nested heading')]
    }
  ])
  expect(items).toEqual([{ id: 'nested-h', text: 'Nested heading', depth: 3 }])
})
