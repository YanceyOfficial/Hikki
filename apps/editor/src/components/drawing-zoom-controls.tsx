import type { Root } from 'react-dom/client'

import { Button } from '@/components/ui/button'

import { t } from '../core/i18n'
import { ArrowsInIcon, MagnifyingGlassMinusIcon, MagnifyingGlassPlusIcon } from '../generated/icons'
import { IconProvider } from './icons'

type Props = {
  /** 1 is the whole drawing. */
  zoom: number
  max: number
  onZoomIn: () => void
  onZoomOut: () => void
  /** Back to the whole drawing. */
  onFit: () => void
}

/**
 * The zoom controls over a drawing's preview in the page (`extensions/drawing-zoom.ts`): out, how far in, in, and the
 * whole drawing again. The block shows them on hover, and while zoomed on a touch screen.
 */
function DrawingZoomControls({ zoom, max, onZoomIn, onZoomOut, onFit }: Props) {
  const fitted = zoom <= 1
  return (
    <div className="flex items-center gap-0.5 rounded-lg bg-popover p-0.5 text-popover-foreground shadow-popover">
      <Button
        variant="ghost"
        size="icon-xs"
        aria-label={t('drawing.zoomOut')}
        disabled={fitted}
        onClick={onZoomOut}
      >
        <MagnifyingGlassMinusIcon />
      </Button>
      <span
        className="min-w-10 text-center text-xs text-muted-foreground tabular-nums"
        aria-live="polite"
      >
        {t('drawing.zoomLevel', { percent: Math.round(zoom * 100) })}
      </span>
      <Button
        variant="ghost"
        size="icon-xs"
        aria-label={t('drawing.zoomIn')}
        disabled={zoom >= max}
        onClick={onZoomIn}
      >
        <MagnifyingGlassPlusIcon />
      </Button>
      <Button
        variant="ghost"
        size="icon-xs"
        aria-label={t('drawing.zoomFit')}
        disabled={fitted}
        onClick={onFit}
      >
        <ArrowsInIcon />
      </Button>
    </div>
  )
}

export function renderDrawingZoomControls(root: Root, props: Props): void {
  root.render(
    <IconProvider>
      <DrawingZoomControls {...props} />
    </IconProvider>
  )
}
