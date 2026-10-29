import { createFileRoute } from '@tanstack/solid-router'

import { SharedReader } from '../components/shared-reader'
import { reportLink, SharedShell } from '../components/shared-shell'
import { SITE_URL } from '../site'

const title = 'Hikki Community'

/** A page listed in Hikki Community: stored readable, read by its record's name (`SharedReader`). */
export const Route = createFileRoute('/community/$id')({
  head: ({ params }) => ({
    meta: [
      { title },
      { name: 'description', content: 'A page someone shared from Hikki for anyone to read.' },
      { property: 'og:title', content: title },
      { property: 'og:url', content: `${SITE_URL}/community/${params.id}` }
    ],
    links: [{ rel: 'canonical', href: `${SITE_URL}/community/${params.id}` }]
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
