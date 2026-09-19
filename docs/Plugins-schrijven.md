# Een Inkline-plugin schrijven

Een plugin is een macOS-bundel met de extensie `.inklineplugin`. Inkline zoekt
ze in:

1. `Inkline.app/Contents/PlugIns` (de meegeleverde voorbeelden)
2. `~/Library/Application Support/Inkline/Plugins` (die van jou)

Een plugin van de gebruiker met dezelfde identifier overschrijft een
meegeleverde.

## De levenscyclus

```swift
public protocol InklinePlugin: AnyObject {
    static var manifest: PluginManifest { get }
    init()
    func activate(host: PluginHost) throws
    func deactivate()
}
```

1. Inkline leest `Info.plist` — zonder code te laden — en toont de plugin in de
   beheerder.
2. Staat hij aan, dan wordt de bundel geladen, `NSPrincipalClass`
   geïnstantieerd en `activate(host:)` aangeroepen.
3. Bij uitschakelen of afsluiten volgt `deactivate()`. Commando's, menu-items en
   panelen die via de host zijn geregistreerd, ruimt Inkline zelf op.

Gooit `activate(host:)`, dan wordt de plugin niet geladen en staat de reden in
de beheerder. Eén stukke plugin houdt de app nooit tegen.

## Info.plist

| Sleutel | Verplicht | Betekenis |
| --- | --- | --- |
| `NSPrincipalClass` | ja | Objective-C-naam van je klasse (`@objc(MijnPlugin)`). |
| `InklinePluginIdentifier` | ja | Unieke id; valt terug op `CFBundleIdentifier`. |
| `InklinePluginName` | nee | Naam in de beheerder. |
| `InklinePluginAPIVersion` | ja | Bv. `1.0`. Laadt als de hoofdversie klopt en de minor niet hoger is dan die van de host. |
| `InklinePluginAuthor` / `InklinePluginSummary` | nee | Tonen in de beheerder. |
| `InklinePluginCapabilities` | nee | `editText`, `readFiles`, `writeFiles`, `runProcesses`, `network`, `contributePanel`, `contributeMenu`. Informatief: de gebruiker ziet waar de plugin aan komt. |

Je klasse moet `NSObject` erven en `@objc(Naam)` dragen, anders vindt
`NSPrincipalClass` hem niet.

## Wat de host biedt

```swift
public protocol PluginHost: AnyObject {
    var apiVersion: PluginAPIVersion { get }
    var activeDocument: PluginDocument? { get }
    var openDocuments: [PluginDocument] { get }

    func register(command: PluginCommand)
    func register(menuItem: PluginMenuItem)
    func register(panel: PluginPanelDescriptor)
    func showPanel(identifier: String)

    func storageDirectory(forPlugin identifier: String) -> URL
    func showMessage(_ message: String, style: PluginMessageStyle)
    func log(_ message: String)
    func performOnMainThread(_ body: @escaping () -> Void)
}
```

Een geregistreerd commando komt in het Plugins-menu, in de commandoregistry en
daarmee ook binnen bereik van het macrosysteem: een macro kan
`.command("mijnplugin.doeiets")` opnemen en afspelen.

## Wat een document biedt

```swift
public protocol PluginDocument: AnyObject {
    var fileURL: URL? { get }
    var displayName: String { get }
    var languageIdentifier: String? { get }
    var text: String { get }
    var length: Int { get }
    var selectedRange: Range<Int> { get set }     // UTF-16-offsets
    var selectedRanges: [Range<Int>] { get }

    func string(in range: Range<Int>) -> String
    func replace(range: Range<Int>, with replacement: String)
    func performGrouped(_ body: () -> Void)       // één undo-stap
    func lineNumber(at offset: Int) -> Int
    func offsetOfLineStart(_ line: Int) -> Int
}
```

Plus `selectedText` en `replaceSelectionOrAll(with:)` als gemak. Alle offsets
zijn UTF-16-eenheden, net als in `NSRange`.

Bewerkingen lopen via dezelfde undo-manager als het typen van de gebruiker: na
een plugin-commando doet ⌘Z wat je verwacht. Meerdere bewerkingen hoor je in
`performGrouped` te zetten, zodat ze samen één stap vormen.

## Een paneel toevoegen

```swift
host.register(panel: PluginPanelDescriptor(identifier: "mijnplugin.paneel",
                                           title: "Mijn paneel",
                                           symbolName: "wand.and.stars",
                                           placement: .rightSidebar,
                                           preferredSize: 300) {
    MijnPaneelView()          // een NSView
})
```

`makeView` draait op de hoofdthread, de eerste keer dat het paneel getoond
wordt. `host.showPanel(identifier:)` brengt het naar voren.

## De kern gebruiken

`InklineCore` is onderdeel van de API: `TextTransforms`, `SearchEngine`,
`PieceTable`, `ColumnEditor`, `DiffEngine` en `FileLoader` mag je vrij
gebruiken. Dat scheelt code en zorgt dat jouw plugin zich precies zo gedraagt
als de ingebouwde commando's.

## Bouwen

In `App/project.yml` staan de drie voorbeelden als bundel-targets; kopieer er
één. Belangrijk:

```yaml
WRAPPER_EXTENSION: inklineplugin
LD_RUNPATH_SEARCH_PATHS:
  - "$(inherited)"
  - "@loader_path/../../../../Frameworks"
```

De plugin linkt tegen dezelfde **dynamische** `InklinePluginAPI`- en
`InklineCore`-bibliotheken als de app. Dat is essentieel: bij een statische
kopie zou je plugin een eigen, onverenigbaar `InklinePlugin`-protocol hebben en
zou de cast in de host mislukken.

Los bouwen kan ook; kopieer de bundel daarna naar
`~/Library/Application Support/Inkline/Plugins/` en zet hem aan in
**Plugins ▸ Plugins beheren…**.

## Testen

`DefaultPluginHost` en `BufferPluginDocument` zijn publiek, dus een plugin is
zonder draaiende app te testen:

```swift
let registry = CommandRegistry()
let host = DefaultPluginHost(registry: registry, storageRoot: tijdelijkeMap)
let document = BufferPluginDocument(buffer: TextBuffer(text: "{\"a\":1}"))
host.documentProvider = { document }

try host.withActivePlugin(MijnPlugin.manifest.identifier) {
    try MijnPlugin().activate(host: host)
}
try registry.perform("mijnplugin.doeiets", context: CommandContext(document: nil))
XCTAssertEqual(document.text, "…")
```

`Tests/InklinePluginAPITests/PluginAPITests.swift` doet dit voor een
voorbeeldplugin, inclusief in- en uitschakelen en versiecontrole.
