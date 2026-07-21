import { extractCodeBlockText } from '#components/code-block-copy-overlay'

test('preserves line breaks rendered as <br> elements', () => {
  const code = document.createElement('code')
  code.innerHTML =
    'const greeting = "hello world";<br class="shiki">console.log(greeting);'
  expect(extractCodeBlockText(code)).toBe(
    'const greeting = "hello world";\nconsole.log(greeting);'
  )
})

test('handles single-line content with no <br>', () => {
  const code = document.createElement('code')
  code.innerHTML = 'const x = 1;'
  expect(extractCodeBlockText(code)).toBe('const x = 1;')
})

test('preserves multiple consecutive line breaks (blank lines)', () => {
  const code = document.createElement('code')
  code.innerHTML = 'line one<br class="shiki"><br class="shiki">line three'
  expect(extractCodeBlockText(code)).toBe('line one\n\nline three')
})

test('extracts text nested inside shiki token spans', () => {
  const code = document.createElement('code')
  code.innerHTML =
    '<span style="color:#000">const</span> x <span>=</span> 1;<br class="shiki">next line'
  expect(extractCodeBlockText(code)).toBe('const x = 1;\nnext line')
})
