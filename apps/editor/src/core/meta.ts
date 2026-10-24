/**
 * Transaction metas more than one module reads, kept here so none of them imports another for a string.
 *
 * `SAVE_META`: on a transaction kept out of undo that must still be saved — a comment's mark added or removed
 * (undoing it would leave a thread with no passage), a drawing's strokes — so the page counts as edited.
 */
export const SAVE_META = 'hikkiSave'
