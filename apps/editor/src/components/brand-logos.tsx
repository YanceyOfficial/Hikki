/**
 * Logos of the services the "/" menu embeds, from Simple Icons (simpleicons.org, CC0; the `simple-icons` package,
 * one named import per mark so the bundle keeps only these). They are trademarks of their owners, used only to
 * identify each service next to its embed. Each is one path in its brand colour (as kagi's key icons draw them), at
 * the Phosphor icons' size; a brand colour too dark to read on a dark surface (GitHub's near-black) takes the row's
 * text colour instead, so it reads in both themes.
 */
import type { SVGProps } from 'react'
import {
  siAirtable,
  siCalendly,
  siCodesandbox,
  siDiagramsdotnet,
  siExcalidraw,
  siFigma,
  siGithub,
  siGoogledrive,
  siLoom,
  siMiro,
  type SimpleIcon
} from 'simple-icons'

export type LogoProps = Omit<SVGProps<SVGSVGElement>, 'ref'> & { size?: number | string }

/**
 * Simple Icons fill their whole 24-unit square; Phosphor's glyphs leave about a twelfth of it free on each side.
 * The same margin here makes a logo look as large as the icons beside it.
 */
const VIEW_BOX = '-2 -2 28 28'

/** Whether a 6-digit brand colour is too dark to see on a dark surface (perceived luminance, kagi's `isHexDark`). */
export function isDarkHex(hex: string): boolean {
  const [r, g, b] = [0, 2, 4].map((i) => Number.parseInt(hex.slice(i, i + 2), 16))
  return 0.299 * r + 0.587 * g + 0.114 * b < 80
}

/** The logo's fill: its brand colour, or the row's text colour when that colour is near-black. */
export const brandFill = (hex: string) => (isDarkHex(hex) ? 'currentColor' : `#${hex}`)

function logo(icon: SimpleIcon, name: string) {
  const fill = brandFill(icon.hex)
  function Logo({ size = 18, ...rest }: LogoProps) {
    return (
      <svg viewBox={VIEW_BOX} width={size} height={size} fill={fill} data-logo={name} {...rest}>
        <path d={icon.path} />
      </svg>
    )
  }
  Logo.displayName = `${name}Logo`
  return Logo
}

export const AirtableLogo = logo(siAirtable, 'Airtable')
export const CalendlyLogo = logo(siCalendly, 'Calendly')
export const CodeSandboxLogo = logo(siCodesandbox, 'CodeSandbox')
export const DrawioLogo = logo(siDiagramsdotnet, 'Drawio')
export const ExcalidrawLogo = logo(siExcalidraw, 'Excalidraw')
export const FigmaLogo = logo(siFigma, 'Figma')
export const GitHubLogo = logo(siGithub, 'GitHub')
export const GoogleDriveLogo = logo(siGoogledrive, 'GoogleDrive')
export const LoomLogo = logo(siLoom, 'Loom')
export const MiroLogo = logo(siMiro, 'Miro')
