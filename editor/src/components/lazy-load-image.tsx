import { ImageNotFound01Icon } from '@hugeicons/core-free-icons'
import { cn } from 'cn'
import {
  type CSSProperties,
  type HTMLAttributeReferrerPolicy,
  type ReactNode,
  useState
} from 'react'

import { Skeleton } from '@/components/ui/skeleton'

import { Icon } from './icons'

/**
 * Every image fetched from the network (exodus's `LazyLoadImage`, the owner's rule): a skeleton while it loads, a fade
 * in, an icon — or the caller's `fallback` — when it fails. Covers, the Unsplash grid; body images get the same through
 * `extensions/image-loading.ts`.
 */
export function LazyLoadImage({
  src,
  alt,
  className,
  imgClassName,
  imgStyle,
  referrerPolicy,
  fallback,
  onLoad,
  imgTestId
}: {
  src: string
  alt: string
  /** The box. Sized by the caller: `size-full` by default, for a tile. */
  className?: string
  /** On the image itself (`object-cover` by default). */
  imgClassName?: string
  /** On the image itself: a cover's `object-position`. */
  imgStyle?: CSSProperties
  referrerPolicy?: HTMLAttributeReferrerPolicy
  /** Drawn instead of the default icon when the image fails. */
  fallback?: ReactNode
  onLoad?: () => void
  imgTestId?: string
}) {
  // Keyed by the source: another picture starts loading afresh.
  const [state, setState] = useState<{ src: string; status: 'loading' | 'loaded' | 'failed' }>({
    src,
    status: 'loading'
  })
  const status = state.src === src ? state.status : 'loading'

  if (status === 'failed' && fallback !== undefined) return <>{fallback}</>

  return (
    <div
      className={cn(
        'relative flex size-full items-center justify-center overflow-hidden',
        className
      )}
      data-slot="lazy-image"
      data-status={status}
    >
      {status === 'loading' && <Skeleton className="absolute inset-0 size-full rounded-none" />}
      {status !== 'failed' && (
        <img
          src={src}
          alt={alt}
          loading="lazy"
          decoding="async"
          draggable={false}
          referrerPolicy={referrerPolicy}
          onLoad={() => {
            setState({ src, status: 'loaded' })
            onLoad?.()
          }}
          onError={() => setState({ src, status: 'failed' })}
          style={imgStyle}
          data-testid={imgTestId}
          className={cn(
            'size-full object-cover transition-opacity duration-(--motion-pop-in) ease-out',
            status === 'loaded' ? 'opacity-100' : 'opacity-0',
            imgClassName
          )}
        />
      )}
      {status === 'failed' && (
        <div className="flex size-full items-center justify-center bg-muted text-muted-foreground">
          <Icon icon={ImageNotFound01Icon} className="size-1/3 max-h-12 max-w-12" aria-hidden />
        </div>
      )}
    </div>
  )
}
