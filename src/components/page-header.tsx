import { formatDistanceToNow } from 'date-fns'
import { ImagePlus, SmilePlus, X } from 'lucide-react'
import { useRef, useState } from 'react'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'
import type { Doc } from '#lib/types'

import {
  EmojiPickerSearch,
  EmojiPickerContent,
  EmojiPicker
} from './ui/emoji-picker'

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
      reportError('HK-1004', {
        message: error instanceof Error ? error.message : String(error)
      })
    }
  }

  return (
    <header data-testid="page-header">
      {doc.cover ? (
        <div className="group relative left-1/2 -mt-12 mb-6 h-[30vh] max-h-70 w-[100cqw] -translate-x-1/2">
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
        <Popover onOpenChange={setIconPickerOpen} open={iconPickerOpen}>
          <PopoverTrigger data-testid="doc-icon-button">
            {doc.icon ?? <SmilePlus className="text-muted-foreground size-5" />}
          </PopoverTrigger>
          <PopoverContent className="w-fit p-0">
            <EmojiPicker
              className="h-81.5 rounded-lg border shadow-md"
              onEmojiSelect={({ emoji }) => {
                pickIcon(emoji)
              }}
            >
              <EmojiPickerSearch />
              <EmojiPickerContent />
              {doc.icon ? (
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full py-4"
                  onClick={() => pickIcon(null)}
                  data-testid="doc-icon-remove"
                >
                  Remove icon
                </Button>
              ) : null}
            </EmojiPicker>
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
