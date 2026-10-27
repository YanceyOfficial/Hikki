/**
 * Whether a key event is an input method's and must not act on the field (the Enter that commits a pinyin candidate
 * is not the Enter that sends). `isComposing` alone misses WebKit's commit: Safari and WKWebView fire `compositionend`
 * first and then the committing Enter's keydown with `isComposing` false — but with `keyCode` 229, which every
 * browser gives a key the input method handled (ISSUE-258: Edit with AI sent the half-typed pinyin as the request).
 */
export function isImeKey(event: { isComposing: boolean; keyCode: number }): boolean {
  return event.isComposing || event.keyCode === 229
}
