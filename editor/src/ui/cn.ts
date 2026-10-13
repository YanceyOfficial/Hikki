export { cn } from '@/lib/utils'

/** The few class recipes that aren't a shadcn component: the floating layer and the page column. */
export const ui = {
  floating:
    'hk-floating fixed left-0 top-0 z-50 overflow-y-auto overscroll-contain rounded-xl bg-popover text-popover-foreground shadow-popover',
  column: 'hk-column mx-auto box-border max-w-[calc(var(--size-column)+96px)] px-12 max-sm:px-5'
}
