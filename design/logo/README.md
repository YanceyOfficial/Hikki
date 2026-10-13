# Logo

`hikki` in Outfit SemiBold (lowercase, tracking −0.012 em), the last i dotless with the AI sparkle as its dot in
Kurenai. Text is converted to outlines, so the SVGs need no font installed.

| File                              | Use                                                |
| --------------------------------- | -------------------------------------------------- |
| `wordmark-outfit-light.svg`       | on white: ink `#1C1C1C`, sparkle `#D7003A`         |
| `wordmark-outfit-dark.svg`        | on dark: ink `#E6E4DF`, sparkle `#FF6478`          |
| `lockup-hi-star-{light,dark}.svg` | app icon mark + wordmark, side by side             |
| `wordmark-poppins-*.svg`          | the alternate face (closest to the first sketches) |

`node design/logo/generate.mjs` regenerates everything (fontkit is a root devDependency; the fonts in `fonts/` are
OFL). Change the face in `fonts`, the colours in `inks`.
