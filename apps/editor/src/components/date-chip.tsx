import { enUS, zhCN } from 'date-fns/locale'
import { useState, type ReactNode } from 'react'
import type { Root } from 'react-dom/client'

import { Calendar } from '@/components/ui/calendar'
import { Input } from '@/components/ui/input'
import { Separator } from '@/components/ui/separator'
import { Switch } from '@/components/ui/switch'

import i18n, { t } from '../core/i18n'
import {
  BellSimpleIcon,
  CalendarBlankIcon,
  CaretLeftIcon,
  CaretRightIcon,
  CheckCircleIcon,
  CheckIcon,
  TrashIcon
} from '../generated/icons'
import {
  DAY_TIME,
  REMIND_DAY,
  REMIND_TIMED,
  dateLabel,
  isOverdue,
  isoDate,
  localMoment,
  parseDateQuery,
  remindLabel,
  type DateMentionAttrs
} from '../lib/dates'
import { isImeKey } from '../lib/ime'
import type { FloatingAnchor, FloatingLayer } from './floating'
import { IconProvider } from './icons'
import { MenuRow, MenuTitle } from './menu-row'

/** How a chip looks: a plain date, a reminder, one that has rung without Mark done, or one marked done. */
export type DateChipState = 'date' | 'remind' | 'overdue' | 'done'

export function dateChipState(attrs: DateMentionAttrs, now = new Date()): DateChipState {
  if (attrs.remind === null) return 'date'
  if (attrs.done) return 'done'
  return isOverdue(attrs, now) ? 'overdue' : 'remind'
}

function ChipIcon({ state }: { state: DateChipState }) {
  if (state === 'done') return <CheckCircleIcon size={15} aria-hidden />
  if (state === 'date') return <CalendarBlankIcon size={15} aria-hidden />
  return <BellSimpleIcon size={15} aria-hidden />
}

/** A chip's inside (the node view's own `<span>` carries its state and colour): its icon and words. */
export function renderDateChip(root: Root, attrs: DateMentionAttrs, now = new Date()): void {
  root.render(
    <IconProvider>
      <ChipIcon state={dateChipState(attrs, now)} />
      <span className="hk-date-label">{dateLabel(attrs, now)}</span>
    </IconProvider>
  )
}

/** The "@" menu's icon for a date row or a reminder row. */
export function dateMenuIcon(remind: boolean): ReactNode {
  return remind ? (
    <BellSimpleIcon size={18} aria-hidden />
  ) : (
    <CalendarBlankIcon size={18} aria-hidden />
  )
}

type PopoverProps = {
  attrs: DateMentionAttrs
  onChange: (patch: Partial<DateMentionAttrs>) => void
  onRemove: () => void
}

/** The chip's popover: typed words or the calendar for the day, an optional time, the reminder, Mark done, Remove. */
export function DatePopover({ attrs, onChange, onRemove }: PopoverProps) {
  const [typed, setTyped] = useState('')
  const [choosing, setChoosing] = useState(false)
  const day = localMoment(attrs.date) ?? undefined
  const timed = attrs.time !== null
  const locale = i18n.language === 'zh-Hans' ? zhCN : enUS

  // A new day or time moves the reminder with it: a snooze is forgotten.
  const move = (patch: Partial<DateMentionAttrs>) => onChange({ ...patch, snoozed: null })

  if (choosing) {
    const options = [null, ...(timed ? REMIND_TIMED : REMIND_DAY)]
    return (
      <div role="group" aria-label={t('date.remind.label')} data-testid="date-remind-list">
        <MenuRow onClick={() => setChoosing(false)} aria-label={t('date.back')}>
          <CaretLeftIcon size={14} aria-hidden />
          <span className="flex-1 truncate">{t('date.remind.label')}</span>
        </MenuRow>
        {options.map((minutes) => (
          <MenuRow
            key={String(minutes)}
            role="menuitemradio"
            aria-checked={attrs.remind === minutes}
            data-testid={`date-remind-${minutes ?? 'none'}`}
            onClick={() => {
              onChange({ remind: minutes, done: false, snoozed: null })
              setChoosing(false)
            }}
          >
            <span className="flex-1 truncate">{remindLabel(minutes, timed)}</span>
            {attrs.remind === minutes && <CheckIcon size={14} aria-hidden />}
          </MenuRow>
        ))}
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-1" data-testid="date-popover">
      <Input
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- the popover opens to change the date
        autoFocus
        className="h-8"
        aria-label={t('date.field')}
        placeholder={t('date.placeholder')}
        value={typed}
        onChange={(e) => setTyped(e.target.value)}
        onKeyDown={(e) => {
          if (isImeKey(e.nativeEvent) || e.key !== 'Enter') return
          e.preventDefault()
          const parsed = parseDateQuery(typed)
          if (!parsed) return
          move({ date: parsed.date, time: parsed.time ?? attrs.time })
          setTyped('')
        }}
      />
      <Calendar
        mode="single"
        required
        locale={locale}
        selected={day}
        defaultMonth={day}
        className="self-center bg-transparent p-1"
        onSelect={(next: Date | undefined) => next && move({ date: isoDate(next) })}
      />
      <Separator />
      {/* Not a <label>: a click would toggle Base UI's switch twice, itself and through its hidden input. */}
      <div className="flex h-8 items-center justify-between gap-2 px-2 text-sm">
        <span>{t('date.includeTime')}</span>
        <Switch
          checked={timed}
          aria-label={t('date.includeTime')}
          data-testid="date-include-time"
          onCheckedChange={(on) =>
            // A reminder keeps meaning "at the time": at 9:00 on the day either way.
            move({ time: on ? DAY_TIME : null, remind: attrs.remind === null ? null : 0 })
          }
        />
      </div>
      {timed && (
        <Input
          type="time"
          className="h-8"
          aria-label={t('date.time')}
          data-testid="date-time"
          value={attrs.time ?? ''}
          onChange={(e) => /^\d{2}:\d{2}$/u.test(e.target.value) && move({ time: e.target.value })}
        />
      )}
      <MenuRow onClick={() => setChoosing(true)} data-testid="date-remind">
        <span className="flex-1 truncate">{t('date.remind.label')}</span>
        <span className="truncate text-muted-foreground">{remindLabel(attrs.remind, timed)}</span>
        <CaretRightIcon size={14} className="text-muted-foreground" aria-hidden />
      </MenuRow>
      {attrs.remind !== null && (
        <MenuRow
          data-testid="date-done"
          onClick={() => onChange({ done: !attrs.done, snoozed: null })}
        >
          <CheckCircleIcon size={16} aria-hidden />
          <span className="flex-1 truncate">
            {attrs.done ? t('date.markNotDone') : t('date.markDone')}
          </span>
        </MenuRow>
      )}
      <Separator />
      <MenuRow data-testid="date-remove" onClick={onRemove}>
        <TrashIcon size={16} aria-hidden />
        <span className="flex-1 truncate">{t('date.remove')}</span>
      </MenuRow>
    </div>
  )
}

export function renderDatePopover(
  layer: FloatingLayer,
  props: PopoverProps,
  anchor: FloatingAnchor
): void {
  layer.render(
    <IconProvider>
      <MenuTitle>{t('date.title')}</MenuTitle>
      <DatePopover {...props} />
    </IconProvider>,
    anchor
  )
}
