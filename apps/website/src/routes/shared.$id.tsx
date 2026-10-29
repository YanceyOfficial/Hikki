import { createFileRoute, redirect } from '@tanstack/solid-router'

/** A listed page's old address (Hikki Shared, now Hikki Community), as builds before the rename link it. */
export const Route = createFileRoute('/shared/$id')({
  beforeLoad: ({ params }) => {
    throw redirect({ to: '/community/$id', params: { id: params.id }, statusCode: 301 })
  }
})
