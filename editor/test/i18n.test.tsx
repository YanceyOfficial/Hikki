import { act, cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'

import { filterBlockTypes } from '../src/core/blocks'
import { EditorBridge } from '../src/core/bridge'
import i18n, { resolveLocale, setLocale } from '../src/core/i18n'
import en from '../src/locales/en.json'
import zhHans from '../src/locales/zh-Hans.json'
import { PageHeader } from '../src/page/page-header'
import { page } from './helpers'

const keys = (obj: object, prefix = ''): string[] =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object' ? keys(v, `${prefix}${k}.`) : [`${prefix}${k}`]
  )

describe('i18n', () => {
  afterEach(async () => {
    cleanup()
    await i18n.changeLanguage('en')
  })

  it('resolves BCP-47 tags to a shipped locale', () => {
    expect(resolveLocale('zh-Hans')).toBe('zh-Hans')
    expect(resolveLocale('zh-Hans-CN')).toBe('zh-Hans')
    expect(resolveLocale('zh-CN')).toBe('zh-Hans')
    expect(resolveLocale('zh-Hant-TW')).toBe('en') // not shipped yet → English, not Simplified
    expect(resolveLocale('ja')).toBe('en')
    expect(resolveLocale(undefined)).toBe('en')
  })

  it('ships the same keys in every catalog', () => {
    expect(keys(zhHans).toSorted()).toEqual(keys(en).toSorted())
  })

  it('switches the page header and block names when the native side sets the locale', async () => {
    const host = document.createElement('div')
    document.body.append(host)
    const bridge = new EditorBridge(host, { post: async () => null })
    render(<PageHeader bridge={bridge} />)
    act(() => bridge.loadDocument(page('a')))
    expect((screen.getByLabelText('Page title') as HTMLTextAreaElement).placeholder).toBe(
      'Untitled'
    )

    await act(async () => {
      setLocale('zh-Hans-CN')
    })
    expect((screen.getByLabelText('页面标题') as HTMLTextAreaElement).placeholder).toBe('无标题')
    expect(screen.getByText('添加图标')).toBeTruthy()
    expect(filterBlockTypes('todo')[0].label()).toBe('待办列表')
    expect(document.documentElement.lang).toBe('zh-Hans')
    host.remove()
  })
})
