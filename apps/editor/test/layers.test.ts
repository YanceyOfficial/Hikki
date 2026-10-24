import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const root = resolve(process.cwd(), 'src')

function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return sources(path)
    return /\.tsx?$/u.test(name) ? [path] : []
  })
}

function resolveImport(from: string, spec: string): string | null {
  let base: string
  if (spec.startsWith('@/')) base = join(root, spec.slice(2))
  else if (spec.startsWith('.')) base = resolve(dirname(from), spec)
  else return null
  for (const ext of ['', '.ts', '.tsx']) {
    const path = base + ext
    if (existsSync(path) && statSync(path).isFile()) return path
  }
  return null
}

/** Each module's runtime imports (type-only imports erased), as paths relative to src/. */
function importGraph(): Map<string, string[]> {
  const graph = new Map<string, string[]>()
  for (const file of sources(root)) {
    const text = readFileSync(file, 'utf8')
    const deps: string[] = []
    for (const m of text.matchAll(
      /^(?:import|export)\s+(type\s+)?([^'"]*?)\s*from\s*'([^']+)'/gmsu
    )) {
      const names = m[2].trim()
      const typeOnly =
        m[1] !== undefined ||
        (/^\{[^}]*\}$/su.test(names) &&
          names
            .slice(1, -1)
            .split(',')
            .map((n) => n.trim())
            .filter(Boolean)
            .every((n) => n.startsWith('type ')))
      if (typeOnly) continue
      const target = resolveImport(file, m[3])
      if (target) deps.push(relative(root, target))
    }
    graph.set(relative(root, file), deps)
  }
  return graph
}

/** Whether `to` can be reached from `from` along runtime imports. */
function reaches(graph: Map<string, string[]>, from: string, to: string): boolean {
  const seen = new Set<string>()
  const stack = [...(graph.get(from) ?? [])]
  while (stack.length > 0) {
    const next = stack.pop()!
    if (next === to) return true
    if (seen.has(next)) continue
    seen.add(next)
    stack.push(...(graph.get(next) ?? []))
  }
  return false
}

describe('module layers', () => {
  const graph = importGraph()

  it('core/ never imports from components/ (its data and logic live in core/ or lib/)', () => {
    const offending = [...graph].flatMap(([file, deps]) =>
      file.startsWith('core/')
        ? deps.filter((d) => d.startsWith('components/')).map((d) => `${file} → ${d}`)
        : []
    )
    expect(offending).toEqual([])
  })

  it('no core/ module is part of an import cycle', () => {
    const cyclic = [...graph.keys()].filter((f) => f.startsWith('core/') && reaches(graph, f, f))
    expect(cyclic).toEqual([])
  })
})
