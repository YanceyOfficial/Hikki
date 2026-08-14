import { useNavigate } from 'react-router'

import type { DocumentMeta } from '#lib/types'

export function DashboardRecentList({ docs }: { docs: DocumentMeta[] }) {
  const navigate = useNavigate()

  if (docs.length === 0) {
    return (
      <p
        data-testid="dashboard-recent-empty"
        className="text-muted-foreground text-sm"
      >
        Create your first document to see it here.
      </p>
    )
  }

  return (
    <ul data-testid="dashboard-recent-list" className="flex flex-col gap-1">
      {docs.map((doc) => (
        <li key={doc.id}>
          <button
            type="button"
            onClick={() => navigate(`/doc/${doc.id}`)}
            data-testid={`dashboard-recent-${doc.id}`}
            className="hover:bg-accent flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors"
          >
            {doc.icon && <span>{doc.icon}</span>}
            <span className="truncate">{doc.title || 'Untitled'}</span>
          </button>
        </li>
      ))}
    </ul>
  )
}
