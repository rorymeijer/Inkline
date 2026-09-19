# Inkline

**Elke taal. Elk bestand. Meteen open.**
_Licht, snel, uitbreidbaar._

Inkline is een native macOS-teksteditor voor code en platte tekst: tabbladen,
syntaxkleuring, zoeken in bestanden, macro's en een echt plugin-systeem — in
Swift, met SwiftUI voor de vensterstructuur en AppKit (`NSTextView`) waar
precisie en snelheid tellen. Geen Electron, geen webview, geen sandbox die
Find-in-Files in de weg zit.

Bundle-ID: `nl.rorymeijer.inkline` · macOS 13+ · distributie buiten de App Store
(Developer ID, notarisatie, DMG, automatische updates via Sparkle).

---

## Inhoud

1. [Functies](#functies)
2. [Bouwen en draaien](#bouwen-en-draaien)
3. [Architectuur](#architectuur)
4. [Een nieuwe taal toevoegen](#een-nieuwe-taal-toevoegen)
5. [Een plugin schrijven](#een-plugin-schrijven)
6. [Thema's](#themas)
7. [Sneltoetsen](#sneltoetsen)
8. [Signeren, notariseren en distribueren](#signeren-notariseren-en-distribueren)
9. [Sparkle instellen](#sparkle-instellen)
10. [App-icoon](#app-icoon)
11. [Status en bekende beperkingen](#status-en-bekende-beperkingen)

---

## Functies

**Editor**

- Tabbladen met herordenen, "niet bewaard"-indicator, en volledig sessieherstel
  (open bestanden, cursorposities, scrollpositie, bladwijzers — ook van
  niet-bewaarde buffers).
- Syntaxkleuring via tree-sitter waar een grammatica beschikbaar is, met een
  data-gedreven regex-highlighter als terugval. 25 meegeleverde taaldefinities:
  Swift, JS/TS, HTML, CSS, JSON, XML, Markdown, PHP, Python, Shell, YAML, SQL,
  C, C++, Java, Go, Rust, Ruby, Lua, Kotlin, TOML, INI, Dockerfile en meer.
- Zoeken en vervangen: incrementeel, reguliere expressies, hoofdlettergevoelig,
  heel woord, escape-tekens (`\n`, `\t`), alle treffers markeren, alle treffers
  selecteren (multi-cursor), vervangen in alle open tabbladen, en **Find in
  Files** over mappen met een resultatenpaneel.
- Regelnummers, huidige-regel-markering, code folding, haakjesparen,
  automatisch inspringen, inspringhulplijnen.
- Multi-cursor (⌘-klik) en kolom-/blokselectie (⌥-slepen).
- Splitsen in twee panelen, hetzelfde of verschillende bestanden, optioneel met
  gesynchroniseerd scrollen.
- Codering en regeleindes: detectie en conversie van UTF-8/16/32, Latin-1,
  Windows-1252 en meer, en tussen LF/CRLF/CR — allemaal via de statusbalk.
- Statusbalk met regel/kolom, selectiegrootte, taal, codering, regeleinde,
  bestandsgrootte en INS/OVR.
- Instelbare tabs/spaties, witruimte trimmen bij bewaren, regels afbreken,
  zoombaar lettertype.

**Notepad++-klasse functiepariteit**

- Macro's: opnemen, afspelen, opslaan met naam, sneltoets toewijzen, herhalen
  of tot einde bestand.
- Plugin-systeem met gedocumenteerde API, plugin-beheerder en drie
  voorbeeldplugins (JSON-formatter, hex-weergave, kolomgereedschap).
- Functielijst/symbolenpaneel, bestandsverkenner, zoekresultaten en
  plugin-panelen in één dockbare zijbalk.
- Benoemde sessies opslaan en laden.
- Vergelijk-weergave (Myers-diff) tussen twee bestanden.
- Bladwijzers per regel, ga-naar-regel, ga-naar-bijbehorend-haakje.
- Tekstbewerkingen: hoofd-/kleine letters, sorteren (ook numeriek), dubbele en
  lege regels verwijderen, regels omkeren/samenvoegen/afbreken/verplaatsen,
  base64/URL/HTML coderen en decoderen, tabs⇄spaties, commentaar aan/uit,
  kolomeditor met tekst- en getallenreeksen.
- Woordaanvulling uit het document, taalsleutelwoorden en symbolen.
- Licht/donker thema plus eigen thema's als JSON.

**macOS**

- Volledige menubalk (Archief/Wijzig/Zoeken/Weergave/Codering/Taal/Macro/
  Plugins/Venster) met standaard sneltoetsen.
- Licht/donker mode en systeemaccentkleur, Retina-scherp.
- Slepen en neerzetten op venster en Dock-icoon, "Open met" voor tekst- en
  codebestanden.
- VoiceOver-labels op de editor, tabbladen en zoekbalk.
- Nederlandstalige interface via String Catalog; code en API zijn Engelstalig.

---

## Bouwen en draaien

Vereisten: macOS 13+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/rorymeijer/Inkline.git
cd Inkline

# 1. De headless kern testen (geen Xcode-project nodig, geen netwerk)
swift test

# 2. Het Xcode-project genereren en openen
cd App && xcodegen generate && open Inkline.xcodeproj
```

`xcodegen generate` maakt `App/Inkline.xcodeproj` uit `App/project.yml`; het
projectbestand staat bewust niet in git. De app-target haalt Sparkle en
SwiftTreeSitter als Swift Package-afhankelijkheden op (daarvoor is bij de
eerste build netwerk nodig).

> `swift test` draait alleen de kern (`InklineCore`, `InklineSyntax`,
> `InklinePluginAPI`). Die targets hebben géén externe afhankelijkheden, zodat
> de testsuite offline en in een paar seconden draait — ook vanuit
> `scripts/release.sh`.

---

## Architectuur

```
Inkline/
├── Package.swift                 Swift-package met de headless kern
├── Sources/
│   ├── InklineCore/              tekstbuffer, I/O, zoeken, bewerkingen, macro's
│   ├── InklineSyntax/            talen, thema's, highlighters  (+ Resources/)
│   ├── InklinePluginAPI/         plugin-protocollen en -beheer
│   └── InklineTreeSitter/        tree-sitter-koppeling (in de app gecompileerd)
├── Tests/                        unit tests voor alle drie de kernmodules
├── App/
│   ├── project.yml               XcodeGen-spec (app + 3 plugin-bundels)
│   ├── Supporting/               Info.plist, entitlements
│   ├── Resources/                Assets.xcassets, Localizable.xcstrings
│   └── Sources/
│       ├── App/                  @main, AppDelegate, menubalk, Sparkle
│       ├── Model/                workspace, documenten, zoeken, instellingen
│       ├── Editor/               NSTextView-laag, tekststorage, gutter, thema
│       ├── UI/                   SwiftUI-vensters en -panelen
│       └── Commands/             alle menucommando's in de commandoregistry
├── Plugins/                      drie voorbeeldplugins
├── docs/                         taal- en plugin-documentatie
└── scripts/                      release.sh, make-app-icon.py
```

### De drie lagen

**1. Editor-kern (`InklineCore`) — geen AppKit, geen UI.**
`PieceTable` is de tekstopslag: het originele bestand wordt één keer gelezen en
nooit meer gekopieerd, elke invoeging gaat naar een append-buffer, en stukken
("pieces") beschrijven het document als een rij spans. Elk stuk cachet zijn
regelbeginnen, met prefix-sommen erboven, zodat `lineNumber(at:)` en
`offsetOfLineStart(_:)` logaritmisch zijn in plaats van een scan over het
document. Offsets zijn UTF-16-eenheden — dezelfde eenheid als `NSRange`,
`NSTextView` en `NSRegularExpression`, wat een hele klasse conversiefouten
wegneemt. Regeleindes zijn binnen de buffer altijd LF; conversie gebeurt bij
lezen en schrijven (`FileLoader`), zodat geen enkele berekening rekening hoeft
te houden met een CRLF dat over twee stukken valt.

Daarbovenop: `TextBuffer` (undo/redo met samenvoeging van typen, observers),
`SearchEngine` (alle zoekmodi als één regex-implementatie), `FindInFilesSearch`,
`TextTransforms`, `ColumnEditor`, `DiffEngine` (Myers), `BookmarkSet`,
`FoldingCalculator`, `MacroRecorder`/`MacroPlayer`, `SessionStore` en
`CommandRegistry`.

**2. Syntax (`InklineSyntax`) — data, geen code per taal.**
`LanguageDefinition` en `Theme` zijn `Codable` structs die uit JSON komen.
`PatternHighlighter` (regex) en `TreeSitterHighlighter` implementeren allebei
`SyntaxHighlighter`; `HighlightCoordinator` cachet per blok van 16 KB, rekent op
een achtergrondwachtrij en meldt per bereik terug aan de UI. De editor vraagt
alleen om het *zichtbare* bereik — dat is waarom een bestand van 100 MB direct
openklapt.

**3. App (`App/Sources`) — SwiftUI voor structuur, AppKit voor tekst.**
`InklineTextStorage` (een `NSTextStorage`) is het levende bewerkingsoppervlak;
elke wijziging wordt doorgegeven aan de `TextBuffer` van het document, zodat
zoeken, transformaties, macro's en plugins met dezelfde tekst werken als de
gebruiker ziet. `NSLayoutManager` draait met `allowsNonContiguousLayout`, dus
alleen wat zichtbaar is wordt gelayout. Code folding verbergt glyphs via
`layoutManager(_:shouldGenerateGlyphs:…)` — de tekst zelf wordt nooit
aangepast. Twee panelen delen één `NSTextStorage` met elk hun eigen
layoutmanager: hetzelfde bestand in twee panelen blijft daardoor gratis in sync.

### Bewuste keuzes

- **Commandoregistry als enige doorgang.** Menu's, macro's en plugins roepen
  allemaal dezelfde `EditorCommand` aan. Daardoor kan een macro een
  plugin-commando opnemen zonder dat daar één regel speciale code voor nodig is.
- **Macro's slaan betekenis op, geen toetsaanslagen.** `MacroAction` is
  `Codable`; een macro is leesbaar, deelbaar en werkt op een andere
  toetsenbordindeling.
- **Alles wat kan falen, faalt zacht.** Een kapotte taal-JSON, een ontbrekende
  grammatica of een plugin die tijdens activatie gooit, wordt gemeld in de
  beheerder — nooit fataal bij het starten.
- **Niet gesandboxed.** Find-in-Files, de bestandsverkenner en losse
  plugin-bundels hebben vrije bestandstoegang nodig. Daarom Developer ID +
  notarisatie in plaats van de App Store.

---

## Een nieuwe taal toevoegen

Een taal is één JSON-bestand. Zet het in
`~/Library/Application Support/Inkline/Languages/` (of in
`Sources/InklineSyntax/Resources/Languages/` om het mee te leveren) en herstart.
Geen code, geen build.

```jsonc
{
  "identifier": "nim",
  "name": "Nim",
  "fileExtensions": ["nim", "nims"],
  "fileNames": ["nim.cfg"],
  "firstLinePattern": "^#!.*\\bnim\\b",
  "comments": { "line": "#", "blockStart": "#[", "blockEnd": "]#" },
  "indentation": { "usesTabs": false, "indentWidth": 2, "tabWidth": 2 },
  "indentationRules": {
    "increaseAfterPattern": ":\\s*$",
    "decreaseOnPattern": "^\\s*(?:else|elif)\\b",
    "reindentTriggers": [":"]
  },
  "folding": "indentation",            // "brackets" | "indentation" | "none"
  "keywords": ["proc", "var", "let", "const", "type"],
  "patterns": [
    { "scope": "comment", "pattern": "#\\[[\\s\\S]*?\\]#", "multiline": true },
    { "scope": "comment", "pattern": "#[^\\n]*" },
    { "scope": "string",  "pattern": "\"(?:[^\"\\\\\\n]|\\\\.)*\"" },
    { "scope": "number",  "pattern": "\\b\\d+(?:\\.\\d+)?\\b" },
    { "scope": "storage", "pattern": "\\b(?:proc|func|type|var|let|const)\\b" },
    { "scope": "controlKeyword", "pattern": "\\b(?:if|else|elif|for|while|return)\\b" },
    { "scope": "type", "pattern": "\\b[A-Z][A-Za-z0-9_]*\\b" },
    { "scope": "function", "pattern": "\\b([a-z_][\\w]*)\\s*(?=\\()", "captureGroup": 1 }
  ],
  "symbols": [
    { "kind": "function", "pattern": "^\\s*proc\\s+([A-Za-z_]\\w*)", "nameGroup": 1 }
  ],
  "treeSitter": {
    "grammar": "nim",
    "library": "libtree-sitter-nim.dylib",
    "highlightsQuery": "nim/highlights.scm"
  }
}
```

Belangrijk om te weten:

- **Volgorde telt.** Regels worden op volgorde geprobeerd; de eerste die een
  positie raakt wint. Zet commentaar en strings dus vóór sleutelwoorden.
- **`multiline: true`** is voor regels die over regeleindes lopen (blokcommentaar,
  heredocs). Die worden één keer per documentversie gescand en gecachet.
- **Scopes** zijn de vaste lijst uit `HighlightScope`. Thema's kleuren op die
  namen; onbekende namen worden genegeerd.
- Alle velden behalve `identifier` zijn optioneel. Een taal van vier regels
  werkt gewoon.

### Met een tree-sitter-grammatica

Als `treeSitter` is ingevuld én de dylib gevonden wordt, gebruikt Inkline de
parser in plaats van de regexen; anders valt hij automatisch terug. Bouw de
grammatica als dynamische bibliotheek en zet hem samen met de
`highlights.scm` in `~/Library/Application Support/Inkline/Grammars/`:

```bash
git clone https://github.com/alaviss/tree-sitter-nim
cd tree-sitter-nim
cc -fPIC -shared -I src src/parser.c src/scanner.c -o libtree-sitter-nim.dylib

mkdir -p ~/Library/Application\ Support/Inkline/Grammars/nim
cp libtree-sitter-nim.dylib ~/Library/Application\ Support/Inkline/Grammars/
cp queries/highlights.scm  ~/Library/Application\ Support/Inkline/Grammars/nim/
```

Inkline zoekt het symbool `tree_sitter_<grammar>` op en vertaalt de
capture-namen uit de query (`@keyword.control`, `@function.method`, …) naar zijn
eigen scopes via de langste passende prefix. Een nieuwe grammatica heeft dus
geen code nodig, alleen de juiste capture-namen.

Zie ook [`docs/Talen-toevoegen.md`](docs/Talen-toevoegen.md).

---

## Een plugin schrijven

Een plugin is een bundel (`MijnPlugin.inklineplugin`) met een `NSPrincipalClass`
die `InklinePlugin` implementeert. Inkline maakt er één instantie van, roept
`activate(host:)` aan en ruimt bij uitschakelen alles op wat via de host is
geregistreerd.

```swift
import AppKit
import InklineCore
import InklinePluginAPI

@objc(WoordenTellerPlugin)
public final class WoordenTellerPlugin: NSObject, InklinePlugin {

    public static let manifest = PluginManifest(
        identifier: "nl.example.inkline.plugin.woordenteller",
        name: "Woordenteller",
        version: "1.0",
        summary: "Telt de woorden in de selectie of het document.",
        capabilities: [.editText, .contributeMenu])

    public override required init() { super.init() }

    public func activate(host: PluginHost) throws {
        host.register(command: PluginCommand(identifier: "woordenteller.tel",
                                             title: "Woorden tellen",
                                             keyEquivalent: "w",
                                             modifierDescription: "cmd,ctrl") { invocation in
            guard let document = invocation.document else { throw PluginError.noActiveDocument }
            let tekst = document.selectedRange.isEmpty ? document.text : document.selectedText
            let aantal = tekst.split { !$0.isLetter && !$0.isNumber }.count
            invocation.host.showMessage("\(aantal) woorden", style: .informational)
        })
        host.register(menuItem: PluginMenuItem(title: "Woorden tellen",
                                               commandIdentifier: "woordenteller.tel"))
    }
}
```

`Info.plist` van de bundel:

```xml
<key>NSPrincipalClass</key>            <string>WoordenTellerPlugin</string>
<key>InklinePluginIdentifier</key>     <string>nl.example.inkline.plugin.woordenteller</string>
<key>InklinePluginName</key>           <string>Woordenteller</string>
<key>InklinePluginAPIVersion</key>     <string>1.0</string>
<key>InklinePluginCapabilities</key>   <array><string>editText</string></array>
```

Wat de host biedt (`PluginHost`): commando's, menu-items en dockbare panelen
registreren, het actieve en alle open documenten opvragen, een eigen
opslagmap, meldingen en logging, en `performOnMainThread`. Wat een document
biedt (`PluginDocument`): tekst lezen, selectie lezen en zetten, bereiken
vervangen, meerdere bewerkingen als één undo-stap groeperen, en regel/offset
omrekenen.

Bouwen en installeren:

```bash
# Als target in App/project.yml (zoals de drie voorbeelden), of los:
xcodebuild -project App/Inkline.xcodeproj -scheme Inkline -configuration Release build
cp -R build/Release/Woordenteller.inklineplugin \
      ~/Library/Application\ Support/Inkline/Plugins/
```

Daarna verschijnt hij in **Plugins ▸ Plugins beheren…**, waar je hem aan- en
uitzet. Een plugin die bij activatie een fout gooit, wordt met reden getoond en
overgeslagen.

> **API-versie.** De host draait versie `1.0`. Een plugin laadt als het
> hoofdversienummer gelijk is en de gevraagde minorversie niet hoger is dan die
> van de host. De protocollen zitten in een *dynamische* bibliotheek, zodat host
> en plugin exact dezelfde types delen.

De drie voorbeelden in `Plugins/` laten elk iets anders zien:
`JSONFormatter` (tekstcommando's), `HexViewer` (een dockbaar `NSView`-paneel),
`ColumnTools` (kolombewerkingen op de kern-API). Zie
[`docs/Plugins-schrijven.md`](docs/Plugins-schrijven.md).

---

## Thema's

Thema's zijn JSON, net als talen. Vier zijn meegeleverd (Inkline Licht, Inkline
Donker, Inkline Papier, Inkline Hoog Contrast); eigen thema's komen in
`~/Library/Application Support/Inkline/Themes/`:

```jsonc
{
  "identifier": "mijn-thema",
  "name": "Mijn thema",
  "appearance": "dark",              // bepaalt of hij bij licht of donker hoort
  "colors": {
    "background": "#1E1F22", "foreground": "#E8E8ED", "caret": "#FFFFFF",
    "selection": "#2F5C8F", "inactiveSelection": "#3A3A40", "currentLine": "#26282C",
    "gutterBackground": "#1A1B1E", "lineNumber": "#5E6068", "activeLineNumber": "#E8E8ED",
    "indentGuide": "#33353A", "invisibles": "#44464C", "findHighlight": "#6B5A1F",
    "currentFindHighlight": "#A6851F", "bracketMatch": "#3A4D66", "pageGuide": "#2A2C31",
    "diffInserted": "#1E3225", "diffDeleted": "#3A2224", "bookmark": "#6699FF"
  },
  "scopes": {
    "keyword": "#C678DD",
    "string":  "#98C379",
    "comment": { "color": "#7F848E", "italic": true },
    "heading": { "color": "#61AFEF", "bold": true }
  }
}
```

Een scope mag kort (`"#C678DD"`) of uitgebreid (`{ "color": …, "bold": … }`).
Ontbrekende scopes vallen terug op hun familie: `controlKeyword` volgt
`keyword`, `method` volgt `function`, enzovoort.

---

## Sneltoetsen

| Actie | Toets |
| --- | --- |
| Nieuw bestand / openen / map openen | ⌘N · ⌘O · ⇧⌘O |
| Bewaren / bewaren als / alles bewaren | ⌘S · ⇧⌘S · ⌥⌘S |
| Tabblad sluiten | ⌘W |
| Zoeken / zoeken en vervangen | ⌘F · ⌥⌘F |
| Volgende / vorige treffer | ⌘G · ⇧⌘G |
| Zoeken in bestanden | ⇧⌘F |
| Zoek naar selectie | ⌘E |
| Ga naar regel | ⌘L |
| Ga naar bijbehorend haakje | ⌃⌘B |
| Bladwijzer aan/uit · volgende | ⇧⌘M · ⌥⌘M |
| Regel dupliceren · verwijderen | ⌘D · ⇧⌘K |
| Regel omhoog · omlaag | ⌃⌘↑ · ⌃⌘↓ |
| In-/uitspringen | ⌘] · ⌘[ |
| Commentaar aan/uit · blokcommentaar | ⌘/ · ⌥⌘/ |
| HOOFDLETTERS · kleine letters | ⇧⌘U · ⌥⌘U |
| Macro opnemen/stoppen · afspelen | ⇧⌘R · ⇧⌘P |
| Zijbalk tonen/verbergen | ⌥⌘0 |
| Splitsen naast elkaar | ⌥⌘\ |
| Zoomen in/uit/reset | ⌘+ · ⌘- · ⌘0 |
| Multi-cursor · kolomselectie | ⌘-klik · ⌥-slepen |

---

## Signeren, notariseren en distribueren

Alles zit in `scripts/release.sh`. Het script bouwt, ondertekent, notariseert,
maakt de DMG **en** de Sparkle-ZIP, genereert een ondertekende appcast en maakt
een **draft**-release op GitHub. Publiceren doe je zelf, na controle.

### Eenmalig instellen

1. **Developer ID-certificaat.** Xcode ▸ Settings ▸ Accounts ▸ je Apple-ID ▸
   *Manage Certificates* ▸ **Developer ID Application**. Controleer:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

2. **Notarisatieprofiel** in de Keychain (met een app-specifiek wachtwoord van
   appleid.apple.com):

   ```bash
   xcrun notarytool store-credentials inkline-notary \
     --apple-id "jij@example.com" \
     --team-id "GPYS6SK835" \
     --password "abcd-efgh-ijkl-mnop"
   ```

3. **Team-ID** in `scripts/release.sh` of via `INKLINE_TEAM_ID`.

4. **Sparkle-gereedschap** (`generate_keys`, `generate_appcast`) uit de
   [Sparkle-release](https://github.com/sparkle-project/Sparkle/releases),
   standaard verwacht in `~/Documents/Sparkle/bin` — anders
   `INKLINE_SPARKLE_BIN_DIR` zetten.

### Releasen

```bash
scripts/release.sh            # vraagt om versie en buildnummer
scripts/release.sh 0.2.0 2    # of direct
```

Het script stopt bij de eerste afwijking: ongecommitte wijzigingen, een branch
die achterloopt, een bestaande tag, een privérepository (de feed moet publiek
zijn), een ontbrekend certificaat, een niet-passende Sparkle-sleutel of een
appcast die niet klopt. Wat het doet:

1. versie en buildnummer in `App/project.yml` zetten, committen en pushen;
2. `xcodegen generate` en `swift test`;
3. `xcodebuild archive` + `-exportArchive` met Developer ID;
4. de app notariseren, `stapler staple`, `spctl --assess`;
5. de Sparkle-ZIP maken en opnieuw controleren na uitpakken;
6. de DMG bouwen (met symlink naar `/Applications`), ondertekenen,
   notariseren en stapelen;
7. `generate_appcast` draaien en de uitvoer verifiëren;
8. een GitHub-draft maken met ZIP, DMG en `appcast.xml`.

Handmatig, als je het zonder script wilt doen:

```bash
codesign --force --options runtime --timestamp \
         --entitlements App/Supporting/Inkline.entitlements \
         --sign "Developer ID Application: Naam (TEAMID)" Inkline.app
ditto -c -k --sequesterRsrc --keepParent Inkline.app Inkline.zip
xcrun notarytool submit Inkline.zip --keychain-profile inkline-notary --wait
xcrun stapler staple Inkline.app
```

---

## Sparkle instellen

1. **Sleutelpaar maken** (de private sleutel gaat in de Keychain, de publieke
   wordt afgedrukt):

   ```bash
   ~/Documents/Sparkle/bin/generate_keys
   ```

2. **Publieke sleutel** in `App/Supporting/Info.plist` zetten, in plaats van de
   placeholder:

   ```xml
   <key>SUPublicEDKey</key>
   <string>gbxFgROhkDGw8Tmhvotvm4rCnaFjzUgu/2qDEAyYHMQ=</string>
   ```

   `scripts/release.sh` leest die waarde en weigert te releasen als de private
   sleutel er niet bij hoort — dan zou geen enkele gebruiker de update kunnen
   installeren.

3. **Feed-URL** staat al in `Info.plist` en wijst naar de laatste GitHub-release:

   ```xml
   <key>SUFeedURL</key>
   <string>https://github.com/rorymeijer/Inkline/releases/latest/download/appcast.xml</string>
   ```

   Omdat elke release een nieuwe `appcast.xml` meelevert, wijst
   `releases/latest/download/appcast.xml` altijd naar de actuele feed.

4. **Controleren** na publicatie:

   ```bash
   curl --fail --location --head \
     https://github.com/rorymeijer/Inkline/releases/latest/download/appcast.xml
   ```

In de app zit alles achter `UpdaterController`; **Inkline ▸ Zoeken naar
updates…** en de voorkeuren-tab *Updates* bedienen Sparkle. Is de
Sparkle-package niet aanwezig bij het bouwen, dan compileert de app gewoon en
meldt hij dat deze build geen automatische updates heeft.

---

## App-icoon

**Concept: inkt + regel.** Een diepblauwe, afgeronde tegel; onderin een lichte
basislijn — de "line" uit de naam — met daarop een inktdruppel die er net op
landt, en links een oranje tekstcursor die op dezelfde lijn staat. Inkt voor
schrijven, de lijn voor de regel tekst, de cursor voor de editor. Bij 16 px
blijven druppel en lijn los van elkaar leesbaar.

De placeholder-assets zijn programmatisch gegenereerd en staan in
`App/Resources/Assets.xcassets/AppIcon.appiconset`. Opnieuw genereren of
aanpassen:

```bash
python3 scripts/make-app-icon.py
```

---

## Status en bekende beperkingen

- **Schijfgebruik bij zeer grote bestanden.** Het levende bewerkingsoppervlak
  (`NSTextStorage`) en de kern-`TextBuffer` houden elk een kopie van de tekst.
  Bij een bestand van 100 MB kost dat meer geheugen dan strikt nodig. De weg
  vooruit is een `NSTextStorage` die rechtstreeks op de piece table zit; de
  scheiding in de architectuur is daar al op ingericht.
- **Tree-sitter-grammatica's worden niet meegeleverd.** Zonder dylib valt elke
  taal terug op de regex-highlighter, die voor de meegeleverde talen compleet is.
- **Codevouwen** hangt aan haakjes of inspringing, niet aan de grammatica.
- **Tabbladen losmaken naar een eigen venster** kan nog niet. Herordenen met
  slepen, en verplaatsen naar het andere paneel van de splitsing, kan wel.
- De interface is Nederlandstalig; een Engelse vertaling is een kwestie van een
  tweede locale in `App/Resources/Localizable.xcstrings`.
