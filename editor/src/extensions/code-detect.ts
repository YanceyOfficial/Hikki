/**
 * Guesses a code block's language from the text. highlight.js's own guess only compares grammar
 * relevance, and on a short snippet CSS, JavaScript and Python score the same; so each catalog language
 * has a few signatures — the tokens a reader would spot — and the strongest wins when it stands out.
 */
type Signature = [RegExp, number]

const SIGNATURES: Record<string, Signature[]> = {
  javascript: [
    [/\b(const|let|var)\s+\w+\s*=/, 3],
    [/\bfunction\b\s*\w*\s*\(/, 3],
    [/=>/, 2],
    [/\bconsole\.(log|error|warn)\(/, 3],
    [/\b(export|import)\b.*\b(from|default)\b/, 2],
    [/\b(document|window)\.\w+/, 3],
    [/\brequire\(/, 2]
  ],
  typescript: [
    [/\b(const|let|var)\s+\w+\s*[:=]/, 2],
    [/=>/, 1],
    [/:\s*(string|number|boolean|void|unknown|never|any)\b/, 4],
    [/\binterface\s+\w+\s*(<[^>]*>)?\s*\{/, 4],
    [/\btype\s+\w+\s*(<[^>]*>)?\s*=/, 4],
    [/\b(readonly|implements|enum)\b/, 2],
    [/\bexport\b/, 1]
  ],
  python: [
    [/^\s*def\s+\w+\s*\(.*\)\s*(->\s*[\w[\], ]+)?:\s*$/m, 5],
    [/^\s*(if|elif|for|while|with|try|except|class)\b.*:\s*$/m, 3],
    [/^\s*(from\s+[\w.]+\s+)?import\s+\w/m, 2],
    [/\bprint\(/, 2],
    [/\b(self|None|True|False)\b/, 2],
    [/^\s*#(?!include|import|define)/m, 1]
  ],
  swift: [
    [/\b(func)\s+\w+\s*\(/, 4],
    [/\b(struct|class|enum|protocol|extension)\s+\w+(\s*:\s*[\w, ]+)?\s*\{/, 3],
    [/\bimport\s+(Foundation|SwiftUI|UIKit|AppKit|Combine)\b/, 5],
    [/\b(let|var)\s+\w+\s*:\s*[A-Z]\w*/, 3],
    [/\b(guard|defer|inout|some)\b/, 3],
    [/@(State|Binding|Published|Observable|MainActor|objc)\b/, 4],
    [/\?\?|\bnil\b/, 1]
  ],
  rust: [
    [/\bfn\s+\w+\s*(<[^>]*>)?\s*\(/, 4],
    [/\blet\s+(mut\s+)?\w+/, 3],
    [/\b(impl|trait|pub|mod|crate|struct)\b/, 2],
    [/\w+::\w+/, 2],
    [/&(mut\s+)?(self|str)\b/, 3],
    [/\bprintln!\(/, 4],
    [/\b(Some|None|Ok|Err)\(/, 2]
  ],
  go: [
    [/^\s*package\s+\w+/m, 5],
    [/\bfunc\s+(\(\w+\s+\*?\w+\)\s+)?\w+\s*\(/, 4],
    [/:=/, 3],
    [/\bfmt\.\w+\(/, 4],
    [/\b(go|defer|chan|goroutine)\b/, 2],
    [/\berr\s*!=\s*nil\b/, 4]
  ],
  c: [
    [/#include\s*<[\w./]+>/, 4],
    [/\bint\s+main\s*\(/, 4],
    [/\bprintf\s*\(/, 3],
    [/\b(malloc|free|sizeof)\s*\(/, 2],
    [/\b(unsigned|size_t|char\s*\*)/, 2]
  ],
  cpp: [
    [/#include\s*<[\w./]+>/, 3],
    [/\bstd::\w+/, 5],
    [/\b(cout|cin|endl)\b/, 4],
    [/\btemplate\s*</, 4],
    [/\b(class|namespace)\s+\w+/, 2],
    [/\bint\s+main\s*\(/, 2]
  ],
  java: [
    [/\bpublic\s+(static\s+)?(class|void|int|String)\b/, 4],
    [/\bSystem\.out\.print(ln)?\(/, 5],
    [/\bimport\s+java\./, 5],
    [/\bnew\s+[A-Z]\w*(<[^>]*>)?\s*\(/, 2],
    [/\b(private|protected)\s+\w+\s+\w+/, 2]
  ],
  kotlin: [
    [/\bfun\s+\w+\s*\(/, 4],
    [/\bval\s+\w+/, 3],
    [/\bdata\s+class\b/, 5],
    [/\bprintln\(/, 2],
    [/\bwhen\s*\(/, 2],
    [/\?\.|!!/, 1]
  ],
  csharp: [
    [/\busing\s+System\b/, 5],
    [/\bnamespace\s+[\w.]+/, 3],
    [/\bConsole\.Write(Line)?\(/, 5],
    [/\bpublic\s+(static\s+)?(class|void|string|int)\b/, 3],
    [/\bvar\s+\w+\s*=\s*new\b/, 2]
  ],
  php: [
    [/<\?php/, 6],
    [/\$\w+\s*=/, 3],
    [/\becho\b/, 2],
    [/->\w+\(/, 2],
    [/\bfunction\s+\w+\s*\(/, 1]
  ],
  ruby: [
    [/^\s*def\s+\w+[?!]?\s*(\(.*\))?\s*$/m, 4],
    [/^\s*end\s*$/m, 3],
    [/\b(puts|require|attr_accessor|attr_reader)\b/, 3],
    [/\bdo\s*\|[^|]*\|/, 3],
    [/\b(elsif|unless|nil\?)\b/, 2]
  ],
  sql: [
    [
      /\b(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE)\b/i,
      5
    ],
    [/\b(FROM|WHERE|JOIN|GROUP\s+BY|ORDER\s+BY|VALUES|SET)\b/i, 2],
    [/\b(VARCHAR|INTEGER|PRIMARY\s+KEY|NOT\s+NULL)\b/i, 3]
  ],
  json: [
    [/^\s*[[{]/, 2],
    [/"[^"\n]+"\s*:\s*("|\d|true|false|null|\[|\{)/, 4],
    [/[}\]]\s*$/, 1]
  ],
  yaml: [
    [/^---\s*$/m, 4],
    [/^\s*[\w.-]+:\s*(\S.*)?$/m, 2],
    [/^\s*-\s+[\w"']/m, 2],
    [/^\s*[\w-]+:\s*$/m, 2]
  ],
  xml: [
    [/<\/[a-zA-Z][\w:-]*>/, 3],
    [/<[a-zA-Z][\w:-]*(\s+[\w:-]+="[^"]*")*\s*\/?>/, 3],
    [/<!DOCTYPE\s+html/i, 6],
    [/<\?xml\b/, 6],
    [/<(div|span|p|a|html|body|head|script|style|svg|path)\b/, 3]
  ],
  css: [
    [/[.#]?[\w-]+(\s*[,>+~]\s*[.#]?[\w-]+)*\s*\{[^}]*\b[\w-]+\s*:\s*[^;}]+;?[^}]*\}/, 4],
    [/@(media|import|font-face|keyframes|supports)\b/, 3],
    [/\b(margin|padding|display|color|background|font-size|border|width|height)\s*:/, 3],
    [/:(hover|focus|active|root|not)\b/, 2]
  ],
  scss: [
    [/\$[\w-]+\s*:\s*[^;]+;/, 5],
    [/@(mixin|include|extend|use|forward)\b/, 5],
    [/[.#&][\w-]*\s*\{[^}]*[.#&][\w-]*\s*\{/, 3],
    [/\b(margin|padding|display|color|background)\s*:/, 1]
  ],
  less: [
    [/@[\w-]+\s*:\s*[^;]+;/, 4],
    [/\.[\w-]+\(\s*[^)]*\)\s*;/, 3],
    [/\b(margin|padding|display|color|background)\s*:/, 1]
  ],
  bash: [
    [/^#!\s*\/.*\b(ba|z|da)?sh\b/m, 6],
    [/\b(echo|export|source|chmod|mkdir|sudo|grep|sed|awk)\b/, 2],
    [/\$\{?[A-Za-z_]\w*\}?/, 2],
    [/\b(if|for|while)\b.*;\s*(then|do)\b/, 4],
    [/^\s*(fi|done|esac)\s*$/m, 4],
    [/\|\s*\w+/, 1]
  ],
  shell: [
    [/^\$\s+\S/m, 5],
    [/^>\s+\S/m, 1]
  ],
  diff: [
    [/^(\+\+\+|---)\s+\S/m, 5],
    [/^@@\s+-\d+(,\d+)?\s+\+\d+(,\d+)?\s+@@/m, 6],
    [/^[+-](?![+-])/m, 2]
  ],
  markdown: [
    [/^#{1,6}\s+\S/m, 4],
    [/\[[^\]]+\]\([^)]+\)/, 3],
    [/^\s*[-*]\s+\S/m, 1],
    [/\*\*[^*]+\*\*/, 2],
    [/^```/m, 3]
  ],
  makefile: [
    [/^[\w.-]+:\s*([\w.-]+\s*)*$/m, 3],
    [/^\t\S/m, 3],
    [/\$\(\w+\)/, 3],
    [/^\.PHONY:/m, 6]
  ],
  ini: [
    [/^\s*\[[^\]\n]+\]\s*$/m, 4],
    [/^\s*[\w.-]+\s*=\s*\S/m, 2],
    [/^\s*[;#]/m, 1]
  ],
  graphql: [
    [/\b(query|mutation|subscription|fragment)\s+\w*\s*[({]/, 5],
    [/\btype\s+\w+\s*\{[^}]*\b\w+\s*:\s*\[?\w+\]?!?/, 5],
    [/\{\s*\w+\s*(\([^)]*\))?\s*\{/, 2]
  ],
  lua: [
    [/\blocal\s+\w+/, 4],
    [/\bfunction\s*\w*\s*\(/, 2],
    [/^\s*end\s*$/m, 2],
    [/--\s/, 1],
    [/\b(then|elseif|nil)\b/, 2]
  ],
  perl: [
    [/\bmy\s+[$@%]\w+/, 5],
    [/\buse\s+(strict|warnings)\b/, 5],
    [/\bprint\s+[^(]/, 1],
    [/[$@%]\w+/, 1]
  ],
  r: [
    [/<-/, 4],
    [/\blibrary\(\w+\)/, 5],
    [/\bfunction\s*\(/, 1],
    [/\bc\(/, 2],
    [/\b(data\.frame|ggplot|dplyr)\b/, 4]
  ],
  objectivec: [
    [/@(interface|implementation|end|property|synthesize)\b/, 6],
    [/#import\s*[<"]/, 4],
    [/\[\w+\s+\w+(:\w*)*\]/, 3],
    [/\bNS[A-Z]\w+/, 3]
  ],
  wasm: [
    [/\(module\b/, 6],
    [/\(func\b/, 4],
    [/\b(i32|i64|f32|f64)\.\w+/, 4]
  ]
}

/** Below this nothing stands out; the block stays unlabelled. */
const MIN_SCORE = 4
/** The best guess must beat the runner-up by this much, or it's a coin toss. */
const MIN_MARGIN = 1.3

/** The catalog id the text most looks like, or null when nothing stands out clearly. */
export function detectLanguage(text: string): string | null {
  const sample = text.trim()
  if (sample.length < 12) return null
  const scores = Object.entries(SIGNATURES)
    .map(
      ([id, signatures]) =>
        [
          id,
          signatures.reduce((sum, [re, weight]) => sum + (re.test(sample) ? weight : 0), 0)
        ] as const
    )
    .filter(([, score]) => score > 0)
    .toSorted((a, b) => b[1] - a[1])
  const [best, second] = scores
  if (!best || best[1] < MIN_SCORE) return null
  if (second && best[1] < second[1] * MIN_MARGIN) return null
  return best[0]
}
