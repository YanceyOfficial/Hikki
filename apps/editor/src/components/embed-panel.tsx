import { useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'

import { t } from '../core/i18n'
import { keyLabel } from '../core/shortcuts'
import { embedFromHTML, embedFromURL, type EmbedProvider, type EmbedSource } from '../lib/embeds'
import { isImeKey } from '../lib/ime'
import type { FloatingAnchor, FloatingLayer } from './floating'
import { IconProvider } from './icons'

/**
 * Placeholders for the services the "/" menu lists, spelled out so the l10n audit sees every key; a link of any
 * other service is pasted into Embed (its placeholder).
 */
const PLACEHOLDER: Partial<Record<EmbedProvider | 'html', () => string>> = {
  generic: () => t('embed.placeholder.generic'),
  html: () => t('embed.placeholder.html'),
  googleDrive: () => t('embed.placeholder.googleDrive'),
  figma: () => t('embed.placeholder.figma'),
  miro: () => t('embed.placeholder.miro'),
  loom: () => t('embed.placeholder.loom'),
  airtable: () => t('embed.placeholder.airtable'),
  calendly: () => t('embed.placeholder.calendly'),
  gist: () => t('embed.placeholder.gist'),
  codesandbox: () => t('embed.placeholder.codesandbox'),
  drawio: () => t('embed.placeholder.drawio'),
  excalidraw: () => t('embed.placeholder.excalidraw')
}
const placeholder = (provider: EmbedProvider | 'html') =>
  (PLACEHOLDER[provider] ?? PLACEHOLDER.generic)?.() ?? ''

type Props = {
  /** Which "/" item opened it: the placeholder names the service; `html` takes a snippet instead of a link. */
  provider: EmbedProvider | 'html'
  onDone: (source: EmbedSource) => void
  /** The embed's link (or snippet) being replaced (the block menu's Replace). */
  initial?: string
  replacing?: boolean
}

/** Where the link goes in; the panel checks it and inserts, or says the link can't be embedded. */
export function EmbedPanel({ provider, onDone, initial = '', replacing = false }: Props) {
  const [value, setValue] = useState(initial)
  const [invalid, setInvalid] = useState(false)
  const html = provider === 'html'
  const submit = () => {
    const source = html ? embedFromHTML(value) : embedFromURL(value)
    if (source) onDone(source)
    else setInvalid(true)
  }
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (isImeKey(e.nativeEvent)) return
    // Escape is the layers' bus (onDismiss cancels): it never reaches the field.
    if (e.key === 'Enter' && (!html || e.metaKey || e.ctrlKey)) {
      e.preventDefault()
      submit()
    }
  }
  const field = html ? (
    <Textarea
      // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to paste into
      autoFocus
      rows={5}
      className="font-mono text-sm md:text-sm"
      placeholder={placeholder('html')}
      aria-label={t('embed.label.html')}
      value={value}
      onChange={(e) => {
        setValue(e.target.value)
        setInvalid(false)
      }}
      onKeyDown={onKeyDown}
    />
  ) : (
    <Input
      // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to paste into
      autoFocus
      type="url"
      inputMode="url"
      className="h-8 text-sm md:text-sm"
      placeholder={placeholder(provider)}
      aria-label={t('embed.label.link')}
      aria-invalid={invalid || undefined}
      value={value}
      onChange={(e) => {
        setValue(e.target.value)
        setInvalid(false)
      }}
      onKeyDown={onKeyDown}
    />
  )
  return (
    <div className="flex flex-col gap-2" data-testid="embed-panel">
      {field}
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">
          {invalid ? (
            <span className="text-destructive">{t('embed.invalid')}</span>
          ) : html ? (
            t('embed.hintHtml', {
              confirm: keyLabel('return', ['command']),
              cancel: keyLabel('escape')
            })
          ) : (
            t('embed.hintLink', { confirm: keyLabel('return'), cancel: keyLabel('escape') })
          )}
        </span>
        <Button size="xs" onClick={submit} disabled={!value.trim()}>
          {replacing ? t('embed.replace') : t('embed.insert')}
        </Button>
      </div>
    </div>
  )
}

/** Shows the panel in its floating layer at the caret (the extension holds no JSX). */
export function renderEmbedPanel(layer: FloatingLayer, props: Props, anchor: FloatingAnchor): void {
  layer.render(
    <IconProvider>
      <EmbedPanel {...props} />
    </IconProvider>,
    anchor
  )
}
