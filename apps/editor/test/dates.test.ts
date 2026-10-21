import { afterEach, describe, expect, it } from 'vitest'

import { setLocale } from '../src/core/i18n'
import {
  dateLabel,
  datePrefix,
  dateText,
  fireMoment,
  isOverdue,
  parseDateQuery,
  type DateMentionAttrs
} from '../src/lib/dates'

// Wednesday, October 21, 2026, at noon.
const NOW = new Date(2026, 9, 21, 12, 0)
const parse = (text: string) => parseDateQuery(text, NOW)
const day = (date: string, time: string | null = null) => ({ date, time })
const chip = (patch: Partial<DateMentionAttrs>): DateMentionAttrs => ({
  id: 'm',
  date: '2026-10-22',
  time: null,
  remind: null,
  done: false,
  snoozed: null,
  ...patch
})

afterEach(() => {
  setLocale('en')
})

describe('what "@" reads as a date', () => {
  it('understands English words, weekdays, months and numbers', () => {
    expect(parse('today')).toEqual(day('2026-10-21'))
    expect(parse('tod')).toEqual(day('2026-10-21'))
    expect(parse('tom')).toEqual(day('2026-10-22'))
    expect(parse('tmrw')).toEqual(day('2026-10-22'))
    expect(parse('yesterday')).toEqual(day('2026-10-20'))
    // A weekday is the next one on or after today; "next" is the one in next week (Monday-first weeks).
    expect(parse('fri')).toEqual(day('2026-10-23'))
    expect(parse('wednesday')).toEqual(day('2026-10-21'))
    expect(parse('mon')).toEqual(day('2026-10-26'))
    expect(parse('next fri')).toEqual(day('2026-10-30'))
    expect(parse('next week')).toEqual(day('2026-10-26'))
    expect(parse('next month')).toEqual(day('2026-11-01'))
    expect(parse('in 3 days')).toEqual(day('2026-10-24'))
    expect(parse('in 2 weeks')).toEqual(day('2026-11-04'))
    expect(parse('Oct 30')).toEqual(day('2026-10-30'))
    expect(parse('30 october 2027')).toEqual(day('2027-10-30'))
    expect(parse('10/30')).toEqual(day('2026-10-30'))
    expect(parse('2026-12-01')).toEqual(day('2026-12-01'))
    // A day of the year long gone means next year's.
    expect(parse('jan 5')).toEqual(day('2027-01-05'))
    expect(parse('oct 1')).toEqual(day('2026-10-01'))
  })

  it('takes a time with the day, or alone for today', () => {
    expect(parse('tomorrow 9am')).toEqual(day('2026-10-22', '09:00'))
    expect(parse('tomorrow at 3:30pm')).toEqual(day('2026-10-22', '15:30'))
    expect(parse('fri 15:00')).toEqual(day('2026-10-23', '15:00'))
    expect(parse('12am tomorrow')).toEqual(day('2026-10-22', '00:00'))
    expect(parse('at 9')).toEqual(day('2026-10-21', '09:00'))
    expect(parse('noon')).toEqual(day('2026-10-21', '12:00'))
  })

  it('understands Chinese and Japanese', () => {
    expect(parse('明天')).toEqual(day('2026-10-22'))
    expect(parse('后天')).toEqual(day('2026-10-23'))
    expect(parse('周五')).toEqual(day('2026-10-23'))
    expect(parse('下周五')).toEqual(day('2026-10-30'))
    expect(parse('星期天')).toEqual(day('2026-10-25'))
    expect(parse('10月30日')).toEqual(day('2026-10-30'))
    expect(parse('2027年1月2号')).toEqual(day('2027-01-02'))
    expect(parse('3天后')).toEqual(day('2026-10-24'))
    expect(parse('明天下午3点半')).toEqual(day('2026-10-22', '15:30'))
    expect(parse('明天9:30')).toEqual(day('2026-10-22', '09:30'))
    expect(parse('明日')).toEqual(day('2026-10-22'))
    expect(parse('あさって')).toEqual(day('2026-10-23'))
    expect(parse('金曜日')).toEqual(day('2026-10-23'))
    expect(parse('来週の金曜')).toEqual(day('2026-10-30'))
    expect(parse('明日 午後3時')).toEqual(day('2026-10-22', '15:00'))
  })

  it('reads nothing else as a date', () => {
    for (const text of [
      '',
      'roadmap',
      'meeting',
      'feb 30',
      '13/40',
      'tomorrow 25:00',
      '13pm',
      'to'
    ])
      expect(parse(text), text).toBeNull()
  })

  it('keeps a space only while the words can still become a date', () => {
    expect(datePrefix('next', NOW)).toBe(true)
    expect(datePrefix('next f', NOW)).toBe(true)
    expect(datePrefix('oct', NOW)).toBe(true)
    expect(datePrefix('tomorrow at', NOW)).toBe(true)
    expect(datePrefix('tomorrow 9', NOW)).toBe(true)
    expect(datePrefix('in 3 d', NOW)).toBe(true)
    expect(datePrefix('Trip to', NOW)).toBe(false)
    expect(datePrefix('tomorrow and then', NOW)).toBe(false)
  })
})

describe('how a chip reads', () => {
  it('relative to today, then as a date, with its time', () => {
    expect(dateLabel(day('2026-10-21'), NOW)).toBe('Today')
    expect(dateLabel(day('2026-10-22', '09:00'), NOW)).toBe('Tomorrow 9:00 AM')
    expect(dateLabel(day('2026-10-20'), NOW)).toBe('Yesterday')
    expect(dateLabel(day('2026-10-23'), NOW)).toBe('Friday')
    expect(dateLabel(day('2026-10-30'), NOW)).toBe('Oct 30')
    expect(dateLabel(day('2027-01-02'), NOW)).toBe('Jan 2, 2027')
    setLocale('zh-Hans')
    expect(dateLabel(day('2026-10-22'), NOW)).toBe('明天')
    expect(dateLabel(day('2026-10-30'), NOW)).toBe('10月30日')
  })

  it('as text for search and Markdown, the same as the native side', () => {
    expect(dateText(day('2026-10-22'))).toBe('2026-10-22')
    expect(dateText(day('2026-10-22', '09:30'))).toBe('2026-10-22 09:30')
  })
})

describe('when a reminder rings', () => {
  it('before the time, at 9:00 on a whole day, or at a snooze', () => {
    expect(fireMoment(chip({}))).toBeNull()
    expect(fireMoment(chip({ remind: 0 }))).toEqual(new Date(2026, 9, 22, 9, 0))
    expect(fireMoment(chip({ remind: 1440 }))).toEqual(new Date(2026, 9, 21, 9, 0))
    expect(fireMoment(chip({ time: '15:00', remind: 60 }))).toEqual(new Date(2026, 9, 22, 14, 0))
    expect(fireMoment(chip({ remind: 0, snoozed: '2026-10-22T10:00' }))).toEqual(
      new Date(2026, 9, 22, 10, 0)
    )
  })

  it('is overdue once rung, until marked done', () => {
    const rung = chip({ date: '2026-10-21', time: '09:00', remind: 0 })
    expect(isOverdue(rung, NOW)).toBe(true)
    expect(isOverdue({ ...rung, done: true }, NOW)).toBe(false)
    expect(isOverdue(chip({ remind: 0 }), NOW)).toBe(false)
    expect(isOverdue(chip({ date: '2026-10-01' }), NOW)).toBe(false)
  })
})
