import { formatDistanceToNow } from 'date-fns'
import { ImagePlus, SmilePlus, X } from 'lucide-react'
import { useRef, useState } from 'react'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import { backend } from '#lib/backend/index'
import type { Doc } from '#lib/types'

const EMOJI = [
  '📝',
  '📚',
  '💡',
  '🚀',
  '🎯',
  '📌',
  '🗂️',
  '🧠',
  '☕',
  '🌱',
  '🔥',
  '⭐',
  '💼',
  '🏠',
  '🎨',
  '🎵',
  '🧪',
  '💰',
  '❤️',
  '🗓️',
  '✅',
  '✈️',
  '🍜',
  '🏋️',
  '🐛',
  '🔒',
  '🌍',
  '📷',
  '🎁',
  '⚡'
]

interface PageHeaderProps {
  doc: Doc
  onPatch: (patch: Partial<Doc>) => void
}

export function PageHeader({ doc, onPatch }: PageHeaderProps) {
  const coverInput = useRef<HTMLInputElement>(null)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)

  const pickIcon = (icon: string | null) => {
    onPatch({ icon })
    setIconPickerOpen(false)
  }

  const uploadCover = async (file: File | undefined) => {
    if (!file) return
    try {
      const imported = await backend.importAsset(doc.id, file)
      onPatch({ cover: imported.fileName })
    } catch (error) {
      // Full error funnel (toasts, HK codes) arrives in Phase 4.
      console.error('hikki: cover upload failed', error)
    }
  }

  return (
    <header data-testid="page-header">
      {doc.cover ? (
        <div className="group relative left-1/2 -mt-12 mb-6 h-56 w-[100cqw] -translate-x-1/2">
          <img
            data-testid="doc-cover-image"
            src={backend.assetUrl(doc.id, doc.cover)}
            alt=""
            className="h-full w-full object-cover"
          />
          <Button
            variant="secondary"
            size="sm"
            className="absolute right-6 bottom-3 opacity-0 transition-opacity group-hover:opacity-100"
            onClick={() => onPatch({ cover: null })}
            data-testid="doc-cover-remove"
          >
            <X /> Remove cover
          </Button>
        </div>
      ) : null}
      <div className="flex items-center gap-2">
        <Popover open={iconPickerOpen} onOpenChange={setIconPickerOpen}>
          <PopoverTrigger
            render={
              <Button
                variant="ghost"
                size="icon"
                className="size-10 text-2xl"
                data-testid="doc-icon-button"
              />
            }
          >
            {doc.icon ?? <SmilePlus className="text-muted-foreground size-5" />}
          </PopoverTrigger>
          <PopoverContent className="w-64" align="start">
            <div className="grid grid-cols-6 gap-1">
              {EMOJI.map((emoji) => (
                <Button
                  key={emoji}
                  variant="ghost"
                  size="icon"
                  className="size-9 text-lg"
                  onClick={() => pickIcon(emoji)}
                  data-testid={`doc-icon-option-${emoji}`}
                >
                  {emoji}
                </Button>
              ))}
            </div>
            {doc.icon ? (
              <Button
                variant="ghost"
                size="sm"
                className="mt-2 w-full"
                onClick={() => pickIcon(null)}
                data-testid="doc-icon-remove"
              >
                Remove icon
              </Button>
            ) : null}
          </PopoverContent>
        </Popover>
        {!doc.cover && (
          <Button
            variant="ghost"
            size="sm"
            className="text-muted-foreground"
            onClick={() => coverInput.current?.click()}
            data-testid="doc-cover-add"
          >
            <ImagePlus /> Add cover
          </Button>
        )}
        <input
          ref={coverInput}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0]
            e.target.value = ''
            void uploadCover(file)
          }}
          data-testid="doc-cover-input"
        />
      </div>
      <input
        data-testid="doc-title"
        className="placeholder:text-muted-foreground/50 mt-2 w-full bg-transparent text-4xl font-bold outline-none"
        placeholder="Untitled"
        value={doc.title}
        onChange={(e) => onPatch({ title: e.target.value })}
      />
      <p
        data-testid="doc-updated-at"
        className="text-muted-foreground mt-1 text-xs"
      >
        Edited{' '}
        {formatDistanceToNow(new Date(doc.updatedAt), { addSuffix: true })}
      </p>
    </header>
  )
}
