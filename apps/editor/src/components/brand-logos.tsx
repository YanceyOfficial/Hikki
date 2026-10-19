/**
 * Logos of the services the "/" menu embeds, from Simple Icons (simpleicons.org, CC0; the `simple-icons` package,
 * one named import per mark so the bundle keeps only these). They are trademarks of their owners, used only to
 * identify each service next to its embed. Each is one path drawn in `currentColor`, so a logo takes its row's
 * text colour like the Phosphor icons around it, at the same size: the brand colours stay out of the menus.
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

function logo(icon: SimpleIcon, name: string) {
  function Logo({ size = 18, ...rest }: LogoProps) {
    return (
      <svg
        viewBox={VIEW_BOX}
        width={size}
        height={size}
        fill="currentColor"
        data-logo={name}
        {...rest}
      >
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
