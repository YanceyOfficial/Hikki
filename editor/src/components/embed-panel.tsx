import { useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'

import { t } from '../core/i18n'
import { embedFromHTML, embedFromURL, type EmbedProvider, type EmbedSource } from '../lib/embeds'
import type { FloatingAnchor, FloatingLayer } from './floating'

/** Placeholders, spelled out so the l10n audit sees every key. */
const PLACEHOLDER: Record<EmbedProvider | 'html', () => string> = {
  generic: () => t('embed.placeholder.generic'),
  html: () => t('embed.placeholder.html'),
  googleDrive: () => t('embed.placeholder.googleDrive'),
  tweet: () => t('embed.placeholder.tweet'),
  gist: () => t('embed.placeholder.gist'),
  googleMaps: () => t('embed.placeholder.googleMaps'),
  figma: () => t('embed.placeholder.figma'),
  youtube: () => t('embed.placeholder.youtube'),
  vimeo: () => t('embed.placeholder.vimeo'),
  codepen: () => t('embed.placeholder.codepen')
}

type Props = {
  /** Which "/" item opened it: the placeholder names the service; `html` takes a snippet instead of a link. */
  provider: EmbedProvider | 'html'
  onDone: (source: EmbedSource) => void
  onCancel: () => void
}

/** Where the link goes in; the panel checks it and inserts, or says the link can't be embedded. */
export function EmbedPanel({ provider, onDone, onCancel }: Props) {
  const [value, setValue] = useState('')
  const [invalid, setInvalid] = useState(false)
  const html = provider === 'html'
  const submit = () => {
    const source = html ? embedFromHTML(value) : embedFromURL(value)
    if (source) onDone(source)
    else setInvalid(true)
  }
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.nativeEvent.isComposing) return
    if (e.key === 'Escape') {
      e.preventDefault()
      onCancel()
    } else if (e.key === 'Enter' && (!html || e.metaKey || e.ctrlKey)) {
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
      placeholder={PLACEHOLDER.html()}
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
      placeholder={PLACEHOLDER[provider]()}
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
            t('embed.hintHtml')
          ) : (
            t('embed.hintLink')
          )}
        </span>
        <Button size="xs" onClick={submit} disabled={!value.trim()}>
          {t('embed.insert')}
        </Button>
      </div>
    </div>
  )
}

/** Shows the panel in its floating layer at the caret (the extension holds no JSX). */
export function renderEmbedPanel(layer: FloatingLayer, props: Props, anchor: FloatingAnchor): void {
  layer.render(<EmbedPanel {...props} />, anchor)
}
