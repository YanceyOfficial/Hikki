import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { installScrollContainment } from '../src/lib/scroll-containment'

let remove: () => void
let popup: HTMLDivElement
let list: HTMLDivElement
let item: HTMLDivElement

/** A list `content` tall in a `height` box, scrolled to `top`. */
function size(element: HTMLElement, height: number, content: number, top = 0) {
  Object.defineProperty(element, 'clientHeight', { value: height, configurable: true })
  Object.defineProperty(element, 'scrollHeight', { value: content, configurable: true })
  element.scrollTop = top
  Object.defineProperty(element, 'scrollTop', { value: top, configurable: true, writable: true })
}

const wheel = (target: Element, deltaY: number) => {
  const event = new WheelEvent('wheel', { deltaY, bubbles: true, cancelable: true })
  target.dispatchEvent(event)
  return event.defaultPrevented
}

beforeEach(() => {
  remove = installScrollContainment()
  popup = document.createElement('div')
  popup.className = 'hk-pop'
  list = document.createElement('div')
  list.style.overflowY = 'auto'
  item = document.createElement('div')
  list.append(item)
  popup.append(list)
  document.body.append(popup)
})
afterEach(() => {
  remove()
  popup.remove()
})

describe('scroll containment', () => {
  it('stops a scroll over a popup that has nothing to scroll', () => {
    size(list, 200, 200)
    expect(wheel(item, 40)).toBe(true)
    expect(wheel(item, -40)).toBe(true)
  })

  it('lets a popup scroll its own list, and stops at either end', () => {
    size(list, 200, 600, 100)
    expect(wheel(item, 40)).toBe(false)
    expect(wheel(item, -40)).toBe(false)
    size(list, 200, 600, 0)
    expect(wheel(item, -40)).toBe(true)
    size(list, 200, 600, 400)
    expect(wheel(item, 40)).toBe(true)
  })

  it('leaves the page itself alone', () => {
    const page = document.createElement('p')
    document.body.append(page)
    expect(wheel(page, 40)).toBe(false)
    page.remove()
  })
})
