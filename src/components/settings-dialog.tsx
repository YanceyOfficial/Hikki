import { useAtom } from 'jotai'

import { AboutSection } from '#components/settings/about-section'
import { AppearanceSection } from '#components/settings/appearance-section'
import { GeneralSection } from '#components/settings/general-section'
import { Dialog, DialogContent } from '#components/ui/dialog'
import {
  settingsDialogOpenAtom,
  settingsDialogSectionAtom,
  type SettingsSection
} from '#lib/store'
import { cn } from '#lib/utils'

const SECTIONS: { id: SettingsSection; label: string }[] = [
  { id: 'general', label: 'General' },
  { id: 'appearance', label: 'Appearance' },
  { id: 'ai', label: 'AI' },
  { id: 'logs', label: 'Logs' },
  { id: 'about', label: 'About & Updates' }
]

export function SettingsDialog() {
  const [open, setOpen] = useAtom(settingsDialogOpenAtom)
  const [section, setSection] = useAtom(settingsDialogSectionAtom)

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent
        data-testid="settings-dialog"
        className="flex h-125 w-175 max-w-none gap-0 p-0"
      >
        <nav className="bg-muted/40 flex w-40 shrink-0 flex-col gap-1 border-r p-2">
          {SECTIONS.map((s) => (
            <button
              key={s.id}
              type="button"
              data-testid={`settings-nav-${s.id}`}
              onClick={() => setSection(s.id)}
              className={cn(
                'rounded-md px-2.5 py-1.5 text-left text-sm transition-colors',
                section === s.id
                  ? 'bg-accent text-accent-foreground'
                  : 'text-muted-foreground hover:bg-accent/50'
              )}
            >
              {s.label}
            </button>
          ))}
        </nav>
        <div className="min-w-0 flex-1 overflow-y-auto p-6">
          {/* Tasks 9-11 each replace one of the remaining placeholders with
              the section's real content. */}
          {section === 'general' && (
            <div data-testid="settings-section-general">
              <GeneralSection />
            </div>
          )}
          {section === 'appearance' && (
            <div data-testid="settings-section-appearance">
              <AppearanceSection />
            </div>
          )}
          {section === 'ai' && <div data-testid="settings-section-ai" />}
          {section === 'logs' && <div data-testid="settings-section-logs" />}
          {section === 'about' && (
            <div data-testid="settings-section-about">
              <AboutSection />
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
