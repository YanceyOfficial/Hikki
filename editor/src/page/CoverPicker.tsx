import { useRef, useState } from 'react'
import { cn, ui } from '../ui/cn'
import { GRADIENTS, gradientCover } from './covers'

type Props = {
  current: string | null
  onSelect: (cover: string) => void
  onRemove: () => void
  onUpload: (file: File) => Promise<void>
}

const ACCEPTED = 'image/png,image/jpeg,image/gif,image/webp,image/heic'

export function CoverPicker({ current, onSelect, onRemove, onUpload }: Props) {
  const fileInput = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const upload = async (file: File | undefined) => {
    if (!file) return
    setUploading(true)
    setError(null)
    try {
      await onUpload(file)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setUploading(false)
    }
  }

  return (
    <div>
      <div className="flex items-center gap-1 border-b border-border px-2.5 py-2 text-base font-medium">
        <span>Gallery</span>
        <span className="flex-1" />
        <button type="button" className={ui.button} disabled={uploading} onClick={() => fileInput.current?.click()}>
          {uploading ? 'Uploading…' : 'Upload'}
        </button>
        {current && <button type="button" className={ui.button} onClick={onRemove}>Remove</button>}
        <input ref={fileInput} type="file" accept={ACCEPTED} hidden onChange={(e) => void upload(e.target.files?.[0])} />
      </div>
      {error && <div className="px-3 py-1 text-sm text-destructive">{error}</div>}
      <div className="grid grid-cols-[repeat(auto-fill,minmax(88px,1fr))] gap-2 p-3">
        {GRADIENTS.map((g) => (
          <button
            key={g.id}
            type="button"
            className={cn('h-14 cursor-pointer rounded-sm shadow-[inset_0_0_0_1px_var(--color-border)] hover:opacity-85', current === gradientCover(g.id) && 'outline-2 outline-offset-2 outline-primary')}
            aria-label={g.label}
            aria-pressed={current === gradientCover(g.id)}
            style={{ background: g.css }}
            onClick={() => onSelect(gradientCover(g.id))}
          />
        ))}
      </div>
    </div>
  )
}
