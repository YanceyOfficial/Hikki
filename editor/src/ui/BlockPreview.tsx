import type { ReactNode } from 'react'

import { cn } from './cn'

/** A placeholder line of text: language-neutral, so previews need no sample copy. */
function Line({ w, className }: { w: string; className?: string }) {
  return (
    <div
      className={cn('h-1.5 rounded-full bg-muted-foreground/25', className)}
      style={{ width: w }}
    />
  )
}

function Lines({ widths }: { widths: string[] }) {
  return (
    <div className="flex flex-col gap-1.5">
      {widths.map((w, i) => (
        <Line key={i} w={w} />
      ))}
    </div>
  )
}

function Rows({ markers, widths }: { markers: ReactNode[]; widths: string[] }) {
  return (
    <div className="flex flex-col gap-2">
      {widths.map((w, i) => (
        <div key={i} className="flex items-center gap-2">
          <span className="flex w-3 flex-none justify-center text-2xs leading-none text-muted-foreground">
            {markers[i]}
          </span>
          <Line w={w} />
        </div>
      ))}
    </div>
  )
}

function Checkbox({ checked }: { checked: boolean }) {
  return (
    <span
      className={cn(
        'block size-2.5 rounded-[3px] border border-muted-foreground/60',
        checked && 'border-primary bg-primary'
      )}
    />
  )
}

function Heading({ size, widths }: { size: string; widths: string[] }) {
  return (
    <div className="flex flex-col gap-2">
      <div className={cn('rounded-full bg-foreground/70', size)} style={{ width: '70%' }} />
      <Lines widths={widths} />
    </div>
  )
}

/**
 * Wireframe of a block type for the "/" menu's preview card. Unknown ids fall back to plain lines.
 */
export function BlockPreview({ id }: { id: string }) {
  switch (id) {
    case 'heading1':
      return <Heading size="h-3.5" widths={['90%', '60%']} />
    case 'heading2':
      return <Heading size="h-3" widths={['90%', '60%']} />
    case 'heading3':
      return <Heading size="h-2.5" widths={['90%', '60%']} />
    case 'heading4':
      return <Heading size="h-2" widths={['90%', '60%']} />
    case 'bulletList':
      return <Rows markers={['•', '•', '•']} widths={['80%', '65%', '72%']} />
    case 'orderedList':
      return <Rows markers={['1.', '2.', '3.']} widths={['80%', '65%', '72%']} />
    case 'taskList':
      return (
        <Rows
          markers={[
            <Checkbox key="a" checked />,
            <Checkbox key="b" checked={false} />,
            <Checkbox key="c" checked={false} />
          ]}
          widths={['70%', '80%', '60%']}
        />
      )
    case 'blockquote':
      return (
        <div className="border-l-2 border-foreground/70 pl-2.5">
          <Lines widths={['95%', '85%', '50%']} />
        </div>
      )
    case 'codeBlock':
      return (
        <div className="flex flex-col gap-1.5 rounded-sm bg-code p-2">
          <Line w="55%" className="bg-ink-purple/60" />
          <Line w="80%" className="ml-3 bg-ink-blue/60" />
          <Line w="40%" className="ml-3 bg-ink-red/50" />
        </div>
      )
    case 'toggle':
      return (
        <div className="flex flex-col gap-2">
          {['75%', '60%'].map((w, i) => (
            <div key={w} className="flex items-center gap-2">
              <span
                className={cn(
                  'size-0 flex-none border-y-[3.5px] border-l-[5px] border-y-transparent border-l-muted-foreground',
                  i === 0 && 'rotate-90'
                )}
              />
              <Line w={w} />
            </div>
          ))}
          <div className="pl-3.5">
            <Lines widths={['80%']} />
          </div>
        </div>
      )
    case 'callout':
      return (
        <div className="flex gap-2 rounded-sm bg-wash-gray p-2">
          <span className="text-xs leading-none">💡</span>
          <Lines widths={['90%', '70%']} />
        </div>
      )
    case 'blockMath':
      return (
        <div className="flex flex-col items-center gap-2">
          <span className="font-serif text-base text-foreground/70 italic">∑ x² = y</span>
          <Lines widths={['60%']} />
        </div>
      )
    case 'inlineMath':
      return (
        <div className="flex items-center gap-1.5">
          <Line w="30%" />
          <span className="font-serif text-xs text-foreground/70 italic">e^iπ</span>
          <Line w="35%" />
        </div>
      )
    case 'divider':
      return (
        <div className="flex flex-col gap-2.5">
          <Lines widths={['85%']} />
          <div className="h-px bg-border" />
          <Lines widths={['70%']} />
        </div>
      )
    default:
      return <Lines widths={['95%', '88%', '60%']} />
  }
}
