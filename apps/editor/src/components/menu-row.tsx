import { cn } from 'cn'
import type { ComponentProps, ReactNode } from 'react'

import { Button } from '@/components/ui/button'

/**
 * A row in a menu, list or panel ("Turn into", colours, the "/" menu, AI actions, pickers): shadcn's ghost
 * `Button` drawn as a full-width row, so every row fades its hover and presses the same way. Roles and state
 * (`role="menuitem"`, `aria-checked`…) go through as props.
 *
 * `glide`: the list marks its selected row with one `GlidingHighlight` (rows `relative` + `data-index`), so the
 * row draws no hover surface of its own.
 */
export function MenuRow({
  glide = false,
  className,
  ...props
}: ComponentProps<typeof Button> & { glide?: boolean }) {
  return (
    <Button
      variant="ghost"
      className={cn(
        "h-8 w-full cursor-pointer justify-start gap-2.5 rounded-md px-2 text-left text-sm font-normal select-none hover:text-inherit aria-expanded:text-inherit coarse:h-10 [&_svg:not([class*='size-'])]:size-auto",
        glide
          ? 'relative hover:bg-transparent aria-expanded:bg-transparent dark:hover:bg-transparent'
          : 'hover:bg-accent aria-expanded:bg-accent dark:hover:bg-accent',
        className
      )}
      {...props}
    />
  )
}

/** The small heading over a group of rows. */
export function MenuTitle({ children }: { children: ReactNode }) {
  return (
    <div className="px-2 pt-1.5 pb-1 text-xs font-medium text-muted-foreground">{children}</div>
  )
}
