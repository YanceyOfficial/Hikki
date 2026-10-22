/**
 * The wordmark (design/logo), inline so the letters take the text colour — light or dark — and the sparkle stays
 * Hikki's red. (Inverting the SVG file for dark mode turned the sparkle cyan.)
 */
export function Wordmark(props: { class?: string }) {
  return (
    <svg
      viewBox="-23.85 -123.85 252.9 173.7"
      class={props.class}
      role="img"
      aria-label="Hikki"
      fill="currentColor"
    >
      <g transform="scale(0.1 -0.1)">
        <path d="M383 0L383 277Q383 320 355.5 347Q328 374 286 374Q258 374 236 362Q214 350 201.5 327.5Q189 305 189 277L138 304Q138 360 162 402.5Q186 445 229 469Q272 493 327 493Q382 493 424 469.5Q466 446 490 404Q514 362 514 307L514 0ZM58 0L58 723L189 723L189 0Z" />
        <path
          transform="translate(549.5 0)"
          d="M57 0L57 483L190 483L190 0ZM124 561Q92 561 71 582.5Q50 604 50 636Q50 667 71 689Q92 711 124 711Q157 711 177.5 689Q198 667 198 636Q198 604 177.5 582.5Q157 561 124 561Z"
        />
        <path
          transform="translate(785 0)"
          d="M365 0L179 249L364 483L516 483L298 219L303 283L525 0ZM58 0L58 723L189 723L189 0Z"
        />
        <path
          transform="translate(1301.3 0)"
          d="M365 0L179 249L364 483L516 483L298 219L303 283L525 0ZM58 0L58 723L189 723L189 0Z"
        />
        <path transform="translate(1817.5 0)" d="M58 0L58 483L189 483L189 0Z" />
      </g>
      <path
        fill="var(--color-red)"
        d="M194.08-84.41Q199.8-66.28 217.93-60.56Q199.8-54.84 194.08-36.71Q188.36-54.84 170.23-60.56Q188.36-66.28 194.08-84.41Z"
      />
    </svg>
  )
}
