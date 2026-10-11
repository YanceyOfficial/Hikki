import { Extension } from '@tiptap/core'
import { TextStyle } from '@tiptap/extension-text-style'

/** Notion's palette. Names, not CSS colors, are stored, so pages re-theme (light/dark, future palettes). */
export const PALETTE = [
  'gray',
  'brown',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
  'pink',
  'red'
] as const
export type PaletteColor = (typeof PALETTE)[number]

const isPaletteColor = (value: unknown): value is PaletteColor =>
  typeof value === 'string' && (PALETTE as readonly string[]).includes(value)

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    colors: {
      /** Text color of the selection; null back to the default. */
      setTextColor: (color: PaletteColor | null) => ReturnType
      /** Background (highlight) color of the selection; null removes it. */
      setBackgroundColor: (color: PaletteColor | null) => ReturnType
    }
  }
}

/**
 * Text and background colors as attributes of the `textStyle` mark (`data-text-color` /
 * `data-bg-color`, styled from the `ink-*` / `wash-*` tokens in style.css). Unknown names from pasted
 * HTML are dropped.
 */
export const Colors = Extension.create({
  name: 'colors',

  addGlobalAttributes() {
    return [
      {
        types: ['textStyle'],
        attributes: {
          textColor: {
            default: null,
            parseHTML: (el) => {
              const value = el.getAttribute('data-text-color')
              return isPaletteColor(value) ? value : null
            },
            renderHTML: (attrs) =>
              isPaletteColor(attrs.textColor) ? { 'data-text-color': attrs.textColor } : {}
          },
          bgColor: {
            default: null,
            parseHTML: (el) => {
              const value = el.getAttribute('data-bg-color')
              return isPaletteColor(value) ? value : null
            },
            renderHTML: (attrs) =>
              isPaletteColor(attrs.bgColor) ? { 'data-bg-color': attrs.bgColor } : {}
          }
        }
      }
    ]
  },

  addCommands() {
    return {
      setTextColor:
        (color) =>
        ({ chain }) =>
          chain().setMark('textStyle', { textColor: color }).removeEmptyTextStyle().run(),
      setBackgroundColor:
        (color) =>
        ({ chain }) =>
          chain().setMark('textStyle', { bgColor: color }).removeEmptyTextStyle().run()
    }
  }
})

/**
 * `textStyle` that also parses our color spans: Tiptap's only matches spans with a `style` attribute,
 * so colors would be lost when HTML is read back (import, pasting from another app).
 */
export const ColorTextStyle = TextStyle.extend({
  parseHTML() {
    return [
      ...(this.parent?.() ?? []),
      ...(['data-text-color', 'data-bg-color'] as const).map((attribute) => ({
        tag: `span[${attribute}]`,
        consuming: false,
        getAttrs: (el: HTMLElement) => (isPaletteColor(el.getAttribute(attribute)) ? {} : false)
      }))
    ]
  }
})
