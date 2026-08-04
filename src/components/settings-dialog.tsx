import { useAtom } from 'jotai'

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
          {/* Task 8-11 each replace one of these placeholders with the
              section's real content - this task builds only the shell. */}
          {section === 'general' && (
            <div data-testid="settings-section-general" />
          )}
          {section === 'appearance' && (
            <div data-testid="settings-section-appearance" />
          )}
          {section === 'ai' && <div data-testid="settings-section-ai" />}
          {section === 'logs' && <div data-testid="settings-section-logs" />}
          {section === 'about' && <div data-testid="settings-section-about" />}
        </div>
      </DialogContent>
    </Dialog>
  )
}
