# Een demo van Inkline maken

Een goede demo laat in twee minuten zien wat Inkline is: licht, snel,
uitbreidbaar. Dit document beschrijft hoe je zo'n demo voorbereidt, welk
script je volgt, en hoe je hem opneemt en verwerkt tot een video of GIF voor
de README of een release-aankondiging.

## Vorm kiezen

| Vorm | Wanneer | Lengte |
| --- | --- | --- |
| GIF in de README | Eén feature laten zien (bv. Find in Files) | 5–15 s |
| Video (MP4) | Release-aankondiging, website | 1–2 min |
| Live presentatie | Meetup, collega's | 5–10 min |

Voor een GIF geldt: één feature per GIF. Een GIF van een hele rondleiding is
te groot en te druk.

## Voorbereiding

### 1. Een schone staat

Demo's ogen het best zonder jouw eigen sessie, thema's en plugins. Zet de
huidige staat opzij (en na afloop terug):

```bash
# Inkline eerst afsluiten!
mv ~/Library/Application\ Support/Inkline ~/Library/Application\ Support/Inkline.backup
defaults delete nl.rorymeijer.inkline 2>/dev/null || true
```

Terugzetten na de demo:

```bash
rm -rf ~/Library/Application\ Support/Inkline
mv ~/Library/Application\ Support/Inkline.backup ~/Library/Application\ Support/Inkline
```

### 2. Een demo-map

Maak een map met bestanden die de features laten zien die je wilt tonen.
Een goede basisset:

```
demo/
├── server.swift        syntaxkleuring, code folding, symbolenpaneel
├── config.json         JSON — voer voor de JSONFormatter-plugin
├── logboek.txt         veel regels — voer voor zoeken, sorteren, macro's
├── data.csv            kolommen — voer voor kolomselectie en ColumnTools
├── oud.txt / nieuw.txt twee versies — voer voor de vergelijk-weergave
└── README.md           Markdown-kleuring
```

Tips voor de inhoud:

- `logboek.txt`: honderden regels met een herkenbaar patroon
  (`2026-09-20 12:34:56 [ERROR] …`), zodat zoeken-met-regex en een macro
  visueel iets doen.
- `config.json`: bewust onnet geformatteerd (alles op één regel), zodat
  **Plugins ▸ JSON formatteren** een duidelijk voor/na geeft.
- `oud.txt`/`nieuw.txt`: een paar regels verschil, niet meer — de diff moet
  in één oogopslag leesbaar zijn.

### 3. Het venster

- Zet het venster op een vaste, niet te grote maat; 1280 × 800 leest goed en
  houdt GIF's klein.
- Kies één thema en blijf erbij (wissel hoogstens één keer, als dát je punt
  is). Inkline Donker leest het best op video.
- Zoom het lettertype één of twee stappen in (⌘+): wat op jouw scherm
  comfortabel is, is in een video te klein.
- Verberg meldingen: Systeeminstellingen ▸ Focus ▸ Niet storen aan.

## Het demo-script

De volgorde hieronder bouwt op: elk onderdeel gebruikt wat het vorige liet
zien. Schrap wat je niet nodig hebt; de volgorde blijft werken.

1. **Openen.** Sleep de map `demo/` op het venster — de bestandsverkenner
   verschijnt in de zijbalk. Open `server.swift`: syntaxkleuring, regelnummers,
   inspringhulplijnen. Klap een functie dicht (code folding) en toon het
   symbolenpaneel in de zijbalk.
2. **Zoeken.** ⌘F in `logboek.txt`, zoek incrementeel, zet regex aan en zoek
   `\[ERROR\]`. Klik "Alles selecteren" — multi-cursor op elke treffer — en
   typ er iets voor. Eén ⌘Z maakt alles ongedaan.
3. **Find in Files.** ⇧⌘F, zoek over de hele demo-map, klik een resultaat in
   het paneel en land op de juiste regel.
4. **Kolommen.** Open `data.csv`, ⌥-sleep een blokselectie, typ in alle
   regels tegelijk. Eventueel: **Plugins ▸ ColumnTools** voor een
   getallenreeks.
5. **Macro.** ⇧⌘R, doe twee of drie bewerkingen op een logregel (zoek,
   bewerk, volgende regel), ⇧⌘R om te stoppen, ⇧⌘P om af te spelen — en dan
   "herhalen tot einde bestand". Dit is het moment dat kijkers overtuigt.
6. **Plugins.** Open `config.json`, **Plugins ▸ JSON formatteren**: voor/na.
   Open daarna **Plugins ▸ Plugins beheren…** kort in beeld, zodat te zien is
   dat het echte, uitschakelbare plugins zijn.
7. **Splitsen en diff.** ⌥⌘\ voor twee panelen naast elkaar, hetzelfde
   bestand, gesynchroniseerd scrollen. Daarna de vergelijk-weergave met
   `oud.txt` en `nieuw.txt`.
8. **Afsluiter: sessieherstel.** Sluit de app met een niet-bewaard bestand
   open, start opnieuw: alles staat er weer — tabs, cursor, ook de
   niet-bewaarde tekst. Sterk slot, want het is in drie seconden getoond.

Voor een korte GIF pak je één nummer uit deze lijst; 5 (macro) en 8
(sessieherstel) zijn de dankbaarste.

## Opnemen

Het ingebouwde schermopname-paneel van macOS is voldoende: **⇧⌘5**, kies
"Neem geselecteerd gedeelte op" en trek het kader precies om het
Inkline-venster. Zet in Opties "Toon muisklikken" aan en de microfoon uit
(tenzij je voice-over doet).

- Oefen het script één keer droog; opnemen gaat daarna in één take.
- Beweeg de muis rustig en met doel; parkeer hem als je typt.
- Typ sneltoetsen rustig na elkaar, niet gehaast — kijkers moeten het
  effect kunnen koppelen aan de actie.
- Laat na elke feature een tel rust voordat je verder gaat; dat zijn ook
  je knippunten.

## Nabewerken

De opname is een `.mov`. Omzetten met [ffmpeg](https://ffmpeg.org)
(`brew install ffmpeg`):

```bash
# MP4 voor een release-pagina of website
ffmpeg -i demo.mov -vcodec h264 -crf 23 -preset slow -an demo.mp4

# GIF voor de README: eerst een palet, dan de GIF (kleiner en mooier)
ffmpeg -i macro.mov -vf "fps=12,scale=960:-1:flags=lanczos,palettegen" palet.png
ffmpeg -i macro.mov -i palet.png \
  -filter_complex "fps=12,scale=960:-1:flags=lanczos[x];[x][1:v]paletteuse" macro.gif
```

Richtlijnen: een README-GIF onder de 5 MB houden (korter knippen of
`fps=10`/`scale=800` proberen als hij te groot is), en een MP4 zonder audio
opslaan (`-an`) tenzij er voice-over is.

In de README opnemen:

```markdown
![Macro opnemen en afspelen](docs/media/macro.gif)
```

Zet media in `docs/media/`, dan blijven de paden in de README en op GitHub
allebei kloppend.

## Checklist voor je publiceert

- [ ] Geen persoonlijke bestandsnamen, paden of gegevens in beeld
      (denk aan de recent-geopend-lijst en de bestandsverkenner).
- [ ] Versienummer in beeld klopt met de release waar de demo bij hoort.
- [ ] GIF's spelen goed af op GitHub (even in een draft-PR bekijken).
- [ ] Eigen staat teruggezet (zie [Voorbereiding](#1-een-schone-staat)).
