import { countWords } from '#lib/word-count'

test('counts words across nested content and children', () => {
  const blocks = [
    {
      type: 'paragraph',
      content: [{ type: 'text', text: 'the quick brown fox' }],
      children: [
        {
          type: 'paragraph',
          content: [{ type: 'text', text: 'jumps over' }],
          children: []
        }
      ]
    }
  ]
  expect(countWords(blocks)).toBe(6)
})

test('returns 0 for an empty document', () => {
  expect(countWords([])).toBe(0)
})

test('walks table rows and cells', () => {
  const blocks = [
    {
      type: 'table',
      content: {
        rows: [
          {
            cells: [
              [{ type: 'text', text: 'a b' }],
              [{ type: 'text', text: 'c' }]
            ]
          }
        ]
      }
    }
  ]
  expect(countWords(blocks)).toBe(3)
})

test("collapses runs of whitespace the same way Rust's split_whitespace does", () => {
  const blocks = [
    {
      type: 'paragraph',
      content: [{ type: 'text', text: '  leading and   extra   spaces  ' }]
    }
  ]
  expect(countWords(blocks)).toBe(4)
})
