import { createFileRoute } from '@tanstack/solid-router'

import { SharedReader } from '../components/shared-reader'
import { reportLink, SharedShell } from '../components/shared-shell'

const title = 'Hikki Community'

/**
 * A page shared by link: the record named in the address, opened in the browser with the key from its fragment
 * (`SharedReader`); the server renders only the frame.
 */
export const Route = createFileRoute('/p/$id')({
  head: () => ({
    meta: [
      { title },
      {
        name: 'description',
        content: 'A page someone shared from Hikki. Only people with the link can read it.'
      },
      // The content is opened in the browser with the link's key: nothing here for a crawler, and nothing it should keep.
      { name: 'robots', content: 'noindex, nofollow' }
    ]
  }),
  component: Published
})

function Published() {
  const params = Route.useParams()
  return (
    <SharedShell report={reportLink(params().id)}>
      <SharedReader id={params().id} linked />
    </SharedShell>
  )
}
