import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { extractTocItems, TableOfContents } from '#components/table-of-contents'

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

test('opening the floating toggle reveals heading text and excludes the paragraph', async () => {
  render(
    <TableOfContents
      blocks={[
        heading('h1', 1, 'Intro'),
        paragraph('p1', 'Just a paragraph'),
        heading('h2', 2, 'Details')
      ]}
    />
  )
  expect(screen.queryByTestId('table-of-contents')).not.toBeInTheDocument()
  await userEvent.click(screen.getByTestId('toc-toggle'))
  expect(await screen.findByTestId('table-of-contents')).toBeInTheDocument()
  expect(screen.getByText('Intro')).toBeInTheDocument()
  expect(screen.getByText('Details')).toBeInTheDocument()
  expect(screen.queryByText('Just a paragraph')).not.toBeInTheDocument()
})

test('renders nothing when there are no headings', () => {
  const { container } = render(
    <TableOfContents blocks={[paragraph('p1', 'Just a paragraph')]} />
  )
  expect(container).toBeEmptyDOMElement()
})

test('renders nothing for an empty blocks array', () => {
  const { container } = render(<TableOfContents blocks={[]} />)
  expect(container).toBeEmptyDOMElement()
})
