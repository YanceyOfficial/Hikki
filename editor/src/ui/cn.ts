/** Joins class names, skipping falsy entries: cn('a', cond && 'b'). */
export function cn(...classes: (string | false | null | undefined)[]): string {
  return classes.filter(Boolean).join(' ')
}

/** Shared class recipes (shadcn-style variants without a dependency). */
export const ui = {
  floating:
    'hk-floating fixed left-0 top-0 z-50 overflow-y-auto overscroll-contain rounded-xl bg-popover text-popover-foreground shadow-popover',
  button:
    'inline-flex h-7 cursor-pointer items-center rounded-md px-2 text-base text-subtle-foreground hover:bg-accent disabled:cursor-default disabled:opacity-50',
  ghost:
    'inline-flex h-7 cursor-pointer items-center gap-1.5 rounded-md px-2 text-base text-muted-foreground hover:bg-accent hover:text-subtle-foreground',
  input:
    'h-7 min-w-0 flex-1 rounded-md border border-border bg-muted px-2 text-base text-foreground outline-none focus:border-primary focus:ring-3 focus:ring-ring',
  chip: 'cursor-pointer rounded-sm bg-white/90 px-2 py-1 text-sm text-black/70 shadow-[0_0_0_1px] shadow-black/10 hover:bg-white',
  column: 'hk-column mx-auto box-border max-w-[calc(var(--size-column)+96px)] px-12 max-sm:px-5'
}
