import { t } from './i18n'

/** An AI request's failure as the app reports it (`aiEvent` error): its code, the provider, the provider's words. */
export type AIErrorInfo = { code: string; provider?: string | null; message?: string | null }

/** What the user reads for an AI failure, in the page's language. */
export function aiErrorText(error: AIErrorInfo): string {
  switch (error.code) {
    case 'missingKey':
      return t('ai.error.missingKey', { provider: error.provider ?? '' })
    case 'badBaseURL':
      return t('ai.error.badBaseURL', { provider: error.provider ?? '' })
    case 'unauthorized':
      return t('ai.error.unauthorized')
    case 'rateLimited':
      return t('ai.error.rateLimited')
    case 'unavailable':
      return t('ai.error.unavailable')
    case 'offline':
      return t('ai.error.offline')
    case 'rejected':
      return error.message
        ? t('ai.error.rejectedWith', { message: error.message })
        : t('ai.error.rejected')
    case 'mediaUnreadable':
      return t('ai.error.mediaUnreadable')
    case 'locked':
      return t('ai.error.locked')
    default:
      return t('ai.error.invalidResponse')
  }
}
