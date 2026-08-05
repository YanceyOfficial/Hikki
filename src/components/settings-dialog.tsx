import { useAtom } from 'jotai'
import {
  Info,
  ScrollText,
  Settings2,
  Sparkles,
  type LucideIcon
} from 'lucide-react'
import type { CSSProperties } from 'react'

import { AboutSection } from '#components/settings/about-section'
import { AiSection } from '#components/settings/ai-section'
import { GeneralSection } from '#components/settings/general-section'
import { LogsSection } from '#components/settings/logs-section'
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbList,
  BreadcrumbPage
} from '#components/ui/breadcrumb'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle
} from '#components/ui/dialog'
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider
} from '#components/ui/sidebar'
import {
  settingsDialogOpenAtom,
  settingsDialogSectionAtom,
  type SettingsSection
} from '#lib/store'

const SECTIONS: { id: SettingsSection; label: string; icon: LucideIcon }[] = [
  { id: 'general', label: 'General', icon: Settings2 },
  { id: 'ai', label: 'AI', icon: Sparkles },
  { id: 'logs', label: 'Logs', icon: ScrollText },
  { id: 'about', label: 'About & Updates', icon: Info }
]

export function SettingsDialog() {
  const [open, setOpen] = useAtom(settingsDialogOpenAtom)
  const [section, setSection] = useAtom(settingsDialogSectionAtom)
  const activeLabel = SECTIONS.find((s) => s.id === section)?.label

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent
        data-testid="settings-dialog"
        className="flex h-125 w-175 max-w-none gap-0 overflow-hidden p-0 sm:max-w-none"
      >
        <DialogTitle className="sr-only">Settings</DialogTitle>
        <DialogDescription className="sr-only">
          Customize your Hikki settings.
        </DialogDescription>
        {/* `min-h-0` overrides SidebarProvider's own default `min-h-svh` -
            meant for a full-page app-shell layout, which would otherwise
            force this dialog-embedded instance to want viewport height.
            `--sidebar-width` is narrowed from the 16rem default (sized for
            the app's own page-level sidebar) - at 16rem, the AI section's
            content (API key input + Save + Test buttons per row) had no
            room left in this dialog's 700px width and got clipped, confirmed
            live before landing on 11rem. */}
        <SidebarProvider
          className="min-h-0 items-start"
          style={{ '--sidebar-width': '11rem' } as CSSProperties}
        >
          <Sidebar collapsible="none" className="hidden md:flex">
            <SidebarContent>
              <SidebarGroup>
                <SidebarGroupContent>
                  <SidebarMenu>
                    {SECTIONS.map((s) => (
                      <SidebarMenuItem key={s.id}>
                        <SidebarMenuButton
                          type="button"
                          data-testid={`settings-nav-${s.id}`}
                          isActive={section === s.id}
                          onClick={() => setSection(s.id)}
                        >
                          <s.icon />
                          <span>{s.label}</span>
                        </SidebarMenuButton>
                      </SidebarMenuItem>
                    ))}
                  </SidebarMenu>
                </SidebarGroupContent>
              </SidebarGroup>
            </SidebarContent>
          </Sidebar>
          <main className="flex h-125 min-w-0 flex-1 flex-col overflow-hidden">
            <header className="flex h-12 shrink-0 items-center border-b px-4">
              <Breadcrumb>
                <BreadcrumbList>
                  <BreadcrumbItem>
                    <BreadcrumbPage>{activeLabel}</BreadcrumbPage>
                  </BreadcrumbItem>
                </BreadcrumbList>
              </Breadcrumb>
            </header>
            <div className="min-h-0 flex-1 overflow-y-auto p-6">
              {section === 'general' && (
                <div data-testid="settings-section-general">
                  <GeneralSection />
                </div>
              )}
              {section === 'ai' && (
                <div data-testid="settings-section-ai">
                  <AiSection />
                </div>
              )}
              {section === 'logs' && (
                <div data-testid="settings-section-logs">
                  <LogsSection />
                </div>
              )}
              {section === 'about' && (
                <div data-testid="settings-section-about">
                  <AboutSection />
                </div>
              )}
            </div>
          </main>
        </SidebarProvider>
      </DialogContent>
    </Dialog>
  )
}
