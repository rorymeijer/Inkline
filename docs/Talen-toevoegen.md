# Een taal toevoegen aan Inkline

Talen zijn data. Een JSON-bestand in
`~/Library/Application Support/Inkline/Languages/` is genoeg; herstart Inkline
en de taal staat in het Taal-menu. Meeleveren doe je door het bestand in
`Sources/InklineSyntax/Resources/Languages/` te zetten.

Een kapot bestand blokkeert niets: het wordt overgeslagen en gemeld, de rest
laadt gewoon door.

## Velden

| Veld | Type | Standaard | Betekenis |
| --- | --- | --- | --- |
| `identifier` | string | **verplicht** | Unieke sleutel, bv. `nim`. Een gelijke identifier overschrijft een meegeleverde taal. |
| `name` | string | `identifier` | Naam in het menu en de statusbalk. |
| `fileExtensions` | [string] | `[]` | Zonder punt, hoofdletterongevoelig. |
| `fileNames` | [string] | `[]` | Volledige namen, bv. `Dockerfile`. Gaan vóór extensies. |
| `firstLinePattern` | string | – | Regex op de eerste regel (shebangs, `<?xml`). |
| `comments` | object | `{}` | `line`, `blockStart`, `blockEnd`; gebruikt door "commentaar aan/uit". |
| `brackets` | [{open, close}] | `()[]{}` | Voor haakjesparen, vouwen en selecteren. |
| `autoClosePairs` | [{open, close}] | `brackets` | Wat automatisch gesloten wordt tijdens typen. |
| `indentation` | object | 4 spaties | `usesTabs`, `indentWidth`, `tabWidth`. |
| `indentationRules` | object | accolades | `increaseAfterPattern`, `decreaseOnPattern`, `reindentTriggers`. |
| `folding` | string | `brackets` | `brackets`, `indentation` of `none`. |
| `keywords` | [string] | `[]` | Voedt de woordaanvulling. |
| `patterns` | [regel] | `[]` | De regex-highlighter, zie onder. |
| `symbols` | [regel] | `[]` | Vult de functielijst. |
| `treeSitter` | object | – | `grammar`, `library`, `highlightsQuery`. |
| `priority` | int | `0` | Wint bij een gedeelde extensie (hoger = sterker). |

## Kleurregels (`patterns`)

```jsonc
{ "scope": "string", "pattern": "\"(?:[^\"\\\\\\n]|\\\\.)*\"", "captureGroup": 0,
  "caseInsensitive": false, "multiline": false }
```

* **Volgorde is prioriteit.** De eerste regel die een positie raakt, wint, en
  alles wat daarmee overlapt vervalt. Commentaar en strings horen dus bovenaan,
  sleutelwoorden eronder. Zo krijgt `let` in `"let x = 1"` geen sleutelwoordkleur.
* **`captureGroup`** kleurt alleen die groep — handig voor
  `\b([a-z_]\w*)\s*(?=\()` om alleen de functienaam te kleuren.
* **`multiline: true`** voor regels die regeleindes mogen overschrijden. Die
  worden één keer per documentversie over het hele bestand gescand en gecachet;
  alle andere regels draaien alleen over het zichtbare bereik.
* Reguliere expressies zijn ICU (`NSRegularExpression`): lookbehind, `\p{L}`,
  inline vlaggen (`(?i)`) en niet-gulzige herhaling werken allemaal.

### Beschikbare scopes

`plain`, `comment`, `documentationComment`, `keyword`, `controlKeyword`,
`storage`, `type`, `constant`, `number`, `string`, `escapeSequence`,
`regularExpression`, `character`, `function`, `method`, `parameter`,
`property`, `variable`, `operator`, `punctuation`, `attribute`, `tag`,
`tagAttribute`, `heading`, `emphasis`, `strong`, `link`, `listMarker`,
`preprocessor`, `label`, `namespace`, `error`.

Thema's kleuren op deze namen; een scope die een thema niet kent, valt terug op
zijn familie (`controlKeyword` → `keyword`, `method` → `function`, …).

## Symbolen (`symbols`)

```jsonc
{ "kind": "function", "pattern": "^\\s*proc\\s+([A-Za-z_]\\w*)", "nameGroup": 1,
  "containerGroup": null }
```

`kind` is een van `function`, `method`, `type`, `class`, `structure`, `enum`,
`protocol`, `interface`, `property`, `variable`, `constant`, `section`, `tag`,
`selector`, `key`, `target`. De regels draaien met `^`/`$` per regel; de
gevonden symbolen staan in documentvolgorde in het functielijstpaneel.

## Tree-sitter

```jsonc
"treeSitter": {
  "grammar": "nim",                     // symbool tree_sitter_nim
  "library": "libtree-sitter-nim.dylib",
  "highlightsQuery": "nim/highlights.scm"
}
```

Beide bestanden komen in `~/Library/Application Support/Inkline/Grammars/`
(of in `Inkline.app/Contents/Resources/Grammars`). Bouwen:

```bash
cc -fPIC -shared -I src src/parser.c src/scanner.c -o libtree-sitter-nim.dylib
```

Capture-namen uit de query worden op de scopes hierboven afgebeeld via de
langste passende prefix: `@keyword.control` → `controlKeyword`,
`@function.method` → `method`, `@variable.parameter` → `parameter`. Ontbreekt de
bibliotheek of de query, dan gebruikt Inkline stilzwijgend de `patterns`.

## Testen zonder de app te starten

```swift
let registry = LanguageRegistry.standard()
let taal = registry.language(withIdentifier: "nim")!
let highlighter = PatternHighlighter(language: taal)
print(highlighter.tokens(in: 0..<tekst.utf16.count, text: tekst))
```

`Tests/InklineSyntaxTests/SyntaxTests.swift` doet precies dit voor de
meegeleverde talen; een eigen taal toevoegen aan die test is de snelste manier
om je regels te controleren.
