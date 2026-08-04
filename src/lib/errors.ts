import { getDefaultStore } from 'jotai'
import { toast } from 'sonner'

import { log } from '#lib/logger'
import { openSettingsAtom } from '#lib/store'

export type HkErrorCode =
  | 'HK-1001'
  | 'HK-1002'
  | 'HK-1003'
  | 'HK-1004'
  | 'HK-1005'
  | 'HK-1006'
  | 'HK-1007'
  | 'HK-2001'
  | 'HK-3001'
  | 'HK-3002'
  | 'HK-3003'
  | 'HK-3004'
  | 'HK-3005'
  | 'HK-6001'
  | 'HK-6002'
  | 'HK-9001'

type ErrorSeverity = 'info' | 'warning' | 'error'

interface ErrorDefinition {
  message: string
  severity: ErrorSeverity
  /** When present, the toast gets an action button opening Settings to this section. */
  openSettings?: 'general' | 'appearance' | 'ai' | 'logs' | 'about'
}

const ERROR_DEFINITIONS: Record<HkErrorCode, ErrorDefinition> = {
  'HK-1001': { message: 'A file system error occurred.', severity: 'error' },
  'HK-1002': {
    message: 'Saved data could not be read - it may be corrupted.',
    severity: 'error'
  },
  'HK-1003': { message: 'That document was not found.', severity: 'error' },
  'HK-1004': { message: 'The file could not be imported.', severity: 'error' },
  'HK-1005': {
    message: 'Could not switch to the selected vault folder.',
    severity: 'error',
    openSettings: 'general'
  },
  'HK-1006': {
    message:
      "This page's content could not be displayed - the file may be damaged.",
    severity: 'error'
  },
  'HK-1007': { message: 'Could not copy to the clipboard.', severity: 'error' },
  'HK-2001': {
    message: 'Search index error - try rebuilding the index.',
    severity: 'error',
    openSettings: 'general'
  },
  'HK-3001': {
    message: 'Could not access the Keychain for this API key.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3002': {
    message: 'Could not load your AI settings.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3003': {
    message: 'Could not save that API key.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3004': {
    message: 'Could not save your default AI provider/model.',
    severity: 'error',
    openSettings: 'ai'
  },
  'HK-3005': {
    message: 'The Writing Tools request failed.',
    severity: 'error'
  },
  'HK-6001': {
    message: 'Could not load the logs.',
    severity: 'error',
    openSettings: 'logs'
  },
  'HK-6002': {
    message: 'Could not export the logs.',
    severity: 'error',
    openSettings: 'logs'
  },
  'HK-9001': { message: 'Something unexpected went wrong.', severity: 'error' }
}

const FALLBACK: ErrorDefinition = {
  message: 'Something unexpected went wrong.',
  severity: 'error'
}

export function reportError(
  code: HkErrorCode,
  context?: Record<string, unknown>
) {
  const definition = ERROR_DEFINITIONS[code] ?? FALLBACK
  const toastFn =
    definition.severity === 'warning'
      ? toast.warning
      : definition.severity === 'info'
        ? toast.info
        : toast.error
  toastFn(definition.message, {
    description: code,
    action: definition.openSettings
      ? {
          label: 'Open Settings',
          onClick: () =>
            getDefaultStore().set(openSettingsAtom, definition.openSettings)
        }
      : undefined
  })
  log.error('error', definition.message, { code, ...context })
}
