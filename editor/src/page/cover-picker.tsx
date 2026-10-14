import { cn } from 'cn'
import { useEffect, useRef, useState } from 'react'
import { Trans, useTranslation } from 'react-i18next'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'

import { LazyLoadImage } from '../components/lazy-load-image'
import { GRADIENTS, gradientCover } from '../lib/covers'
import {
  bffURL,
  searchUnsplash,
  trackUnsplashDownload,
  UNSPLASH_HOME,
  type UnsplashPhoto
} from '../lib/unsplash'

type Props = {
  current: string | null
  onSelect: (cover: string) => void
  onRemove: () => void
  onUpload: (file: File) => Promise<void>
}

const ACCEPTED = 'image/png,image/jpeg,image/gif,image/webp,image/heic'

/** Notion-style cover picker: Gallery / Upload / Link / Unsplash, Remove on the right. */
export function CoverPicker({ current, onSelect, onRemove, onUpload }: Props) {
  const { t } = useTranslation()
  return (
    <Tabs defaultValue="gallery" className="gap-0">
      <div className="flex items-center border-b border-border px-2">
        <TabsList variant="line" className="h-10">
          <TabsTrigger value="gallery">{t('cover.tabs.gallery')}</TabsTrigger>
          <TabsTrigger value="upload">{t('cover.tabs.upload')}</TabsTrigger>
          <TabsTrigger value="link">{t('cover.tabs.link')}</TabsTrigger>
          <TabsTrigger value="unsplash">{t('cover.tabs.unsplash')}</TabsTrigger>
        </TabsList>
        <span className="flex-1" />
        {current && (
          <Button variant="ghost" size="sm" onClick={onRemove}>
            {t('cover.remove')}
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
            aria-label={g.label()}
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
  const { t } = useTranslation()
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
        {busy ? t('cover.uploading') : t('cover.uploadFile')}
      </Button>
      <p className="m-0 text-xs text-muted-foreground">{t('cover.uploadHint')}</p>
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
  const { t } = useTranslation()
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
        placeholder={t('cover.linkPlaceholder')}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        aria-label={t('cover.linkLabel')}
      />
      <Button type="submit" disabled={!valid}>
        {t('cover.linkSubmit')}
      </Button>
      <p className="m-0 text-xs text-muted-foreground">{t('cover.linkHint')}</p>
    </form>
  )
}

function UnsplashPane({ onSelect }: { onSelect: Props['onSelect'] }) {
  const { t } = useTranslation()
  const [query, setQuery] = useState('')
  // Each answer remembers the query it is for: while the current one is still on its way (or the search waits out its
  // debounce) the grid shows skeletons, not the previous results.
  const [results, setResults] = useState<{ query: string; photos: UnsplashPhoto[] } | null>(null)
  const [failure, setFailure] = useState<{ query: string; message: string } | null>(null)
  const error = failure?.query === query ? failure.message : null
  const loading = error === null && results?.query !== query
  const photos = loading ? null : (results?.photos ?? null)
  const configured = bffURL() !== null

  useEffect(() => {
    if (!configured) return
    let alive = true
    const timer = setTimeout(() => {
      searchUnsplash(query)
        .then((page) => alive && setResults({ query, photos: page.photos }))
        .catch(
          (e: unknown) =>
            alive &&
            setFailure({
              query,
              message:
                e instanceof Error && e.message === 'rate_limited'
                  ? t('cover.unsplashBusy')
                  : t('cover.unsplashFailed')
            })
        )
    }, 300)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [query, configured, t])

  if (!configured) {
    return (
      <p className="m-0 py-6 text-center text-xs text-muted-foreground">
        {t('cover.unsplashNotConfigured')}
      </p>
    )
  }
  return (
    <div className="flex flex-col gap-3">
      <Input
        placeholder={t('cover.unsplashSearch')}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        aria-label={t('cover.unsplashLabel')}
      />
      {error && <p className="m-0 text-xs text-destructive">{error}</p>}
      <div className="grid max-h-80 grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-3 overflow-y-auto">
        {loading &&
          Array.from({ length: 9 }, (_, i) => (
            <div key={i} className="flex min-w-0 flex-col gap-1.5" data-testid="unsplash-skeleton">
              <Skeleton className="aspect-[16/10] w-full rounded-sm" />
              <Skeleton className="h-3 w-full rounded-sm" />
              <Skeleton className="h-3 w-2/3 rounded-sm" />
            </div>
          ))}
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
              aria-label={photo.alt ?? t('cover.photoBy', { name: photo.author })}
            >
              <LazyLoadImage src={photo.thumb} alt="" />
            </button>
            <PhotoCredit photo={photo} />
          </figure>
        ))}
      </div>
    </div>
  )
}

/** Unsplash guideline: "Photo by <photographer> on <Unsplash>", both linked (utm-tagged). */
export function PhotoCredit({ photo }: { photo: UnsplashPhoto }) {
  return (
    <figcaption className="line-clamp-2 text-xs leading-snug break-words text-muted-foreground">
      <Trans
        i18nKey="cover.credit"
        values={{ name: photo.author }}
        components={{
          author: (
            <a href={photo.authorUrl} target="_blank" rel="noreferrer" className="underline" />
          ),
          unsplash: (
            <a href={UNSPLASH_HOME} target="_blank" rel="noreferrer" className="underline" />
          )
        }}
      />
    </figcaption>
  )
}
