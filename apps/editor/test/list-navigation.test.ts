import { describe, expect, it } from 'vitest'

import { handleListKey, listStep } from '../src/components/command-list'

describe('list navigation (menus, pickers, suggestions)', () => {
  it('↑ / ↓ move one row and wrap round; other keys are not steps', () => {
    expect(listStep('ArrowDown', 3, 0)).toBe(1)
    expect(listStep('ArrowDown', 3, 2)).toBe(0)
    expect(listStep('ArrowUp', 3, 0)).toBe(2)
    expect(listStep('ArrowUp', 0, 0)).toBe(0)
    expect(listStep('Enter', 3, 1)).toBeNull()
  })

  it('handleListKey steps by the same rule and chooses on Enter or Tab', () => {
    const picked: number[] = []
    let selected = 2
    const handle = (key: string) =>
      handleListKey(
        key,
        3,
        selected,
        (i) => (selected = i),
        (i) => picked.push(i)
      )
    expect(handle('ArrowDown')).toBe(true)
    expect(selected).toBe(0)
    expect(handle('Enter')).toBe(true)
    expect(handle('x')).toBe(false)
    expect(picked).toEqual([0])
  })
})
