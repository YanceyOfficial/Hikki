import { HugeiconsIcon, type HugeiconsIconProps, type IconSvgElement } from '@hugeicons/react'

import {
  ICON_BOLD_STROKE_WIDTH,
  ICON_STROKE_WIDTH,
  iconElements,
  type IconWeight
} from '../lib/icon-svg'

export type { IconSvgElement }

/**
 * Every editor icon: a Hugeicons outline (`@hugeicons/core-free-icons`, imported by its `…Icon` name) at the
 * editor's stroke (`ICON_STROKE_WIDTH`, mirrored from design/icons.json). Sized like text (1em) unless a
 * `size` or a `size-*` class says otherwise; `weight` thickens an active toggle or fills the shape.
 */
export function Icon({
  icon,
  weight = 'regular',
  size = '1em',
  ...props
}: Omit<HugeiconsIconProps, 'strokeWidth' | 'altIcon' | 'showAlt'> & { weight?: IconWeight }) {
  return (
    <HugeiconsIcon
      icon={iconElements(icon, weight)}
      size={size}
      strokeWidth={weight === 'bold' ? ICON_BOLD_STROKE_WIDTH : ICON_STROKE_WIDTH}
      {...props}
    />
  )
}
