import { ThemeProvider as NextThemesProvider, useTheme } from 'next-themes'
import type { ComponentProps } from 'react'
import { useEffect } from 'react'

/**
 * Bridges next-themes' resolved theme back into the native macOS window
 * chrome (traffic lights, menu bar rendering) so it matches the in-app
 * theme, mirroring the exodus project's Electron nativeTheme bridge.
 */
function NativeThemeBridge() {
  const { resolvedTheme } = useTheme()

  useEffect(() => {
    if (typeof window === 'undefined' || !('__TAURI_INTERNALS__' in window))
      return
    if (resolvedTheme !== 'light' && resolvedTheme !== 'dark') return
    let cancelled = false
    import('@tauri-apps/api/window').then(({ getCurrentWindow }) => {
      if (cancelled) return
      getCurrentWindow()
        .setTheme(resolvedTheme)
        .catch(() => {})
    })
    return () => {
      cancelled = true
    }
  }, [resolvedTheme])

  return null
}

export function ThemeProvider({
  children,
  ...props
}: ComponentProps<typeof NextThemesProvider>) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      storageKey="hikki-theme"
      disableTransitionOnChange
      {...props}
    >
      <NativeThemeBridge />
      {children}
    </NextThemesProvider>
  )
}
