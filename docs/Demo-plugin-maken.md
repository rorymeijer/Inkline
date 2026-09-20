# Een demo-plugin maken, stap voor stap

Dit is de kortste route naar een werkende eigen plugin. We maken **Demo**: een
plugin met twee commando's — één die een melding toont, en één die een
datumstempel invoegt op de cursor. Meer niet. Voor de volledige API-uitleg is
er [`Plugins-schrijven.md`](Plugins-schrijven.md); dit document is bedoeld om
in tien minuten iets werkends te hebben.

## Wat je gaat maken

Een plugin is een bundel (`Demo.inklineplugin`) met één Swift-klasse en een
`Info.plist`. Inkline laadt de bundel, roept `activate(host:)` aan, en jouw
commando's verschijnen in het **Plugins**-menu.

## Stap 1 — Mappen en bestanden

Maak naast de drie voorbeeldplugins een eigen map:

```
Plugins/
└── Demo/
    ├── Info.plist
    └── Sources/
        └── DemoPlugin.swift
```

## Stap 2 — De code

`Plugins/Demo/Sources/DemoPlugin.swift`:

```swift
import AppKit
import Foundation
import InklineCore
import InklinePluginAPI

@objc(DemoPlugin)
public final class DemoPlugin: NSObject, InklinePlugin {

    public static let manifest = PluginManifest(
        identifier: "nl.rorymeijer.inkline.plugin.demo",
        name: "Demo",
        version: "1.0",
        summary: "Kleinst mogelijke voorbeeldplugin.",
        capabilities: [.editText, .contributeMenu])

    public override required init() {
        super.init()
    }

    public func activate(host: PluginHost) throws {
        // Commando 1: alleen een melding tonen.
        host.register(command: PluginCommand(identifier: "demo.hallo",
                                             title: "Zeg hallo") { invocation in
            invocation.host.showMessage("Hallo vanuit de demo-plugin!",
                                        style: .informational)
        })

        // Commando 2: tekst invoegen op de plek van de cursor of selectie.
        host.register(command: PluginCommand(identifier: "demo.stempel",
                                             title: "Datumstempel invoegen") { invocation in
            guard let document = invocation.document else {
                throw PluginError.noActiveDocument
            }
            let stempel = ISO8601DateFormatter().string(from: Date())
            document.performGrouped {
                document.replace(range: document.selectedRange, with: stempel)
            }
        })

        // Allebei in het Plugins-menu zetten.
        host.register(menuItem: PluginMenuItem(title: "Zeg hallo",
                                               commandIdentifier: "demo.hallo"))
        host.register(menuItem: PluginMenuItem(title: "Datumstempel invoegen",
                                               commandIdentifier: "demo.stempel"))
    }
}
```

Drie dingen om te onthouden:

- **`@objc(DemoPlugin)` is verplicht** — zo vindt `NSPrincipalClass` uit de
  `Info.plist` je klasse. Zonder die regel laadt de plugin niet.
- **`deactivate()` hoef je niet te schrijven.** Alles wat je via de host
  registreert (commando's, menu-items, panelen), ruimt Inkline zelf op.
- **Bewerkingen in `performGrouped`** vormen samen één undo-stap: één ⌘Z
  maakt het hele commando ongedaan.

## Stap 3 — De Info.plist

`Plugins/Demo/Info.plist` (kopie van een voorbeeldplugin, met eigen namen):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>   <string>nl</string>
    <key>CFBundleExecutable</key>          <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>          <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key>                <string>Demo</string>
    <key>CFBundlePackageType</key>         <string>BNDL</string>
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>NSPrincipalClass</key>            <string>DemoPlugin</string>
    <key>InklinePluginIdentifier</key>     <string>nl.rorymeijer.inkline.plugin.demo</string>
    <key>InklinePluginName</key>           <string>Demo</string>
    <key>InklinePluginSummary</key>        <string>Kleinst mogelijke voorbeeldplugin.</string>
    <key>InklinePluginAPIVersion</key>     <string>1.0</string>
    <key>InklinePluginCapabilities</key>
    <array>
        <string>editText</string>
        <string>contributeMenu</string>
    </array>
</dict>
</plist>
```

`NSPrincipalClass` moet exact de naam uit `@objc(…)` zijn, en
`InklinePluginIdentifier` moet gelijk zijn aan de identifier in je manifest.

## Stap 4 — Target toevoegen aan het project

In `App/project.yml` staan de drie voorbeelden als bundel-targets. Voeg er
onder `targets:` één bij (kopie van `JSONFormatterPlugin`, aangepast):

```yaml
  DemoPlugin:
    type: bundle
    platform: macOS
    sources:
      - ../Plugins/Demo/Sources
    dependencies:
      - package: Inkline
        product: InklineKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: nl.rorymeijer.inkline.plugin.demo
        PRODUCT_NAME: Demo
        WRAPPER_EXTENSION: inklineplugin
        INFOPLIST_FILE: ../Plugins/Demo/Info.plist
        LD_RUNPATH_SEARCH_PATHS:
          - "$(inherited)"
          - "@loader_path/../../../../Frameworks"
        SKIP_INSTALL: YES
```

En laat de app hem meebouwen en insluiten: voeg bij het `Inkline`-target
onder `dependencies:` toe:

```yaml
      - target: DemoPlugin
        embed: true
        codeSign: true
```

Genereer daarna het project opnieuw:

```bash
cd App && xcodegen generate
```

> De `LD_RUNPATH_SEARCH_PATHS`-regel is essentieel: de plugin moet tegen
> dezelfde *dynamische* `InklinePluginAPI`- en `InklineCore`-bibliotheken
> linken als de app. Met een eigen (statische) kopie zou de host je plugin
> niet herkennen.

## Stap 5 — Bouwen en testen

Bouw en start de app vanuit Xcode (⌘R). Omdat de plugin is ingesloten in
`Inkline.app/Contents/PlugIns`, is er verder niets te installeren:

1. Open **Plugins ▸ Plugins beheren…** — daar staat "Demo", aangevinkt.
2. Kies **Plugins ▸ Zeg hallo** — je melding verschijnt.
3. Zet de cursor in een document en kies **Plugins ▸ Datumstempel
   invoegen** — de datum staat in de tekst, en ⌘Z haalt hem weer weg.

Gooit `activate(host:)` een fout, dan crasht er niets: de plugin wordt
overgeslagen en de reden staat in de plugin-beheerder.

## Hoe verder

- **Sneltoets?** Geef `PluginCommand` een `keyEquivalent:` en
  `modifierDescription:` mee (zie de JSON-formatter).
- **Eigen paneel in de zijbalk?** `host.register(panel:)` — zie de
  HexViewer-plugin en [`Plugins-schrijven.md`](Plugins-schrijven.md).
- **Los verspreiden zonder Xcode-target?** Bouw de bundel apart en kopieer
  hem naar `~/Library/Application Support/Inkline/Plugins/`.
- **Testen zonder de app te starten?** `DefaultPluginHost` en
  `BufferPluginDocument` zijn publiek; het testrecept staat onderaan
  [`Plugins-schrijven.md`](Plugins-schrijven.md).
