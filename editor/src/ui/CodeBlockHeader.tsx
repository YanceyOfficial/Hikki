import { CaretDown, Check, Copy } from '@phosphor-icons/react'
import { useEffect, useRef, useState } from 'react'

import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'

import { filterLanguages, findLanguage } from '../extensions/code-languages'
import { t } from '../i18n'
import { cn } from './cn'
import { handleListKey } from './CommandList'

type Props = {
  language: string
  editable: boolean
  onLanguage: (id: string) => void
  getText: () => string
}

/** Copied-state feedback lasts this long. */
const COPIED_MS = 1500

/**
 * The bar inside a code block: the language (a searchable picker) on the left, copy on the right. The
 * copy button shows on hover (always on touch); the language stays visible, quietly.
 */
export function CodeBlockHeader({ language, editable, onLanguage, getText }: Props) {
  const [open, setOpen] = useState(false)
  const [copied, setCopied] = useState(false)
  const label =
    language === 'plaintext' ? t('code.plainText') : (findLanguage(language)?.name ?? language)

  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), COPIED_MS)
    return () => clearTimeout(timer)
  }, [copied])

  return (
    <div className="flex h-7 items-center justify-between gap-2 px-2 pt-1.5 select-none">
      {editable ? (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger
            render={
              <button
                type="button"
                className="inline-flex h-6 cursor-pointer items-center gap-1 rounded-md px-1.5 text-xs text-muted-foreground hover:bg-accent hover:text-subtle-foreground"
                aria-label={t('code.language')}
              />
            }
          >
            {label}
            <CaretDown size={10} aria-hidden />
          </PopoverTrigger>
          <PopoverContent align="start" className="w-56 gap-0 p-0">
            <LanguageList
              current={language}
              onPick={(id) => {
                setOpen(false)
                onLanguage(id)
              }}
            />
          </PopoverContent>
        </Popover>
      ) : (
        <span className="px-1.5 text-xs text-muted-foreground">{label}</span>
      )}
      <button
        type="button"
        className={cn(
          'inline-flex h-6 cursor-pointer items-center gap-1 rounded-md px-1.5 text-xs text-muted-foreground opacity-0 transition-opacity duration-(--motion-pop-in) group-hover/code:opacity-100 hover:bg-accent hover:text-subtle-foreground focus-visible:opacity-100 touch:opacity-100',
          copied && 'opacity-100'
        )}
        onClick={() => {
          void navigator.clipboard?.writeText(getText()).then(() => setCopied(true))
        }}
      >
        {copied ? <Check size={12} aria-hidden /> : <Copy size={12} aria-hidden />}
        {copied ? t('code.copied') : t('code.copy')}
      </button>
    </div>
  )
}

function LanguageList({ current, onPick }: { current: string; onPick: (id: string) => void }) {
  const [query, setQuery] = useState('')
  const items = filterLanguages(query)
  const [selected, setSelected] = useState(() =>
    Math.max(
      0,
      items.findIndex((l) => l.id === current)
    )
  )
  const listRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    listRef.current
      ?.querySelector<HTMLElement>(`[data-index="${selected}"]`)
      ?.scrollIntoView?.({ block: 'nearest' })
  }, [selected])

  return (
    <div className="flex flex-col">
      <input
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- the picker opens to type a language
        autoFocus
        className="h-9 border-b border-border bg-transparent px-3 text-sm outline-none placeholder:text-placeholder"
        placeholder={t('code.searchLanguage')}
        aria-label={t('code.searchLanguage')}
        value={query}
        onChange={(e) => {
          setQuery(e.target.value)
          setSelected(0)
        }}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return
          const handled = handleListKey(e.key, items.length, selected, setSelected, (i) =>
            onPick(items[i].id)
          )
          if (handled) e.preventDefault()
        }}
      />
      <div ref={listRef} role="listbox" className="max-h-64 overflow-y-auto p-1">
        {items.length === 0 && (
          <div className="px-2 py-1.5 text-sm text-muted-foreground">{t('editor.noResults')}</div>
        )}
        {items.map((language, i) => (
          <button
            key={language.id}
            type="button"
            role="option"
            aria-selected={i === selected}
            data-index={i}
            className={cn(
              'flex h-8 w-full cursor-pointer items-center justify-between rounded-md px-2 text-left text-sm',
              i === selected && 'bg-accent'
            )}
            onMouseMove={() => i !== selected && setSelected(i)}
            onClick={() => onPick(language.id)}
          >
            {language.id === 'plaintext' ? t('code.plainText') : language.name}
            {language.id === current && <Check size={14} aria-hidden />}
          </button>
        ))}
      </div>
    </div>
  )
}
