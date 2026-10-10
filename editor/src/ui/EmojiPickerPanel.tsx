import { EmojiPicker } from 'frimousse'

type Props = {
  onSelect: (emoji: string) => void
  onRemove?: () => void
  onRandom?: () => void
  locale?: 'en' | 'zh'
}

/** Offline emoji picker (data bundled under ./emojibase). Reusable for page icons, callouts, reactions. */
export function EmojiPickerPanel({ onSelect, onRemove, onRandom, locale = preferredLocale() }: Props) {
  return (
    <div className="hk-emoji-panel">
      <EmojiPicker.Root
        className="hk-emoji-root"
        locale={locale}
        columns={9}
        emojibaseUrl={new URL('./emojibase', document.baseURI).href.replace(/\/$/, '')}
        onEmojiSelect={({ emoji }) => onSelect(emoji)}
      >
        <div className="hk-emoji-toolbar">
          <EmojiPicker.Search className="hk-input" placeholder={locale === 'zh' ? '搜索表情…' : 'Search emoji…'} autoFocus={!isTouch()} />
          {onRandom && (
            <button type="button" className="hk-button" onClick={onRandom} aria-label="Random emoji" title="Random">🎲</button>
          )}
          {onRemove && (
            <button type="button" className="hk-button" onClick={onRemove}>{locale === 'zh' ? '移除' : 'Remove'}</button>
          )}
        </div>
        <EmojiPicker.Viewport className="hk-emoji-viewport">
          <EmojiPicker.Loading className="hk-emoji-status">…</EmojiPicker.Loading>
          <EmojiPicker.Empty className="hk-emoji-status">{locale === 'zh' ? '没有找到' : 'No emoji found'}</EmojiPicker.Empty>
          <EmojiPicker.List
            className="hk-emoji-list"
            components={{
              CategoryHeader: ({ category, ...props }) => <div className="hk-emoji-category" {...props}>{category.label}</div>,
              Emoji: ({ emoji, ...props }) => <button className="hk-emoji" {...props}>{emoji.emoji}</button>,
            }}
          />
        </EmojiPicker.Viewport>
      </EmojiPicker.Root>
    </div>
  )
}

function preferredLocale(): 'en' | 'zh' {
  return navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en'
}

function isTouch(): boolean {
  return matchMedia?.('(pointer: coarse)').matches ?? false
}
