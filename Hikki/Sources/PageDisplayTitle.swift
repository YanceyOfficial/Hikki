import HikkiCore
import HikkiUI

extension PageSummary {
    /// The title as shown: the page's own, or "Untitled" for an empty one (`PageTitle.display` — the one place that
    /// fallback is written; a row that wants the empty title muted instead draws `app:page.untitled` itself).
    var displayTitle: String { PageTitle.display(title) }
}
