import { useEffect, useRef, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { cn } from '@/lib/utils'

import { GRADIENTS, gradientCover } from './covers'
import { bffURL, searchUnsplash, trackUnsplashDownload, type UnsplashPhoto } from './unsplash'

type Props = {
  current: string | null
  onSelect: (cover: string) => void
  onRemove: () => void
  onUpload: (file: File) => Promise<void>
}

const ACCEPTED = 'image/png,image/jpeg,image/gif,image/webp,image/heic'

/** Notion-style cover picker: Gallery / Upload / Link / Unsplash, Remove on the right. */
export function CoverPicker({ current, onSelect, onRemove, onUpload }: Props) {
  return (
    <Tabs defaultValue="gallery" className="gap-0">
      <div className="flex items-center border-b border-border px-2">
        <TabsList variant="line" className="h-10">
          <TabsTrigger value="gallery">Gallery</TabsTrigger>
          <TabsTrigger value="upload">Upload</TabsTrigger>
          <TabsTrigger value="link">Link</TabsTrigger>
          <TabsTrigger value="unsplash">Unsplash</TabsTrigger>
        </TabsList>
        <span className="flex-1" />
        {current && (
          <Button variant="ghost" size="sm" onClick={onRemove}>
            Remove
          </Button>
        )}
      </div>
      <TabsContent
        value="gallery"
        className="grid grid-cols-[repeat(auto-fill,minmax(88px,1fr))] gap-2 p-3"
      >
        {GRADIENTS.map((g) => (
          <button
            key={g.id}
            type="button"
            className={cn(
              'h-14 cursor-pointer rounded-sm shadow-[inset_0_0_0_1px_var(--color-border)] hover:opacity-85',
              current === gradientCover(g.id) && 'outline-2 outline-offset-2 outline-primary'
            )}
            aria-label={g.label}
            aria-pressed={current === gradientCover(g.id)}
            style={{ background: g.css }}
            onClick={() => onSelect(gradientCover(g.id))}
          />
        ))}
      </TabsContent>
      <TabsContent value="upload" className="p-3">
        <UploadPane onUpload={onUpload} />
      </TabsContent>
      <TabsContent value="link" className="p-3">
        <LinkPane onSelect={onSelect} />
      </TabsContent>
      <TabsContent value="unsplash" className="p-3">
        <UnsplashPane onSelect={onSelect} />
      </TabsContent>
    </Tabs>
  )
}

function UploadPane({ onUpload }: { onUpload: Props['onUpload'] }) {
  const input = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const upload = async (file: File | undefined) => {
    if (!file) return
    setBusy(true)
    setError(null)
    try {
      await onUpload(file)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="flex flex-col items-center gap-2 py-4">
      <Button
        variant="outline"
        className="w-full"
        disabled={busy}
        onClick={() => input.current?.click()}
      >
        {busy ? 'Uploading…' : 'Upload file'}
      </Button>
      <p className="m-0 text-xs text-muted-foreground">Images wider than 1500 pixels work best.</p>
      {error && <p className="m-0 text-xs text-destructive">{error}</p>}
      <input
        ref={input}
        type="file"
        accept={ACCEPTED}
        hidden
        onChange={(e) => void upload(e.target.files?.[0])}
      />
    </div>
  )
}

function LinkPane({ onSelect }: { onSelect: Props['onSelect'] }) {
  const [value, setValue] = useState('')
  const valid = /^https:\/\/\S+$/u.test(value.trim())
  return (
    <form
      className="flex flex-col gap-2 py-2"
      onSubmit={(e) => {
        e.preventDefault()
        if (valid) onSelect(value.trim())
      }}
    >
      <Input
        placeholder="Paste an image link…"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        aria-label="Image link"
      />
      <Button type="submit" disabled={!valid}>
        Submit
      </Button>
      <p className="m-0 text-xs text-muted-foreground">Works with any https image on the web.</p>
    </form>
  )
}

function UnsplashPane({ onSelect }: { onSelect: Props['onSelect'] }) {
  const [query, setQuery] = useState('')
  const [photos, setPhotos] = useState<UnsplashPhoto[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const configured = bffURL() !== null

  useEffect(() => {
    if (!configured) return
    let alive = true
    const timer = setTimeout(() => {
      searchUnsplash(query)
        .then((page) => alive && (setPhotos(page.photos), setError(null)))
        .catch(
          (e: unknown) =>
            alive &&
            setError(
              e instanceof Error && e.message === 'rate_limited'
                ? 'Unsplash is busy — try again later.'
                : 'Could not load Unsplash.'
            )
        )
    }, 300)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [query, configured])

  if (!configured) {
    return (
      <p className="m-0 py-6 text-center text-xs text-muted-foreground">
        Unsplash isn't configured for this build.
      </p>
    )
  }
  return (
    <div className="flex flex-col gap-3">
      <Input
        placeholder="Search for an image…"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        aria-label="Search Unsplash"
      />
      {error && <p className="m-0 text-xs text-destructive">{error}</p>}
      <div className="grid max-h-80 grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-3 overflow-y-auto">
        {photos?.map((photo) => (
          <figure key={photo.id} className="m-0 flex min-w-0 flex-col gap-1">
            <button
              type="button"
              className="aspect-[16/10] cursor-pointer overflow-hidden rounded-sm bg-muted hover:opacity-85"
              style={{ backgroundColor: photo.color ?? undefined }}
              onClick={() => {
                trackUnsplashDownload(photo)
                onSelect(photo.regular)
              }}
              aria-label={photo.alt ?? `Photo by ${photo.author}`}
            >
              <img src={photo.thumb} alt="" loading="lazy" className="size-full object-cover" />
            </button>
            <figcaption className="truncate text-xs text-muted-foreground">
              by{' '}
              <a href={photo.authorUrl} target="_blank" rel="noreferrer" className="underline">
                {photo.author}
              </a>
            </figcaption>
          </figure>
        ))}
      </div>
    </div>
  )
}
