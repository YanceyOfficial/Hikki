/**
 * Exactly one of the two window-corner headers (TitleBar, SidebarLeft's own
 * header) should reserve space for the macOS traffic lights at any given
 * time: whichever one currently sits at the window's top-left corner.
 */
export function titleBarNeedsInset(
  trafficLight: boolean,
  isMobile: boolean,
  sidebarState: 'expanded' | 'collapsed'
): boolean {
  return trafficLight && (isMobile || sidebarState === 'collapsed')
}

export function sidebarHeaderNeedsInset(
  trafficLight: boolean,
  isMobile: boolean,
  sidebarState: 'expanded' | 'collapsed'
): boolean {
  return trafficLight && !isMobile && sidebarState === 'expanded'
}
