import { guessLanguage } from '#lib/guess-language'

test('detects python from a def with a trailing colon', () => {
  const code = `def add(a, b):\n    return a + b\n`
  expect(guessLanguage(code)).toBe('python')
})

test('detects rust from fn plus arrow return type', () => {
  const code = `fn add(a: i32, b: i32) -> i32 {\n    a + b\n}\n`
  expect(guessLanguage(code)).toBe('rust')
})

test('detects rust from fn plus let mut', () => {
  const code = `fn main() {\n    let mut count = 0;\n    count += 1;\n}\n`
  expect(guessLanguage(code)).toBe('rust')
})

test('detects go from func plus package', () => {
  const code = `package main\n\nfunc main() {\n    println("hi")\n}\n`
  expect(guessLanguage(code)).toBe('go')
})

test('detects php from the opening tag', () => {
  const code = `<?php\n\necho "hello";\n`
  expect(guessLanguage(code)).toBe('php')
})

test('detects cpp from #include plus main and C++-only syntax', () => {
  const code = `#include <iostream>\n\nint main() {\n    std::cout << "hi";\n}\n`
  expect(guessLanguage(code)).toBe('cpp')
})

test('detects c from #include plus main without C++ syntax', () => {
  const code = `#include <stdio.h>\n\nint main() {\n    printf("hi");\n    return 0;\n}\n`
  expect(guessLanguage(code)).toBe('c')
})

test('detects sql from select plus from, case-insensitively', () => {
  const code = `select id, name\nfrom users\nwhere active = true;\n`
  expect(guessLanguage(code)).toBe('sql')
})

test('detects javascript from commonjs require/module.exports', () => {
  const code = `const fs = require('fs');\n\nmodule.exports = { fs };\n`
  expect(guessLanguage(code)).toBe('javascript')
})

test('detects javascript from an ES module import/from', () => {
  const code = `import { readFile } from 'fs';\n\nreadFile('a.txt');\n`
  expect(guessLanguage(code)).toBe('javascript')
})

test('returns undefined for plain, ambiguous text', () => {
  const code = `Just a note to self about tomorrow's meeting.`
  expect(guessLanguage(code)).toBeUndefined()
})

test('returns undefined for empty input', () => {
  expect(guessLanguage('')).toBeUndefined()
})
