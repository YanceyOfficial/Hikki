import { createFileRoute } from '@tanstack/solid-router'

import { SharedReader } from '../components/shared-reader'
import { reportLink, SharedShell } from '../components/shared-shell'
import { SITE_URL } from '../site'

const title = 'Hikki Shared'

/** A page listed in Hikki Shared: stored readable, read by its record's name (`SharedReader`). */
export const Route = createFileRoute('/shared/$id')({
  head: ({ params }) => ({
    meta: [
      { title },
      { name: 'description', content: 'A page someone shared from Hikki for anyone to read.' },
      { property: 'og:title', content: title },
      { property: 'og:url', content: `${SITE_URL}/shared/${params.id}` }
    ],
    links: [{ rel: 'canonical', href: `${SITE_URL}/shared/${params.id}` }]
  }),
  component: Listed
})

function Listed() {
  const params = Route.useParams()
  return (
    <SharedShell report={reportLink(params().id)}>
      <SharedReader id={params().id} linked={false} />
    </SharedShell>
  )
}
