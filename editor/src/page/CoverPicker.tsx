import { useRef, useState } from 'react'
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
    <div className="hk-cover-picker">
      <div className="hk-cover-picker-head">
        <span>Gallery</span>
        <span className="hk-spacer" />
        <button type="button" className="hk-button" disabled={uploading} onClick={() => fileInput.current?.click()}>
          {uploading ? 'Uploading…' : 'Upload'}
        </button>
        {current && <button type="button" className="hk-button" onClick={onRemove}>Remove</button>}
        <input ref={fileInput} type="file" accept={ACCEPTED} hidden onChange={(e) => void upload(e.target.files?.[0])} />
      </div>
      {error && <div className="hk-error">{error}</div>}
      <div className="hk-cover-grid">
        {GRADIENTS.map((g) => (
          <button
            key={g.id}
            type="button"
            className="hk-cover-swatch"
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
