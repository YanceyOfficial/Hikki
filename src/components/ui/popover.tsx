import { Popover as PopoverPrimitive } from '@base-ui/react/popover'
import * as React from 'react'

import { cn } from '#lib/utils'

function Popover({ ...props }: PopoverPrimitive.Root.Props) {
  return <PopoverPrimitive.Root data-slot="popover" {...props} />
}

// `asChild` callers hand us an arbitrary element to render in place of Base
// UI's default `<button>`. Base UI validates both directions - `nativeButton`
// (default `true`) assumes the rendered element already has real button
// semantics, and warns if it doesn't; explicitly setting `nativeButton={false}`
// warns right back if the element turns out to actually be a `<button>` (see
// its own message: "Use a non-<button> in the `render` prop, or set
// `nativeButton` to `true`"). So there's no single safe default - it depends
// on what the child actually is. BlockNote's own internal `asChild` callers
// are inconsistent here: `CreateLinkButton`/`EditLinkButton`/etc. pass a real
// `<button>`-rendering component (confirmed via `@blocknote/react`'s source -
// `Components.FormattingToolbar.Button`), while `EmojiPicker` (the "add
// reaction" trigger on comments) passes a raw `<div onClick>` - a real, raw
// host element we CAN introspect via `children.type` since it's a string tag,
// not a component reference.
function isDivElement(node: React.ReactNode): boolean {
  return React.isValidElement(node) && node.type === 'div'
}

function PopoverTrigger({
  asChild,
  children,
  ...props
}: PopoverPrimitive.Trigger.Props & {
  asChild?: boolean
  children?: React.ReactNode
}) {
  return (
    <PopoverPrimitive.Trigger
      data-slot="popover-trigger"
      render={asChild ? (children as React.ReactElement) : undefined}
      nativeButton={asChild && isDivElement(children) ? false : undefined}
      {...props}
    >
      {asChild ? undefined : children}
    </PopoverPrimitive.Trigger>
  )
}

// `anchor` is forwarded straight through to Base UI's `Positioner` (confirmed
// against `useAnchorPositioning` in `@base-ui/react`'s source: with no
// `anchor` and no mounted `PopoverTrigger`, the positioner has no reference
// element to measure against at all, not merely a default-to-origin - the
// popup never becomes `isPositioned`). Every existing caller renders a
// `PopoverTrigger` as a sibling and never passes this, so it's an
// additive, backward-compatible prop - only `writing-tools-popover.tsx`
// (Task 10) needs it, since it's opened from a toolbar button that lives in
// a completely different part of the tree (BlockNote's own floating
// formatting toolbar) rather than as a sibling `PopoverTrigger` here.
function PopoverContent({
  className,
  align = 'center',
  alignOffset = 0,
  side = 'bottom',
  sideOffset = 4,
  anchor,
  ...props
}: PopoverPrimitive.Popup.Props &
  Pick<
    PopoverPrimitive.Positioner.Props,
    'align' | 'alignOffset' | 'side' | 'sideOffset' | 'anchor'
  >) {
  return (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Positioner
        anchor={anchor}
        align={align}
        alignOffset={alignOffset}
        side={side}
        sideOffset={sideOffset}
        className="isolate z-50"
      >
        <PopoverPrimitive.Popup
          data-slot="popover-content"
          className={cn(
            'z-50 flex w-72 origin-(--transform-origin) flex-col gap-2.5 rounded-lg border border-border/60 bg-popover p-2.5 text-sm text-popover-foreground shadow-lg outline-hidden duration-100 data-[side=bottom]:slide-in-from-top-2 data-[side=inline-end]:slide-in-from-left-2 data-[side=inline-start]:slide-in-from-right-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95',
            className
          )}
          {...props}
        />
      </PopoverPrimitive.Positioner>
    </PopoverPrimitive.Portal>
  )
}

function PopoverHeader({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="popover-header"
      className={cn('flex flex-col gap-0.5 text-sm', className)}
      {...props}
    />
  )
}

function PopoverTitle({ className, ...props }: PopoverPrimitive.Title.Props) {
  return (
    <PopoverPrimitive.Title
      data-slot="popover-title"
      className={cn('font-medium', className)}
      {...props}
    />
  )
}

function PopoverDescription({
  className,
  ...props
}: PopoverPrimitive.Description.Props) {
  return (
    <PopoverPrimitive.Description
      data-slot="popover-description"
      className={cn('text-muted-foreground', className)}
      {...props}
    />
  )
}

export {
  Popover,
  PopoverContent,
  PopoverDescription,
  PopoverHeader,
  PopoverTitle,
  PopoverTrigger
}
