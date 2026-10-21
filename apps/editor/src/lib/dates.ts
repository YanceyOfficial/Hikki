import i18n, { t } from '../core/i18n'

/**
 * Dates in a page (`dateMention`): what "@" understands as a date, how a chip reads relative to today, and when its
 * reminder rings. Times are wall-clock ("09:00" is 9:00 wherever the reader is), so everything here works on local
 * calendar days, never on instants that a time zone would move. The native side reads the same attributes
 * (`HikkiCore/Sources/Store/DateMentions.swift`) and must agree on `fireMoment`.
 */

/** A day ("2026-10-22") and, optionally, a time on it ("09:00"). */
export type DateValue = { date: string; time: string | null }

/** A chip's stored attributes. */
export type DateMentionAttrs = DateValue & {
  /** Names the chip, so a reminder's Mark done / Snooze (native) finds it again. */
  id: string | null
  /** Minutes before the date (at `DAY_TIME` for a date without a time) that the reminder rings; null: no reminder. */
  remind: number | null
  /** Marked done: the reminder no longer rings or shows red. */
  done: boolean
  /** A snoozed reminder rings at this wall-clock time instead ("2026-10-22T10:00"). */
  snoozed: string | null
}

/** When a reminder on a date without a time rings. */
export const DAY_TIME = '09:00'

/** Reminder choices: for a date with a time, and for a whole day (rung at `DAY_TIME`). Minutes before. */
export const REMIND_TIMED = [0, 5, 60, 1440] as const
export const REMIND_DAY = [0, 1440, 10080] as const

const pad = (n: number) => String(n).padStart(2, '0')

/** A local calendar day as "YYYY-MM-DD". */
export function isoDate(day: Date): string {
  return `${day.getFullYear()}-${pad(day.getMonth() + 1)}-${pad(day.getDate())}`
}

/** "YYYY-MM-DD" (and "HH:mm") as a local wall-clock moment; null for anything else. */
export function localMoment(date: string, time: string | null = null): Date | null {
  const d = /^(\d{4})-(\d{2})-(\d{2})$/u.exec(date)
  const tm = time === null ? ['', '0', '0'] : /^(\d{2}):(\d{2})$/u.exec(time)
  if (!d || !tm) return null
  return validDay(Number(d[1]), Number(d[2]), Number(d[3]), Number(tm[1]), Number(tm[2]))
}

function validDay(y: number, m: number, d: number, h = 0, min = 0): Date | null {
  if (h > 23 || min > 59) return null
  const day = new Date(y, m - 1, d, h, min)
  return day.getFullYear() === y && day.getMonth() === m - 1 && day.getDate() === d ? day : null
}

function startOfDay(day: Date): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate())
}

function addDays(day: Date, n: number): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate() + n)
}

/** Whole days from `from` to `to` (calendar days, so a DST change doesn't skew it). */
function daysBetween(from: Date, to: Date): number {
  const a = Date.UTC(from.getFullYear(), from.getMonth(), from.getDate())
  const b = Date.UTC(to.getFullYear(), to.getMonth(), to.getDate())
  return Math.round((b - a) / 86_400_000)
}

/** Monday-first weekday: 0 Monday … 6 Sunday. */
const mondayIndex = (day: Date) => (day.getDay() + 6) % 7

/** `weekday` (0 Sunday … 6 Saturday) in the week `weeks` after this one (Monday-first); 0: this week's. */
function weekdayInWeek(today: Date, weekday: number, weeks: number): Date {
  const monday = addDays(today, -mondayIndex(today) + weeks * 7)
  return addDays(monday, (weekday + 6) % 7)
}

/** The next `weekday` (0 Sunday … 6 Saturday) on or after today. */
function upcomingWeekday(today: Date, weekday: number): Date {
  return addDays(today, (weekday - today.getDay() + 7) % 7)
}

const EN_WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']
const EN_MONTHS = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december'
]
const ZH_WEEKDAYS: Record<string, number> = {
  日: 0,
  天: 0,
  一: 1,
  二: 2,
  三: 3,
  四: 4,
  五: 5,
  六: 6
}
const JA_WEEKDAYS: Record<string, number> = { 日: 0, 月: 1, 火: 2, 水: 3, 木: 4, 金: 5, 土: 6 }

/** An English word typed far enough: a prefix of `word` at least `min` letters long. */
const typed = (text: string, word: string, min = 3) => text.length >= min && word.startsWith(text)

const enWeekday = (text: string) => EN_WEEKDAYS.findIndex((w) => typed(text, w))
const enMonth = (text: string) => EN_MONTHS.findIndex((m) => typed(text.replace(/\.$/u, ''), m))

/** A month and day without a year: this year's, unless that was more than two months ago (then next year's). */
function nearYear(today: Date, month: number, day: number): Date | null {
  const date = validDay(today.getFullYear(), month, day)
  if (date && daysBetween(today, date) < -60) return validDay(today.getFullYear() + 1, month, day)
  return date ?? validDay(today.getFullYear() + 1, month, day)
}

function fullYear(text: string | undefined): number | null {
  if (!text) return null
  const year = Number(text)
  return text.length <= 2 ? 2000 + year : year
}

/** A day named in English, Chinese or Japanese; null when the words aren't a day. */
function parseDay(text: string, today: Date): Date | null {
  let m: RegExpExecArray | null
  // 2026-10-30, 2026/10/30
  if ((m = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/u.exec(text)))
    return validDay(Number(m[1]), Number(m[2]), Number(m[3]))
  // 10/30, 10/30/2026
  if ((m = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?$/u.exec(text))) {
    const year = fullYear(m[3])
    return year === null
      ? nearYear(today, Number(m[1]), Number(m[2]))
      : validDay(year, Number(m[1]), Number(m[2]))
  }
  // 10月30日, 2026年10月30号
  if ((m = /^(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号號]?$/u.exec(text))) {
    return m[1]
      ? validDay(Number(m[1]), Number(m[2]), Number(m[3]))
      : nearYear(today, Number(m[2]), Number(m[3]))
  }
  // oct 30, october 30th, oct 30 2026, oct 30, 2026
  if ((m = /^([a-z]{3,}\.?)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?$/u.exec(text))) {
    const month = enMonth(m[1])
    if (month < 0) return null
    return m[3]
      ? validDay(Number(m[3]), month + 1, Number(m[2]))
      : nearYear(today, month + 1, Number(m[2]))
  }
  // 30 oct, 30th october 2026
  if ((m = /^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,}\.?)(?:,?\s+(\d{4}))?$/u.exec(text))) {
    const month = enMonth(m[2])
    if (month < 0) return null
    return m[3]
      ? validDay(Number(m[3]), month + 1, Number(m[1]))
      : nearYear(today, month + 1, Number(m[1]))
  }
  // in 3 days, in 2 weeks, in 1 month
  if ((m = /^in\s+(\d{1,3})\s+(day|week|month)s?$/u.exec(text))) {
    const n = Number(m[1])
    if (m[2] === 'month')
      return new Date(today.getFullYear(), today.getMonth() + n, today.getDate())
    return addDays(today, m[2] === 'week' ? n * 7 : n)
  }
  // 3天后, 3日後
  if ((m = /^(\d{1,3})\s*[天日]\s*[后後]$/u.exec(text))) return addDays(today, Number(m[1]))

  const words: Record<string, number> = {
    今天: 0,
    今日: 0,
    明天: 1,
    明日: 1,
    あした: 1,
    あす: 1,
    后天: 2,
    後天: 2,
    明後日: 2,
    あさって: 2,
    大后天: 3,
    大後天: 3,
    昨天: -1,
    昨日: -1,
    きのう: -1,
    前天: -2,
    一昨日: -2,
    おととい: -2
  }
  if (text in words) return addDays(today, words[text])
  if (typed(text, 'today') || text === 'now') return today
  if (typed(text, 'tomorrow') || text === 'tmr' || text === 'tmrw') return addDays(today, 1)
  if (typed(text, 'yesterday')) return addDays(today, -1)

  // next week → next Monday; next month → its first day (下周, 来週, 下个月, 来月)
  if (
    text === 'next week' ||
    text === '下周' ||
    text === '下週' ||
    text === '下星期' ||
    text === '来週'
  )
    return weekdayInWeek(today, 1, 1)
  if (text === 'next month' || text === '下个月' || text === '下個月' || text === '来月')
    return new Date(today.getFullYear(), today.getMonth() + 1, 1)

  // fri, this friday, next fri, on monday
  if ((m = /^(?:(on|this|next|last)\s+)?([a-z]{3,})$/u.exec(text))) {
    const weekday = enWeekday(m[2])
    if (weekday < 0) return null
    if (m[1] === 'next') return weekdayInWeek(today, weekday, 1)
    if (m[1] === 'last') return weekdayInWeek(today, weekday, -1)
    return upcomingWeekday(today, weekday)
  }
  // 周五, 星期五, 下周五, 这周五, 上周五, 礼拜天
  if (
    (m = /^(下|这|這|本|上)?\s*(?:个|個)?\s*(?:周|週|星期|礼拜|禮拜)([一二三四五六日天])$/u.exec(
      text
    ))
  ) {
    const weekday = ZH_WEEKDAYS[m[2]]
    if (m[1] === '下') return weekdayInWeek(today, weekday, 1)
    if (m[1] === '上') return weekdayInWeek(today, weekday, -1)
    if (m[1]) return weekdayInWeek(today, weekday, 0)
    return upcomingWeekday(today, weekday)
  }
  // 金曜, 金曜日, 来週の金曜, 今週金曜日, 先週の月曜
  if ((m = /^(来週|今週|先週)?\s*の?\s*([月火水木金土日])曜(?:日)?$/u.exec(text))) {
    const weekday = JA_WEEKDAYS[m[2]]
    if (m[1] === '来週') return weekdayInWeek(today, weekday, 1)
    if (m[1] === '先週') return weekdayInWeek(today, weekday, -1)
    if (m[1]) return weekdayInWeek(today, weekday, 0)
    return upcomingWeekday(today, weekday)
  }
  return null
}

const AFTERNOON = new Set(['下午', '傍晚', '晚上', '午後', '夜'])

/** A time in the words ("9am", "at 9:30", "15:00", "下午3点半", "午後3時"), taken out of them. */
function takeTime(text: string): { time: string; rest: string } | null {
  const done = (h: number, min: number, match: RegExpExecArray) => {
    if (h > 23 || min > 59) return null
    const rest = (text.slice(0, match.index) + ' ' + text.slice(match.index + match[0].length))
      .replaceAll(/\s+/gu, ' ')
      .trim()
    return { time: `${pad(h)}:${pad(min)}`, rest }
  }
  let m: RegExpExecArray | null
  // 9am, 9:30 pm, at 9pm
  if ((m = /(?:^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)(?=$|\s)/u.exec(text))) {
    let h = Number(m[1])
    if (h < 1 || h > 12) return null
    if (m[3].startsWith('p') && h < 12) h += 12
    if (m[3].startsWith('a') && h === 12) h = 0
    return done(h, Number(m[2] ?? 0), m)
  }
  // 下午3点半, 9点30分, 午後3時, 上午9:30
  if (
    (m =
      /(上午|早上|早晨|凌晨|中午|下午|傍晚|晚上|午前|午後|朝|夜)?\s*(\d{1,2})\s*(?:[:：]\s*(\d{2})|[点點时時]\s*(?:(\d{1,2})\s*分?|(半))?)/u.exec(
        text
      )) &&
    (m[1] || !m[3])
  ) {
    let h = Number(m[2])
    if (m[1] && AFTERNOON.has(m[1]) && h < 12) h += 12
    if (m[1] === '中午' && h < 11) h += 12
    const min = m[5] ? 30 : Number(m[3] ?? m[4] ?? 0)
    return done(h, min, m)
  }
  // 15:00, at 9:30, 明天9:30
  if ((m = /(?:^|\s|(?<=\D))(?:at\s+)?(\d{1,2}):(\d{2})(?=$|\s|\D)/u.exec(text)))
    return done(Number(m[1]), Number(m[2]), m)
  // at 9
  if ((m = /(?:^|\s)at\s+(\d{1,2})$/u.exec(text))) return done(Number(m[1]), 0, m)
  if ((m = /(?:^|\s)(?:at\s+)?noon$/u.exec(text))) return done(12, 0, m)
  return null
}

/**
 * What "@" typed reads as: a day, with a time when one was given ("tomorrow 9am", "fri", "10/30", "明天下午3点",
 * "来週の金曜"). A time alone is today. Null when the words aren't a date.
 */
export function parseDateQuery(input: string, now = new Date()): DateValue | null {
  let text = input.trim().toLowerCase().replaceAll(/\s+/gu, ' ')
  if (!text) return null
  const today = startOfDay(now)
  let time: string | null = null
  const taken = takeTime(text)
  if (taken) {
    time = taken.time
    text = taken.rest.replaceAll(/^(?:on|at)\s+|\s+(?:on|at)$/gu, '').trim()
  }
  const day = text ? parseDay(text, today) : time ? today : null
  return day ? { date: isoDate(day), time } : null
}

/**
 * Whether "@" may keep a space in what's typed: while the words still read as a date, or as one with a word half
 * typed ("next f", "tomorrow at 9", "oct"), so "@next friday 3pm" stays one suggestion. Anything else ends at the
 * space, as page mentions always have.
 */
export function datePrefix(query: string, now = new Date()): boolean {
  const text = query.trim()
  if (!text) return false
  if (parseDateQuery(text, now)) return true
  const words = text.split(/\s+/u)
  if (words.length < 2)
    return /^(next|this|last|on|in)$/iu.test(text) || enMonth(text.toLowerCase()) >= 0
  const head = words.slice(0, -1).join(' ')
  return (
    parseDateQuery(head, now) !== null ||
    /^(next|this|last|on|in(\s+\d+)?)$/iu.test(head) ||
    /^(at|\d{1,2}(:\d{0,2})?)$/iu.test(words.at(-1) ?? '')
  )
}

/** The chip's words: Today / Tomorrow / Yesterday, a weekday within the week ahead, else the date (with its year when
 * not this one); then the time. In the app's language. */
export function dateLabel(value: DateValue, now = new Date()): string {
  const day = localMoment(value.date)
  if (!day) return value.date
  const locale = i18n.language || 'en'
  const diff = daysBetween(now, day)
  let words: string
  if (diff === 0) words = t('date.today')
  else if (diff === 1) words = t('date.tomorrow')
  else if (diff === -1) words = t('date.yesterday')
  else if (diff > 1 && diff < 7) words = day.toLocaleDateString(locale, { weekday: 'long' })
  else
    words = day.toLocaleDateString(locale, {
      month: 'short',
      day: 'numeric',
      ...(day.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' })
    })
  const at = value.time === null ? null : localMoment(value.date, value.time)
  return at
    ? `${words} ${at.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' })}`
    : words
}

/** The date in full, for a menu hint and copied text ("Thu, Oct 22, 2026"). */
export function dateLong(value: DateValue): string {
  const at = localMoment(value.date, value.time)
  if (!at) return value.date
  const locale = i18n.language || 'en'
  const day = at.toLocaleDateString(locale, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  })
  return value.time === null
    ? day
    : `${day} ${at.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' })}`
}

/** The chip as plain text for search, word counts and Markdown — the same on both sides: "2026-10-22 09:00". */
export function dateText(value: DateValue): string {
  return value.time === null ? value.date : `${value.date} ${value.time}`
}

/** When the reminder rings: a snooze's time, else the date (at `DAY_TIME` without a time) less `remind` minutes. */
export function fireMoment(attrs: DateMentionAttrs): Date | null {
  if (attrs.remind === null) return null
  if (attrs.snoozed) {
    const [date, time] = attrs.snoozed.split('T')
    return localMoment(date, time ?? null)
  }
  const event = localMoment(attrs.date, attrs.time ?? DAY_TIME)
  return event && new Date(event.getTime() - attrs.remind * 60_000)
}

/** A reminder that has rung and isn't marked done. */
export function isOverdue(attrs: DateMentionAttrs, now = new Date()): boolean {
  const fire = fireMoment(attrs)
  return !!fire && !attrs.done && fire.getTime() <= now.getTime()
}

/** A reminder choice in words ("At time of event", "1 day before (9:00)"). */
export function remindLabel(minutes: number | null, timed: boolean): string {
  if (minutes === null) return t('date.remind.none')
  if (!timed) {
    if (minutes === 0) return t('date.remind.onDay', { time: DAY_TIME })
    if (minutes === 1440) return t('date.remind.dayBefore', { time: DAY_TIME })
    if (minutes === 10080) return t('date.remind.weekBefore', { time: DAY_TIME })
  }
  if (minutes === 0) return t('date.remind.atTime')
  if (minutes === 5) return t('date.remind.minutes5')
  if (minutes === 60) return t('date.remind.hour1')
  if (minutes === 1440) return t('date.remind.day1')
  return t('date.remind.minutes', { count: minutes })
}
