# Změny

Formát vychází z [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); verze se řídí
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.9.0] - 2026-10-16

### Přidáno

- Vyjmout soubory (⌘X, také ⌃X) dá označené soubory do schránky; až do vložení jsou zašedlé a Vložit
  soubory (⌘V) je pak přesune místo kopírování. Zkopírováním nebo vyjmutím něčeho jiného vyjmutí končí.
  Finder vyjmuté soubory zkopíruje, protože macOS vyjímání souborů, kterému by Finder rozuměl, nemá.
- Duplikovat (⌘D) vytvoří kopii vedle položky s názvem jako ve Finderu: „zpráva kopie.pdf“, „zpráva kopie
  2.pdf“ a tak dál.
- Přejít → Plocha (⇧⌘D), Dokumenty (⇧⌘O), Stažené soubory (⌥⌘L) a Aplikace.
- Záložky mají i obvyklé zkratky Macu: ⌘T otevře novou záložku, ⇧⌘] a ⇧⌘[ přejdou na další a předchozí
  záložku.

## [0.8.0] - 2026-10-15

### Přidáno

- Písma: Nastavení → Vzhled → Písma vybírá písmo (rodinu, řez
  a velikost) seznamu souborů a hlavního okna, každé zvlášť, ve standardním panelu Písma a výsledek je
  vidět hned. Písmo seznamu souborů platí pro řádky, záhlaví sloupců, stavový řádek pod panelem,
  Historii složek a nabídku oblíbených cest; písmo hlavního okna pro lištu svazků, řádek disku, cestu,
  záložky, příkazovou řádku a funkční klávesy. Řádky i lišty rostou s písmem; „Výchozí“ a „Obnovit
  výchozí písma“ vrátí obvyklý vzhled. Zobrazit → Větší, Menší a Výchozí písmo seznamu souborů mění
  velikost z klávesnice (klávesy lze přiřadit v Nastavení → Klávesnice).
- Hledat soubory: dvojklik nebo Return na výsledku přejde na
  soubor v panelu a pod výsledky jsou tlačítka F3 Zobrazit, F4 Upravit, Nové hledání, Přejít na
  soubor a Výsledky do panelu. Po přechodu na soubor se okno hledání schová a Hledat soubory ho vrátí
  i s výsledky a s označeným hledaným textem, který stačí přepsat (Nastavení → Obecné → Po přechodu na soubor; „Nechat okno hledání otevřené“ zachová
  dosavadní chování). Hledat soubory v novém okně… spustí další hledání vedle; Otevřít zůstává na ⌘O.

### Opraveno

- Dělítko mezi panely se samo posouvalo a po přetažení skákalo zpět: dlouhý název souboru pod kurzorem
  nebo dlouhý název složky v záložce rozšířil svůj panel. Panely teď drží šířku nastavenou dělítkem,
  i po dalším spuštění.
- Hledat soubory: v úzkém okně byl formulář po obou stranách oříznutý a Další volby vytlačily
  tlačítko Hledat z dohledu. Okno už nejde zúžit pod šířku formuláře, v žádném jazyce.

## [0.7.2] - 2026-10-15

### Opraveno

- Aplikace mohla na sekundy i minuty přestat reagovat, když externí disk spal nebo byl zaneprázdněný
  zálohou Time Machine, případně když síťový disk přestal odpovídat. Seznam svazků, svazek složky
  v panelu, ikony svazků i sledování složky se teď čtou na pozadí, takže pohyb kurzoru ani nabídka
  svazků na disk nikdy nečekají. Totéž platí pro ikony aplikací a balíčků na jiných discích, tlačítka
  svazků, Informace o svazku…, nabídku Otevřít v aplikaci, nabídku cílů u kopírování a přesunu,
  zadání nového názvu pro soubor, který už existuje, a obnovení panelu, jehož složka zmizela.
- Informace o svazku… a nabídka svazků ukazovaly u síťových disků 0 kB volného místa.

## [0.7.1] - 2026-10-15

### Opraveno

- Kopírování, přesun a přejmenování na síťových discích (SMB) a discích exFAT selhávalo s hláškou
  „Operation not supported“. Tyto svazky neumí přejmenovat bez přepsání, takže aplikace teď nejdřív
  ověří, že je název volný, a pak přejmenuje běžným způsobem.

## [0.7.0] - 2026-10-14

### Přidáno

- Soubor → Rozdělit soubor… rozdělí soubor na části zvolené velikosti (25 MB pro e-mail, CD, DVD, limit
  FAT32 nebo libovolná velikost zadaná s k, M nebo G) pojmenované `jméno.001`, `jméno.002`, … a volitelně
  zapíše soubor s kontrolním součtem `jméno.crc`. Soubor → Spojit soubory… takové části znovu spojí — od
  kterékoli části, od souboru `.crc` nebo z označených souborů — a výsledek ověří podle kontrolního součtu.
  Obojí zapisuje ve výchozím stavu do složky druhého panelu, předem zkontroluje volné místo a po zrušení
  nic nenechá.
- Soubor → Zakódovat soubor… převede soubory na text (Base64 s názvem souboru v malé hlavičce MIME nebo
  UUE) a Soubor → Dekódovat soubor… takový text převede zpět na soubory: přílohy uložených e-mailů (`.eml`,
  i vnořené a s kódovanými názvy), UUE, XXE, BinHex 4.0 a čisté Base64, rozpoznané podle obsahu. Označené
  kusy se spojí podle názvu; názvy z textu nikdy neopustí cílovou složku a poškozená nebo neúplná data se
  nahlásí.

### Změněno

- Nové záložky se přidávají za poslední záložku, ne za aktivní — i duplikovaná záložka a složka otevřená
  ze zamčené záložky. Nastavení → Panely → „Otevírat nové záložky vedle aktuální“ vrátí původní umístění.

## [0.6.0] - 2026-10-14

### Přidáno

- Označování myší: ⌃-klik nebo ⌘-klik označí či odznačí jednu položku, ⇧-klik označí rozsah od
  kurzoru (dosavadní označení zmizí), ⌃⇧-klik nebo ⌘⇧-klik přidá další rozsah a obyčejný klik začne
  znovu (⌃W vrátí označení zpět). Tažení z prázdného místa nakreslí obdélník, který označí položky,
  jichž se dotkne (s ⇧ přidává, s ⌃/⌘ přepíná), a na okraji posouvá seznam. V Podrobném zobrazení
  se přetahování souborů (drag & drop) spouští z ikony nebo z názvu.
- Nastavení → Panely → „Pravé tlačítko myši označuje (styl Norton Commanderu)“: pravý klik označuje,
  tažení pravým tlačítkem označí položky, přes které prochází, a podržení pravého tlačítka otevře
  kontextové menu.
- Zobrazení → Náhledy (⌃⌥3; ve schématu Klasický Commander také ⌃⇧F1): mřížka náhledů s názvy pod nimi,
  které vytváří macOS pro obrázky, PDF, videa, dokumenty a další; načítají se na pozadí pro viditelné
  buňky a drží se jen v paměti. Tři velikosti v Nastavení → Panely; ⌘+ / ⌘−, ⌘ + kolečko myši nebo
  gesto přiblížení je mění, dokud je zobrazení zapnuté. Archivy, servery a Síť ukazují jen ikony.
- Co je nového: po aktualizaci aplikace jednou ukáže, co se změnilo oproti verzi, která běžela dřív.
  Nápověda → Co je nového…, okno O aplikaci a Nastavení → Obecné otevřou poznámky ke všem verzím.
  Poznámky jsou česky, když aplikace běží česky.
- Aktualizace: aplikace jednou denně zkontroluje, zda nevyšla novější verze (v Nastavení → Obecné se dá
  vypnout a je tam Zkontrolovat; dále Axolotl Commander → Zkontrolovat aktualizace… a okno O aplikaci).
  Nalezená verze se ukáže jako malé tlačítko „↑ Verze X.Y.Z“ v titulkovém pruhu, nic nevyskakuje. Okno
  aktualizace ukáže, co nová verze přináší, česky, když aplikace běží česky; Nainstalovat a spustit znovu
  ji stáhne, ověří kontrolní součet a podpis, dá ji na místo běžící aplikace (stará jde do Koše)
  a spustí ji. Běžící operace se soubory se nikdy nepřeruší. Připomenout později a Přeskočit tuto verzi
  tlačítko skryjí; když se aplikace nemůže aktualizovat sama, řekne proč a nabídne Stáhnout….
- Zamykání záložek: Zamknout záložku drží záložku na její složce a každá změna složky v ní otevře
  novou záložku hned za ní; Zamknout s možností změny složky dovolí v záložce procházet a vrátí ji na
  její složku pokaždé, když se do ní vrátíte (i po spuštění). Zamčená záložka má vlevo zámek (při
  najetí myší ×) a její bublina ukazuje zamčenou složku. Zavřít ostatní záložky a Zavřít
  záložky vpravo zamčené záložky nechají otevřené; Znovu otevřít zavřenou záložku vrátí i zámek;
  vysunutí disku nebo odpojení serveru jeho záložky odemkne.
- Menu záložky (pravý klik na záložku) a menu Přejít mají nově Duplikovat záložku, Kopírovat záložku do
  druhého panelu, Zavřít záložky vpravo a oba příkazy zamykání; menu záložky má i Znovu otevřít
  zavřenou záložku.
- Pruh záložek končí tlačítkem „+“ pro novou záložku. Záložky si drží čitelnou šířku: ty, které se
  nevejdou, jsou v menu „»“ a aktivní záložka zůstává vždy vidět. Nastavení → Panely → „Vždy zobrazovat pruh
  záložek“ nechá pruh (i „+“) zobrazený i s jedinou záložkou.
- Každé vydání na GitHubu popisuje změny anglicky i česky.

### Změněno

- Nastavení: volby panelů (mezerník, psaní, ⌃← / ⌃→, tlačítka disků, pravé tlačítko myši, velikost
  náhledů) mají vlastní záložku Panely místo oddílu v Obecných.

### Opraveno

- Přetahování označených položek v Podrobném zobrazení: tažení z označeného řádku se nespustilo; nyní
  nese všechny označené položky.
- Přetažení na ikonu složky (v Podrobném i Stručném zobrazení) bylo odmítnuto; nyní se soubory vloží do
  složky stejně jako při přetažení na její název.
- Dlouhé popisy v Nastavení se zalamují místo zakončení „…“; záložka vyšší než okno se posouvá místo
  toho, aby zasunula záložky pod titulek okna.

## [0.5.0] - 2026-10-13

### Přidáno

- Dotaz na nahrazení označí novější a větší soubor; F3 / ⇧F3 otevřou stávající / nový soubor
  v prohlížeči a ⌥F3 je porovná, i u souborů v archivech a na serverech.
- Další… v dotazu na nahrazení: Přepsat všechny starší, Přejmenovat…, Přejmenovat automaticky
  („x 2.txt“) a Přejmenovat všechny automaticky.
- Dialog F5/F6 má menu cílů (tlačítko nebo ⌥↓) s druhým panelem, záložkami, oblíbenými cestami
  a posledními 10 cíli; ⌃D otevře oblíbené cesty přímo.
- Při kopírování nebo přesouvání jedné položky se její název vloží do pole „Do:“, takže ji lze cestou
  přejmenovat; F5/F6 opět vybere název, příponu, složku nebo celý text.
- Vysunout svazek (⌘E) vysune svazek aktivního panelu (nebo odpojí jeho server); vysunutelné svazky
  mají v liště disků ⏏ a pravý klik na svazek nabídne Vysunout a Informace o svazku…. Odpojit… (F12)
  nově uvádí také síťové svazky a vysunutelné disky. Panely na daném svazku nejprve přejdou do domovské
  složky a nic se nevysune, dokud svazek používá některá z operací aplikace.
- Synchronizovat složky… (⌥⇧F10, menu Příkazy) porovná stromy složek obou panelů podle data,
  velikosti nebo obsahu a vypíše, v čem se liší, se směrem každého kopírování. Mezerník, ← a →
  mění jednotlivé položky, F3 porovná dva soubory a nic se nezkopíruje, dokud není potvrzen přehled.
  Jednosměrná synchronizace může také přesunout nadbytečné položky do Koše (ve výchozím stavu vypnuto).
- Prohlížeč (F3) zobrazuje JSON formátovaně: odsazený a zvýrazněný, klíče v pořadí souboru, hodnoty
  přesně jak jsou zapsány, s obvyklým hledáním, kopírováním a zalamováním; komentáře, čárky na konci
  a JSON Lines fungují a poškozený JSON se otevře jako text s místem první chyby.
- Kresby SVG se v prohlížeči otevřou jako obrázky (se zvětšením) místo Quick Look, bez spouštění
  skriptů a bez načítání čehokoli z internetu.
- Zvukové a video soubory, které Mac přehraje, se v prohlížeči otevřou s přehrávačem: Return spouští
  a pozastavuje, ← → přetáčejí, ↑ ↓ mění hlasitost a mezerník stále přechází na další soubor.
- Barevné zvýraznění syntaxe pro F#, Razor (.cshtml, .razor), soubory řešení (.sln) a soubory MSBuild
  (.props, .targets, .fsproj, .vbproj, .nuspec).

### Změněno

- Menu Vlevo a Vpravo zmizela: Svazek vlevo… (⌥F1) a Svazek vpravo… (⌥F2) jsou v menu Přejít.
- Šipky v dotazu s tlačítky (například v dotazu na nahrazení při kopírování) posouvají výchozí
  tlačítko, takže Return stiskne vybrané; Esc stále ruší.
- ⇧F2 porovná panely hned s uloženými volbami (Porovnat panely); ⌃F10 nejdřív otevře
  volby (Porovnat panely…).
- Nastavení → Vzhled může vypnout tučné písmo vybraných položek (vedle jejich barvy).

### Opraveno

- Prohlížeč otevírá soubory s velmi dlouhými řádky (například minifikovaný JSON o desítkách MB) během
  vteřin místo minut a gigabajtů paměti: řádky delší než 10 000 znaků se dělí jen na obrazovce,
  zatímco hledání, kopírování, ukládání a Přejít na řádek pracují s původním textem.
- Kliknutí kamkoli na panel z něj udělá aktivní panel, nejen kliknutí na soubor: stačí prázdné řádky
  pod posledním souborem, mezery a informační řádek, záhlaví sloupce i záložka. Kliknutím do panelu
  se také vrátí klávesnice od příkazového řádku.
- Vysvětlivka v Porovnat panely se zalamuje místo oříznutí.
- Interpolovaný řetězec C# (`$"…"`) v prohlížeči končí u koncové uvozovky místo obarvení zbytku
  řádku.

## [0.4.0] - 2026-10-13

### Přidáno

- Další výchozí zkratky z klasických dvoupanelových správců souborů vedle stávajících (spec
  010):
  - ⌥← / ⌥→ zpět a vpřed;
  - ⌃← / ⌃→ otevřít v levém / pravém panelu;
  - ⌃F1 Stručné zobrazení, ⇧F2 Porovnat panely, ⇧F6 Přejmenovat, ⌥F9 Rozbalit;
  - ⌃R obnovit, ⌃A vybrat vše, ⌃C / ⌃V kopírovat a vložit soubory, ⌃I přepnout panel, ⌃D oblíbené cesty;
  - ⌃F a ⌃N Připojit k serveru, ⌃⇧B zobrazení větve vybraných položek;
  - ⌥↩ Informace, ⌥⇧↩ velikosti složek;
  - ⌥Num+ / ⌥Num− vybrat / zrušit výběr se stejnou příponou;
  - ⌃J a ⌃P vloží do příkazového řádku název a cestu panelu.
- ⌃⇧↩ vloží do příkazového řádku úplnou cestu položky pod kurzorem (⌃↩ stále vkládá její
  název).
- Nastavení → Klávesnice → Schéma kláves: „Klasický Commander“ změní klávesy, které v aplikaci
  znamenají něco jiného:
  - ⌃T / ⌃W otevřou a zavřou záložky, ⌃⇥ / ⌃⇧⇥ mezi nimi přecházejí;
  - ⌃F2 je Podrobné zobrazení;
  - ⌥F3 je Zobrazit pomocí, ⌥F4 ukončí aplikaci;
  - ⌃⇧F odpojí, ⌃⇧F5 vytvoří symbolický odkaz.

  Vaše vlastní změny zkratek zůstávají nad schématem. Tabulka ukazuje, odkud každá zkratka pochází,
  a Výchozí se vrátí ke schématu.
- Exportovat nastavení… a Importovat nastavení… (menu aplikace a Nastavení → Obecné) uloží celé
  nastavení do jednoho souboru JSON a zase je načtou: klávesy, předvolby, vzhled, oblíbené cesty,
  uživatelské menu, uložené servery a panel nástrojů. Hesla nejsou nikdy zahrnuta. Import umožňuje vybrat
  části a ohlásí vše, co přeskočil.
- Nastavení → Obecné → Panely: čtyři volby chování, každá nezávislá na schématu kláves (spec 011):
  - Mezerník posune kurzor dolů (ve výchozím stavu zapnuto; vypnuto nechá kurzor na označené položce);
  - Psaní jde do příkazového řádku: znaky napsané v panelu naplní příkazový řádek, zatímco panel
    drží fokus; je-li v řádku text, Return jej spustí, Backspace a Esc jej upravují a ⌥ +
    znak spustí rychlé hledání;
  - ⌃← / ⌃→ změní panel, na který šipka ukazuje, a „..“ otevře složku druhého panelu;
  - Tlačítka disků otevřou složku druhého panelu na daném svazku nebo naposledy použitou složku;
    tlačítko svazku, na kterém panel je, obnoví jeho složku, když je druhý panel jinde.
- Záložky z klávesnice (spec 012), vše v menu Přejít a Zobrazení:
  - Otevřít v nové záložce (⌃↑, ⌥⌘↓), Otevřít v záložce na pozadí (⌥⌘⇧↓) a Otevřít v nové záložce
    druhého panelu (⌃⇧↑) otevřou složku pod kurzorem, aniž byste opustili aktuální záložku;
  - Znovu otevřít zavřenou záložku (⌘⇧T) a Seznam záložek… (⌘⇧\, ⌃⇧A), který nabízí i nedávno
    zavřené záložky;
  - Zavřít ostatní záložky (⌥⌘W; ⌃⇧W v Klasickém Commanderu) a Prohodit panely i se záložkami (⌃⇧U).
- Rychlý filtr (⌥⌘F; ⌃S v Klasickém Commanderu): napsaný text zužuje seznam panelu během psaní, jako
  podřetězec nebo maska například `*.txt`. Šipky se pohybují mezi shodami a Esc znovu ukáže vše.
  Rychlý filtr s posledním textem (⌃⇧S, ⌥⌘⇧F) vrátí poslední filtr a Rychlý filtr během
  rychlého hledání změní hledání na filtr. Označené položky, které filtr skryje, se z příkazů
  vynechají (spec 013).
- Přejít → Historie složek… (⌃⌘H; v Klasickém Commanderu také ⌥↓) uvádí složky, které panel navštívil,
  a nedávno napsané cesty; psaním se seznam filtruje. Return složku otevře, ⌘Return ji otevře v nové
  záložce a ⌥Return v druhém panelu. Příkazy → Historie příkazové řádky… (⌥F8) uvádí provedené
  příkazy; vybraný se vloží do příkazového řádku bez spuštění (spec 014).
- Drobné příkazy (spec 015):
  - Soubor → Kopírovat jako… (⇧F5) zkopíruje položku pod kurzorem vedle ní pod novým názvem;
  - Soubor → Nová složka v druhém panelu… (⌥⌘N; ⇧F7 v Klasickém Commanderu) nabídne název položky pod kurzorem;
  - Soubor → Zobrazit jen soubor pod kurzorem (⌥⇧F3; v Klasickém Commanderu také ⇧F3) ignoruje označené soubory;
  - Soubor → Zabalit a přesunout… (⌥⇧F5) zabalí a poté přesune originály do Koše;
  - Soubor → Otestovat archivy (⌥⇧F9) přečte označené archivy celé a ohlásí poškozené;
  - Upravit → Označit všechny soubory / Odznačit všechny soubory (⌃⇧Num+ / ⌃⇧Num−) nechávají složky být;
  - ⌥⇧↑ označí nebo odznačí bez posunu kurzoru, ⌃⇧J vloží úplnou cestu do příkazového řádku;
  - v Klasickém Commanderu ⌃L spočítá velikost označených položek.
- Zobrazení → Panel rychlého náhledu (⌃Q): druhý panel ukazuje náhled položky pod kurzorem a sleduje
  kurzor; ⌃Q znovu, Tab nebo klik na něj panel vrátí (spec 016).
- Nastavení → Obecné → Tlačítka na liště: zaškrtávací políčka F1–F12 určují, která tlačítka
  lišta funkčních kláves ukazuje; klávesa s vypnutým tlačítkem stále funguje. Tlačítko je široké
  nejvýše 140 bodů, takže několik tlačítek stojí vlevo a nevyplňuje celou lištu. Kontextové menu
  lišty má Vybrat tlačítka… (spec 017).
- Lišta tlačítek (spec 018): řada tlačítek s ikonami pro libovolný příkaz aplikace nebo program (s
  proměnnými uživatelského menu), nahoře nebo dole za funkčními klávesami; Zobrazení → Zobrazit
  lištu tlačítek, Nastavení → Lišta tlačítek (tlačítka, pořadí, oddělovače, SF Symbols nebo ikony
  aplikací) a pravý klik na liště. Tlačítka, která se nevejdou, se přesunou do menu ». Ve výchozím
  stavu vypnuto, s několika ukázkovými tlačítky.

- Řádek disku pod lištou disků každého panelu (spec 020): výběr disku se stejným seznamem jako
  ⌥F1/⌥F2 a volné a celkové místo na disku panelu („273.9 GB free of 994.7 GB“); klik na
  místo otevře Informace o svazku. Je-li řádek skrytý, volné místo se přesune na pravý konec
  lišty disků, případně stavového řádku, pokud je skrytá i lišta disků (Nastavení → Obecné; Zobrazení →
  Zobrazit řádek disku, Zobrazit lištu disků). Lištu disků lze nyní skrýt.

### Změněno

- Lišta funkčních kláves nechává na obou koncích malý okraj, takže F1 už nesedí v zaobleném
  rohu okna.

### Opraveno

- Stavový řádek a Vlastnosti počítají soubory a složky se správným tvarem množného čísla („1 soubor“,
  „3 soubory“) místo „1 souborů“.
- ⌃↩ v panelu opět vloží do příkazového řádku název položky pod kurzorem; macOS místo toho
  ukazoval kontextové menu.
- ⌘X vyjme vybraný text v příkazovém řádku a dalších textových polích; menu Úpravy nemělo
  položku Vyjmout. ⌃X, ⌃C a ⌃V také vyjímají, kopírují a vkládají text, když má fokus příkazový řádek.
- Rozbalování archivu už nakrátko nemění umask procesu, což mohlo souborům vytvářeným
  ve stejnou chvíli (jinou operací) přidělit špatná oprávnění.
- Názvy v souborech zip vytvořených ve Windows bez příznaku UTF-8 (například české názvy v CP852)
  se zobrazí a rozbalí správně místo „�“; znaková sada se řídí jazykem systému.
- Archiv otevřený přes složku se symbolickým odkazem nebo s jinou velikostí písmen už po změně
  neukazuje zastaralý seznam položek.
- F4 oznámí, že editor zvolený v Nastavení není nainstalován, místo aby potichu otevřel
  TextEdit.

## [0.3.1] - 2026-10-11

### Změněno

- F1 (Nápověda → Nápověda k aplikaci Axolotl Commander) otevře stránku projektu na GitHubu, dokud
  aplikace nemá vlastní nápovědu; dříve byla vždy zašedlá.

### Opraveno

- Lišta funkčních kláves drží každou klávesu a název na pevném místě: každá klávesa je nakreslena
  na klávesové čepičce o stejné šířce vlevo od tlačítka a název následuje hned za ní, takže podržení
  ⇧, ⌃ nebo ⌥ už popisky neposouvá.
- F3 na souboru TypeScript (`.ts`, `.mts`) otevře prohlížeč se zvýrazněním syntaxe. macOS tyto
  přípony považuje za video MPEG-2, a tak šly do Quick Look; skutečný videosoubor tam stále jde.

## [0.3.0] - 2026-10-10

### Přidáno

- Velikosti v panelech se čtou jako ve Finderu: „402 bytes“, „453 kB“, „4.1 MB“, v jazyce a formátu
  čísel systému. **Toto je nové výchozí nastavení**; chcete-li ve sloupci Velikost získat zpět přesné
  bajty, zvolte Nastavení → Vzhled → Velikost v panelech → V bajtech. Přesný počet bajtů je vždy
  v tooltipu buňky Velikost a ve stavovém řádku pro položku pod kurzorem
  („4.3 MB (4,300,000 bytes)“).
- Nastavení → Vzhled → Jednotky volí 1000 (jak počítá Finder, výchozí) nebo 1024 (jak počítá
  Windows) pro každou zaokrouhlenou velikost v aplikaci: panely, stavové řádky, lištu disků, operace,
  Vlastnosti, Porovnání a Využití disku.
- Velikost, která se nevejde do úzkého sloupce Velikost, ukáže výpustku, nikdy oříznuté číslo.
- Zobrazení větve (⌃B, Zobrazení → Zobrazit větev (s podsložkami)): panel vypíše
  v jednom seznamu každý soubor složky i všech jejích podsložek. Sloupec Název ukazuje vlastní název
  souboru; stavový řádek ukazuje jeho cestu pod složkou. ⌃B znovu se vrátí do složky. Funguje
  ve složkách na disku, v archivech i na serverech; dlouhé prohledávání ukazuje průběh a Esc jej
  zastaví. Zobrazení → Zobrazit větev označených položek dělá totéž pro označené soubory a složky.

## [0.2.2] - 2026-10-10

### Změněno

- Sloupce Velikost a Datum v panelu lze zúžit. Hodnota, která se nevejde, se ukáže v kratším
  tvaru: zaokrouhlená velikost („1.2 MB“); datum bez času, s dvouciferným rokem nebo jen den
  a měsíc; výpustka, když se nevejde nic. Plná hodnota je v tooltipu. Dříve sloupce nešlo zúžit
  pod jejich nejširší hodnotu, takže jejich hrany v tomto směru nenabízely změnu velikosti.
- Ručně změněný sloupec bere šířku od Názvu, takže sloupce vždy vyplní panel a
  lze přetáhnout i pravou hranu posledního sloupce.

## [0.2.1] - 2026-10-09

### Opraveno

- Symbolické odkazy na složky se v panelu opět otevírají (například /Volumes/Macintosh HD, odkaz
  na /); dříve panel jen pípl s „Not a directory“.

## [0.2.0] - 2026-10-09

První verzovaná verze (dřívější sestavení se nazývala 0.1.0 bez značky): dvoupanelový správce souborů (etapy 0–11 plánu v
[docs/PLAN.md](docs/PLAN.md)) a opravy bezpečnosti dat ze specifikace
[001-data-safety-gaps](specs/001-data-safety-gaps/spec.md).

### Přidáno

- Soubory CSV, TSV a TAB se v Náhledu prohlížeče otevřou jako tabulka, i když mají stovky
  megabajtů. Tabulka má:
  - zjištěný oddělovač, kódování a řádek záhlaví;
  - pevná čísla řádků;
  - označené vadné řádky (⌘↓/⌘↑, Jen vadné řádky ⇧⌘D);
  - hledání po buňkách (F3/⇧F3);
  - Přejít na řádek (⌘L) a kopírování jako text oddělený tabulátory;
  - řazení podle sloupce po přečtení souboru
  ([007-csv-table-preview](specs/007-csv-table-preview/spec.md)).
- V prohlížeči fungují funkční klávesy jako F3 a ⇧F3 i při úpravě pole hledání.
- Web [axolotlcommander.org](https://axolotlcommander.org), odkazovaný z README a z okna
  O aplikaci.
- Lišta funkčních kláves F1–F12 dole v hlavním okně, sledující podržené modifikátory
  (⇧ ⌃ ⌥ ⌘); lištu i příkazový řádek lze skrýt z menu Zobrazení nebo v Nastavení
  ([002-function-key-bar](specs/002-function-key-bar/spec.md)).
- Nastavení → Klávesnice ukazuje, zda F1–F12 potřebují `fn`, a otevře Nastavení systému; jednorázové
  upozornění při spuštění to vysvětlí.
- Klikací cesta ve formě drobečkové navigace nad každým panelem: klik na složku tam přejde, ⌘-klik
  otevře novou záložku, pravý klik nabídne další možnosti; ⌘L (Upravit cestu) umožní cestu napsat;
  dlouhé cesty se sbalí do „…“; textové pole zůstává dostupné v Nastavení → Vzhled
  ([003-breadcrumb-path-bar](specs/003-breadcrumb-path-bar/spec.md)).
- Otevřená připojení k serverům jako tlačítka v liště disků: jeden klik vrátí do poslední složky
  na serveru, ⏏ po najetí myší nebo menu pravého kliku odpojí; menu svazků (⌥F1/⌥F2) je uvádí
  pod „Servery“. Lišta disků nabízí také iCloud Drive, Síť (připojené síťové
  svazky, připojení, Připojit k serveru…) a volitelné tlačítko Domů, které se volí v Nastavení →
  Vzhled; panel nástrojů dostane Připojit k serveru a lze přidat Odpojit
  ([004-server-connection-buttons](specs/004-server-connection-buttons/spec.md)).
- Odkazy: Nový symbolický odkaz… (⌃⌘L) a Nový pevný odkaz… vytvoří odkazy ve složce druhého panelu
  (absolutní nebo relativní cíl, více položek najednou), Upravit symbolický odkaz… změní cíl odkazu
  jedním krokem, Vložit jako symbolický odkaz (⌃⌘V, ⌃S) vytvoří odkazy na zkopírované položky a Přejít na
  cíl odkazu (⌃T) následuje symbolické odkazy a aliasy Finderu. Existující položky se nikdy nenahrazují.
  Změnit atributy… (⌃F2) otevře editor oprávnění přímo
  ([005-unix-link-commands](specs/005-unix-link-commands/spec.md)).
- Síťová složka: tlačítko Síť v liště disků (a Síť v menu svazků) ukazuje v panelu
  servery SMB, AFP a SFTP oznámené v místní síti a připojené síťové svazky; Enter připojí
  sdílení SMB/AFP přes dialog macOS a vstoupí do něj, nebo u serveru SFTP otevře
  Připojit k serveru. Rychlé menu tlačítka Síť se přesunulo na jeho pravý
  klik ([006-network-places](specs/006-network-places/spec.md)).
- Výzvy macOS k přístupu ke složkám (Plocha, Dokumenty, Stažené, disky, cloudová úložiště)
  vysvětlují, proč to správce souborů potřebuje, v angličtině a češtině.
- Vydání lze podepsat stálým certifikátem projektu (`scripts/make-signing-cert.sh`), takže
  přístup ke složkám udělený uživateli přežije aktualizace i bez Apple Developer ID; místní
  sestavení se podepisují vývojářovým certifikátem „Apple Development“, pokud nějaký má.
