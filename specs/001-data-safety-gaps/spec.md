# Feature Specification: Bezpečnost dat — mezery z auditu (D1–D8)

**Feature Branch**: `001-data-safety-gaps`

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: "Bezpečnost dat: odstranit mezery D1–D8 z auditu docs/AUDIT.md proti pravidlům vzoru (05-pravidla.md, specs Tandemu 062, 092, 103, 105, 106, 107, 112, 119) a doplnit chybějící testy pojistek."

Vzor: `../tandemcommander/docs/macos-port/05-pravidla.md` (sekce Identita souboru, Přepsání,
Přesun a odkaz, Archiv) a záznamy funkcí 062, 092, 103, 105, 106, 107, 112, 119 ve
`../tandemcommander/specs/`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Přepis souboru na serveru nezničí starou verzi (Priority: P1)

Uživatel kopíruje (F5) soubor na FTP/SFTP server, kde už soubor stejného jména je, a potvrdí
přepsání. Spojení během operace spadne nebo server odmítne poslední krok. Na serveru musí
zůstat buď stará verze, nebo nová úplná verze — nikdy žádná.

**Why this priority**: Jediné místo, kde dnes běžná operace může zničit data bez možnosti
návratu (na serveru není Koš).

**Independent Test**: Simulovaný server, který selže v závěrečném kroku výměny; po operaci
existuje původní obsah cíle (nebo úplný nový obsah) a uživatel dostal chybovou hlášku.

**Acceptance Scenarios**:

1. **Given** na serveru je `zprava.txt` (stará verze), **When** uživatel přepíše soubor novou
   verzí a výměna na konci selže, **Then** na serveru zůstane `zprava.txt` se starým obsahem
   nebo nová úplná verze pod jménem, které hláška uvede, a hláška řekne, co se stalo.
2. **Given** totéž, **When** přenos dat selže uprostřed, **Then** stará verze je beze změny
   a na serveru nezůstane rozpracovaná kopie.
3. **Given** server umí atomickou výměnu, **When** přepis proběhne, **Then** v žádném okamžiku
   cíl na serveru nechybí.

---

### User Story 2 - Neuložené úpravy členů archivu přežijí ukončení (Priority: P1)

Uživatel otevře soubor uvnitř ZIPu přes F4, upraví ho v editoru a pak aplikaci ukončí.
Aplikace nabídne vrácení úprav do archivu. Uživatel zvolí „Teď ne“, nebo zápis do archivu
selže (archiv je jen pro čtení, disk plný). Úprava se nesmí ztratit.

**Why this priority**: Dnes se upravené kopie při ukončení smažou bez varování — ztráta práce.

**Independent Test**: Upravená kopie člena + odmítnutí nebo chyba zápisu + ukončení → kopie
existuje a při dalším spuštění se znovu nabídne.

**Acceptance Scenarios**:

1. **Given** upravená kopie člena archivu, **When** uživatel při ukončení zvolí „Teď ne“,
   **Then** kopie zůstane zachována a při příštím spuštění aplikace ji znovu nabídne
   k vrácení (s názvem archivu a člena).
2. **Given** upravená kopie, **When** vrácení do archivu při ukončení selže, **Then** aplikace
   ohlásí chybu, kopii zachová a řekne, kde ji uživatel najde.
3. **Given** kopie bez úprav (jen prohlížená), **When** aplikace končí, **Then** se uklidí.
4. **Given** zachovaná úprava z minula, **When** uživatel ji při dalším spuštění vrátí nebo
   výslovně zahodí, **Then** se kopie uklidí.

---

### User Story 3 - Operace s archivem se nezacyklí do sebe (Priority: P1)

Uživatel přesouvá složku do její vlastní podsložky uvnitř téhož archivu, ale archiv má
v panelech otevřený pod různými zápisy cesty (přes symlink, jinou velikostí písmen).
Nebo balí (Alt+F5) obsah do archivu, který je sám mezi zdroji nebo uvnitř zdrojové složky.
Obojí se musí odmítnout dřív, než se cokoli změní.

**Why this priority**: Přesun do sebe může v archivu odstranit originál i kopii.

**Independent Test**: Archiv otevřený přes symlink v jednom panelu a přímo ve druhém; přesun
složky do jejího potomka → odmítnuto, archiv beze změny. Zabalení složky do archivu, který
v té složce leží → odmítnuto.

**Acceptance Scenarios**:

1. **Given** archiv `a.zip` otevřený v levém panelu jako `~/odkaz/a.zip` (symlink) a v pravém
   jako `~/data/a.zip`, **When** uživatel přesune složku `docs` do `docs/old` mezi panely,
   **Then** operace se odmítne s hláškou „nelze přesunout do sebe“ a archiv se nezmění.
2. **Given** totéž s jinou velikostí písmen cesty na svazku bez rozlišení velikosti písmen,
   **Then** stejný výsledek.
3. **Given** složka `projekt` obsahuje `projekt/zaloha.zip`, **When** uživatel zabalí
   `projekt` do `projekt/zaloha.zip`, **Then** operace se odmítne před zápisem.
4. **Given** mezi označenými zdroji je i cílový archiv, **When** uživatel balí, **Then**
   odmítnuto před zápisem.

---

### User Story 4 - Mazání na svazku bez Koše je vědomé (Priority: P2)

Uživatel maže (F8) na síťovém svazku nebo disku, který Koš nepodporuje. Musí se to dozvědět
předem a rozhodnout se, ne zjistit po chybě, že dávka zůstala napůl.

**Why this priority**: Trvalé smazání bez varování je nevratné; napůl provedená dávka mate.

**Independent Test**: Simulovaný svazek bez Koše; F8 na několik položek → jeden dotaz na
trvalé smazání; po „Zrušit“ se nic nesmaže, po „Smazat trvale“ se smaže vše.

**Acceptance Scenarios**:

1. **Given** položky na svazku bez Koše, **When** uživatel stiskne F8, **Then** dotaz výslovně
   řekne, že položky se smažou trvale a nepůjde to vrátit, a nabídne „Smazat trvale“ a „Zrušit“.
2. **Given** smíšený výběr (část na svazku s Košem, část bez), **When** F8, **Then** dotaz
   uvede, které položky se smažou trvale; po potvrzení jdou ostatní do Koše.
3. **Given** dotaz, **When** uživatel zvolí „Zrušit“, **Then** se nesmaže ani nepřesune nic.
4. **Given** přesun do Koše nečekaně selže uprostřed dávky, **When** operace skončí, **Then**
   uživatel vidí, které položky v Koši jsou a které zůstaly, a nic se nesmazalo trvale bez
   jeho potvrzení.

---

### User Story 5 - Svazek bez spolehlivé identity souborů (Priority: P2)

Na některých svazcích (síťové, starší souborové systémy) nelze spolehlivě zjistit, zda dvě
cesty vedou na tentýž soubor. Operace, která by při shodě smazala zdroj, se tam nesmí spoléhat
na odhad.

**Why this priority**: Přesun „souboru na sebe sama“ by smazal jediný exemplář.

**Independent Test**: Svazek simulující chybějící nebo nestálou identitu; přesun na cíl, který
může být týž soubor → odmítnut s vysvětlením; kopie do nové složky funguje.

**Acceptance Scenarios**:

1. **Given** svazek bez spolehlivé identity a cíl, který už existuje pod jménem, jež svazek
   považuje za stejné, **When** uživatel přesouvá nebo přepisuje se smazáním zdroje,
   **Then** operace se odmítne s vysvětlením.
2. **Given** týž svazek a cíl, který neexistuje, **When** přesun, **Then** proběhne normálně.
3. **Given** dva soubory na různých svazcích, **When** se porovnává identita, **Then** se
   rozhoduje podle identity svazku a souboru, ne podle textu cesty ani čísla zařízení.

---

### User Story 6 - „Uložit jako“ v prohlížeči neničí cíl (Priority: P2)

Uživatel v prohlížeči obrázku nebo textu zvolí „Uložit jako“ přes existující soubor. Cíl
může být symlink nebo mít štítky a práva. Uložení se musí chovat jako ostatní bezpečné zápisy.

**Why this priority**: Dnes uložení nahradí symlink obyčejným souborem a ztratí atributy.

**Independent Test**: Cíl = symlink na soubor se štítkem; uložit jako → symlink zůstane
symlinkem, soubor za ním má nový obsah a své atributy; simulovaná chyba zápisu → cíl beze změny.

**Acceptance Scenarios**:

1. **Given** cíl je symlink, **When** uložit jako, **Then** symlink zůstane a nový obsah má
   soubor, na který ukazuje.
2. **Given** cíl má štítky a práva, **When** uložit jako, **Then** štítky a práva zůstanou.
3. **Given** zápis selže, **When** uložit jako, **Then** cíl je beze změny a nezůstane po
   operaci dočasný soubor.

---

### User Story 7 - Přejmenování na jiný odkaz téhož souboru je konflikt (Priority: P3)

Soubor má dva pevné odkazy (`a.txt` a `b.txt`). Uživatel přejmenuje `a.txt` na `b.txt`.
Dnes operace tiše „uspěje“ a nic se nestane. Má se ohlásit, že cíl existuje.

**Why this priority**: Nezpůsobí ztrátu dat, ale zprávu o úspěchu, která neodpovídá stavu.

**Independent Test**: Dva hard linky; F2 jednoho na jméno druhého → hláška o existujícím cíli,
oba odkazy beze změny. Změna jen velikosti písmen téhož jména dál funguje.

**Acceptance Scenarios**:

1. **Given** `a.txt` a `b.txt` jsou pevné odkazy na tentýž soubor, **When** F2 `a.txt` →
   `b.txt`, **Then** aplikace ohlásí, že cíl už existuje, a nic nezmění.
2. **Given** `Zprava.txt`, **When** F2 na `zprava.txt` (jen velikost písmen), **Then**
   přejmenování proběhne.

---

### User Story 8 - Pojistky, které už platí, mají testy (Priority: P3)

Několik pravidel vzoru je splněných, ale bez automatického testu, takže je může nenápadně
rozbít budoucí změna.

**Why this priority**: Ochrana proti regresi; nemění chování.

**Independent Test**: Nové testy procházejí na současném kódu a selžou, když se pojistka
záměrně vypne.

**Acceptance Scenarios**:

1. **Given** samotný symlink na adresář, **When** uživatel ho přesune jinam, **Then** soubory
   za odkazem zůstanou a přesune se jen odkaz.
2. **Given** složka s nečitelnou podsložkou, **When** přesun, **Then** zdroj se nesmaže
   a uživatel se dozví, co se nepřeneslo.
3. **Given** jméno v rozloženém tvaru (NFD), **When** kopie nebo přejmenování jiného souboru
   do stejné složky, **Then** jména si zachovají přesně ty kódové jednotky, které měla.

---

### Edge Cases

- Server bez podpory přejmenování přes existující soubor: nová verze se nahraje pod dočasné
  jméno a stará se odstraní až po úspěšném nahrání; když výměna selže, uživatel ví, kde je
  která verze (US1).
- Zrušení operace uživatelem uprostřed přepisu na serveru: platí totéž co selhání (US1).
- Archiv zmizel nebo se změnil mezi úpravou a vrácením: úprava se nevrací naslepo, kopie
  zůstane a uživatel dostane hlášku (US2).
- Více zachovaných úprav z minula: nabídnou se všechny najednou v jednom přehledu (US2).
- Hard link ve stejné složce pod jménem lišícím se jen NFC/NFD: rozhoduje identita, ne text (US7).
- Mazání, kde část položek je na svazku bez Koše a uživatel nemá právo mazat: dotaz se
  neukáže pro položky, které by stejně selhaly; chyba se ohlásí (US4).
- Svazek, kde identita existuje, ale po odpojení a připojení se mění: identita se
  nepoužívá mezi připojeními (US5).

## Requirements *(mandatory)*

### Functional Requirements

**Přepis na serveru (D1)**

- **FR-001**: Přepis existujícího souboru na serveru MUSÍ nejdřív úplně nahrát nová data pod
  dočasné jméno ve stejné složce; cíl se nesmí odstranit dřív, než je nahrání dokončené.
- **FR-002**: Pokud server umí výměnu souboru jedním krokem, MUSÍ se použít.
- **FR-003**: Když výměna selže, na serveru MUSÍ zůstat aspoň jedna úplná verze (stará, nebo
  nová pod dočasným jménem) a hláška MUSÍ uvést, kde je.
- **FR-004**: Když selže nebo se zruší samotné nahrávání, stará verze MUSÍ zůstat beze změny
  a nedokončená dočasná kopie se MUSÍ odstranit.

**Úpravy členů archivu (D2)**

- **FR-005**: Ukončení aplikace NESMÍ smazat upravenou kopii člena archivu, kterou uživatel
  nevrátil do archivu nebo výslovně nezahodil.
- **FR-006**: Zachované úpravy se MUSÍ při dalším spuštění nabídnout k vrácení nebo zahození,
  s uvedením archivu a člena.
- **FR-007**: Když vrácení do archivu selže, aplikace MUSÍ kopii zachovat a říct, kde je.
- **FR-008**: Kopie bez úprav se MUSÍ při ukončení uklidit.
- **FR-009**: Úprava se do archivu NESMÍ vrátit, pokud se archiv mezitím změnil nebo zmizel;
  uživatel dostane hlášku a kopie zůstane.

**Archiv a operace do sebe (D3, D7)**

- **FR-010**: Kontrola „složka do sebe nebo svého potomka“ uvnitř archivu MUSÍ porovnávat
  identitu souboru archivu, ne text jeho cesty.
- **FR-011**: Zabalení do archivu, který je mezi zdroji nebo leží uvnitř některé zdrojové
  složky, se MUSÍ odmítnout před jakýmkoli zápisem.
- **FR-012**: Každé odmítnutí MUSÍ ponechat archiv i zdroje beze změny a ukázat důvod.

**Mazání bez Koše (D4)**

- **FR-013**: Před mazáním MUSÍ aplikace zjistit, které položky nelze přesunout do Koše.
- **FR-014**: Pro takové položky MUSÍ jeden dotaz výslovně oznámit trvalé smazání a nabídnout
  „Smazat trvale“ a „Zrušit“; bez potvrzení se nic trvale nesmaže.
- **FR-015**: Po „Zrušit“ se NESMÍ smazat ani přesunout žádná položka dávky.
- **FR-016**: Když přesun do Koše selže uprostřed dávky, aplikace MUSÍ skončit a ukázat,
  co je v Koši a co zůstalo; selhané položky NESMÍ smazat trvale bez nového potvrzení.

**Identita souborů (D5)**

- **FR-017**: Identita souboru MUSÍ být určena identitou svazku a identifikátorem souboru;
  číslo zařízení samo nestačí a identita se nesmí uchovávat přes odpojení svazku.
- **FR-018**: Na svazku, kde identitu nelze spolehlivě určit, se operace, která by při shodě
  zdroje a cíle smazala zdroj, MUSÍ odmítnout, pokud cíl existuje pod jménem, které svazek
  považuje za stejné nebo může být týmž souborem.
- **FR-019**: Operace bez mazání zdroje (kopie do nového jména) MUSÍ na takovém svazku fungovat.

**Uložit jako (D6)**

- **FR-020**: „Uložit jako“ v prohlížečích MUSÍ zapsat přes dočasný soubor ve stejné složce
  a vyměnit až po úplném zápisu; při chybě cíl zůstane beze změny a dočasný soubor zmizí.
- **FR-021**: Je-li cílem symlink, MUSÍ zůstat symlinkem a nový obsah dostane soubor za ním.
- **FR-022**: Práva, štítky a rozšířené atributy cíle MUSÍ zůstat zachovány.

**Přejmenování (D8)**

- **FR-023**: Přejmenování na jméno jiného pevného odkazu téhož souboru se MUSÍ ohlásit jako
  existující cíl a nic nezměnit.
- **FR-024**: Přejmenování téhož záznamu jen na jinou velikost písmen nebo jiný tvar
  Unicode MUSÍ dál fungovat.

**Testy (D1–D8 a stávající pojistky)**

- **FR-025**: Každý požadavek FR-001 až FR-024 MUSÍ mít automatický test, který selže, když
  se pojistka odstraní; testy běží jen v izolovaných dočasných složkách a na simulovaných
  serverech/svazcích.
- **FR-026**: Testy MUSÍ pokrýt i stávající pojistky: přesun samotného symlinku na adresář,
  neúplný průchod stromem nechá zdroj, zachování kódových jednotek jmen (NFC/NFD).
- **FR-027**: Logika úprav členů archivu (sledování kopií, rozhodnutí co vrátit, co zachovat)
  MUSÍ být testovatelná bez uživatelského rozhraní.

### Key Entities

- **Upravená kopie člena archivu**: dočasný soubor vytažený z archivu kvůli F4; váže se
  k archivu (identita), jménu člena a stavu při vytažení; stav: neupravená / upravená /
  vrácená / zahozená / zachovaná na příště.
- **Identita souboru**: dvojice identita svazku + identifikátor souboru; platí jen během
  jednoho připojení svazku; může chybět („neznámá“).
- **Dávka mazání**: seznam položek rozdělený na „do Koše“ a „trvale“ ještě před provedením.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Ve 100 % simulovaných selhání přepisu na serveru (přerušení nahrávání, selhání
  výměny, zrušení) zůstane na serveru aspoň jedna úplná verze souboru.
- **SC-002**: Ve 100 % případů ukončení aplikace s neuloženou úpravou člena archivu je úprava
  po dalším spuštění k dispozici.
- **SC-003**: Žádná z operací „do sebe“ (přesun do potomka v archivu, zabalení do vlastního
  zdroje) nezmění jediný bajt archivu ani zdrojů — ověřeno pro všechny zápisy cesty ve
  scénářích US3.
- **SC-004**: Žádná položka se trvale nesmaže bez dotazu, který trvalé smazání výslovně uvádí.
- **SC-005**: Všechny mezery D1–D8 mají aspoň jeden automatický test; celá sada testů projde
  a trvá do 10 sekund.
- **SC-006**: Každé odmítnutí operace ukáže uživateli srozumitelný důvod (žádné tiché selhání
  ani tichý „úspěch“).

## Assumptions

- Testy serveru používají simulovaný souborový systém serveru (jako stávající testy přenosů);
  skutečné servery ani uživatelská data se nepoužijí.
- „Svazek bez spolehlivé identity“ se rozpozná podle vlastností svazku hlášených systémem;
  testy ho simulují.
- Zachované úpravy členů archivu se ukládají v soukromé složce aplikace (ne v dočasné
  složce systému, kterou systém může vyčistit).
- Výchozí volba dotazu na trvalé smazání je „Zrušit“ (bezpečná volba, jako Finder).
- Plán (ne tato specifikace) rozhodne o přesunu logiky úprav členů archivu do jádra aplikace,
  aby šla testovat bez UI (FR-027).
- Mimo rozsah: hesla a soukromí (P1–P4 auditu, samostatná specifikace), nové funkce UI.
