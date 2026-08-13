import { format } from 'date-fns'
import { useSetAtom } from 'jotai'
import { useNavigate } from 'react-router'

import { Button } from '#components/ui/button'
import { backend } from '#lib/backend/index'
import { refreshDocsAtom } from '#lib/store'

export function timeOfDayGreeting(hour: number): string {
  if (hour < 12) return 'Good morning'
  if (hour < 18) return 'Good afternoon'
  return 'Good evening'
}

export function DashboardGreeting() {
  const navigate = useNavigate()
  // Reuses the sidebar's own atom - SidebarLeft is mounted once, as a
  // sibling to the routed page, not remounted per navigation, so it only
  // ever sees a document created here if this same refresh is called.
  const refreshDocs = useSetAtom(refreshDocsAtom)
  const now = new Date()

  const createDoc = async () => {
    const doc = await backend.createDocument(null, '')
    await refreshDocs()
    navigate(`/doc/${doc.id}`)
  }

  return (
    <div className="flex items-center justify-between">
      <div>
        <h1
          data-testid="dashboard-greeting"
          className="text-2xl font-semibold tracking-tight"
        >
          {timeOfDayGreeting(now.getHours())}
        </h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {format(now, 'EEEE, MMMM d')}
        </p>
      </div>
      <Button onClick={createDoc} data-testid="dashboard-new-doc">
        New document
      </Button>
    </div>
  )
}
