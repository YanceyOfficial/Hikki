import { createFileRoute, redirect } from '@tanstack/solid-router'

/** Hikki Shared was renamed Hikki Community: the old address, and its search, go there. */
export const Route = createFileRoute('/shared/')({
  beforeLoad: ({ search }) => {
    throw redirect({ to: '/community', search, statusCode: 301 })
  }
})
