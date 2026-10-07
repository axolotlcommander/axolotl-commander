# Etapa 6 — prohlížeč F3 a editor F4 (zadání)

Vzor: `../tandemcommander/features/viewer.md`, nápověda `viewer_*.htm`, `basicwork_view.htm`,
`basicwork_edit.htm`. Krok 6 v `../tandemcommander/docs/macos-port/04-kroky.md`.

## Chování
- **F3** otevře vlastní prohlížeč v samostatném okně (víc oken najednou smí být). Obrázky, PDF,
  audio/video a složky dál Quick Look (vlastní prohlížeče podle typu jsou etapa 10).
  Quick Look zůstává na ⌘Y a nově i ⌥F3 (alternativní prohlížeč jako Alt+F3 ve Windows).
- Režim **Text / Hex** (⌘1 nebo F5 / ⌘2 nebo F4); automaticky: binární soubor → Hex.
- **Kódování** se určí jednou pro celý soubor: BOM → heuristika UTF-16 bez BOM (ASCII text v UTF-16
  je zároveň platné UTF-8, proto dřív) → celý soubor platné UTF-8 → heuristika Windows-1250/ISO-8859-2 → výchozí kódování z nastavení. Přepínač v okně (popup
  ve stavovém řádku + menu Zobrazit → Kódování), F8/⇧F8 další/předchozí, „Nastavit jako výchozí“.
  Ukazuje se vždy skutečně použité kódování. Přepnutí nikdy nesahá na soubor.
- Text: zalamování ⌃W, hledání ⌘F (systémový find bar), ⌘G/⌘⇧G další/předchozí, ⌘L jdi na řádek,
  ⌘C, ⌘A, ⌘+/⌘−/⌘0 velikost písma, ⌘R znovu načíst, ⌘S uloží výběr (nebo celý text) do souboru.
- Hex: 16 bajtů na řádek, offset, hex, znaky (podle jednobajtového kódování), hledání textu nebo
  hex bajtů, ⌘L jdi na offset (desítkově, `0x…`, `$…`, `…h`), výběr myší, ⌘C zkopíruje hex.
- Další soubory panelu: mezerník další, ⌫ předchozí, ⌃mezerník/⌃⌫ další/předchozí vybraný,
  ⇧⌫ první, ⇧mezerník poslední. Seznam je snímek panelu v okamžiku otevření.
- Esc zavře prohlížeč; kurzor v panelu zůstane. Titulek = celé jméno, podtitulek = složka,
  proxy ikona (representedURL).
- Velké soubory: data mapovaná (`.alwaysMapped`), hex virtualizovaný (kreslí jen viditelné řádky),
  text dekóduje nejvýš 64 MiB (zbytek jen v Hex, oznámí se ve stavovém řádku).
- **F4** otevře soubor pod kurzorem v editoru z nastavení (výchozí TextEdit). **⇧F4** se zeptá na
  jméno, v adresáři panelu založí prázdný soubor (existující jen otevře), kurzor na něj, otevře editor.

## Jádro (`Sources/CommanderCore/Viewer/`) — rozhraní
Viz zadání subagenta v transcriptu; soubory `TextEncoding.swift`, `EncodingDetector.swift`,
`HexFormat.swift`, `ByteSearch.swift`, `FileSequence.swift`, testy `Tests/CommanderCoreTests/ViewerTests.swift`.
