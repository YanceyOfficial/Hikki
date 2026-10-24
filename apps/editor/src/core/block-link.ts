/** A link to a block (`hikki://page/<page>#<block>`) and the page's title, for blocks without text of their own. */
export type BlockLink = { href: string; pageLabel: string }
/** Set by the bridge, which knows the page. */
let builder: ((blockId: string) => BlockLink | null) | null = null
export function setBlockLinkBuilder(next: ((blockId: string) => BlockLink | null) | null): void {
  builder = next
}

/** The link to block `blockId` of the open page, or null with no page. */
export function blockLinkFor(blockId: string): BlockLink | null {
  return builder?.(blockId) ?? null
}
