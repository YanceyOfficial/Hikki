export { cn } from '@/lib/utils'

/** Shared class recipes (shadcn-style variants without a dependency). */
export const ui = {
  floating:
    'hk-floating fixed left-0 top-0 z-50 overflow-y-auto overscroll-contain rounded-xl bg-popover text-popover-foreground shadow-popover',
  /** Hover tints fade; a press scales down a touch (`press`), the shared feedback for anything clickable. */
  press:
    'transition-[background-color,color,scale] duration-(--motion-pop-out) ease-out active:scale-[0.97]',
  button:
    'inline-flex h-7 cursor-pointer items-center rounded-md px-2 text-sm text-subtle-foreground transition-[background-color,color,scale] duration-(--motion-pop-out) ease-out hover:bg-accent active:scale-[0.97] disabled:cursor-default disabled:opacity-50',
  ghost:
    'inline-flex h-7 cursor-pointer items-center gap-1.5 rounded-md px-2 text-sm text-muted-foreground transition-[background-color,color,scale] duration-(--motion-pop-out) ease-out hover:bg-accent hover:text-subtle-foreground active:scale-[0.97]',
  input:
    'h-7 min-w-0 flex-1 rounded-md border border-border bg-muted px-2 text-sm text-foreground outline-none focus:border-primary focus:ring-3 focus:ring-ring',
  chip: 'cursor-pointer rounded-sm bg-white/90 px-2 py-1 text-xs text-black/70 shadow-[0_0_0_1px] shadow-black/10 transition-[background-color,scale] duration-(--motion-pop-out) ease-out hover:bg-white active:scale-[0.97]',
  column: 'hk-column mx-auto box-border max-w-[calc(var(--size-column)+96px)] px-12 max-sm:px-5'
}
