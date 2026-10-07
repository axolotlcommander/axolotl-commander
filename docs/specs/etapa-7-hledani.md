# Etapa 7 – Hledání souborů (⌃⌥F7)

Vzor: Salamander `finddlg_main.htm`, `finddlg_advan.htm`, `basicwork_find.htm`, `src/find.cpp`.

## Okno hledání
- Nemodální okno, lze jich otevřít víc. Hledání běží na pozadí, hlavní okno zůstává použitelné.
- **Jméno** (combo + historie 30): masky Salamanderu (`;`, `|` vyloučení). Maska bez `*`, `?` a tečky
  znamená „obsahuje“ (`dog` = `*dog*`); tečka na konci znamená přesně (`dog.` = jméno `dog`).
  Prázdné = vše.
- **Hledat v** (combo + historie 30): víc cest oddělených `;`, výchozí = složka aktivního panelu,
  tlačítko pro výběr složky. `~` se rozvine.
- Volby: podsložky (výchozí zapnuto), skryté soubory (podle panelu), dovnitř balíčků (`.app` atd.,
  výchozí vypnuto — balíček sám ale může vyhovět jménem).
- **Obsahuje** (combo + historie 30): Rozlišovat velikost písmen, Celá slova, Hex (`4A 6F "text" 00`),
  Regulární výraz. Text se hledá v UTF-8, UTF-16 LE/BE a ve výchozím jednobajtovém kódování
  prohlížeče; NFC i NFD tvar. Hledání obsahu vrací jen soubory.
- **Rozšířené**: velikost od–do (B/KB/MB/GB), změněno od–do, druh (soubory a složky / soubory /
  složky), vynechat složky (`;`: jméno s maskou, např. `node_modules;.git`, nebo absolutní cesta).
- **Duplicity**: stejné jméno / stejná velikost / stejný obsah (obsah vyžaduje velikost). Skupiny
  se střídavým podbarvením, řazení podle skupin.
- Symlinky se nenásledují; adresář navštívený dvakrát (firmlinky `/System/Volumes/Data`) se přeskočí
  (st_dev + st_ino). Nečitelné složky a soubory → protokol chyb (počet ve stavovém řádku).

## Výsledky
- Tabulka Jméno, Cesta, Velikost, Změněno; řazení klikem na hlavičku; vícenásobný výběr;
  přibývají průběžně (dávky). Stavový řádek: právě prohledávaná složka, počet nalezených,
  po dokončení čas a počet chyb.
- Příkazy (rozsah `find`, menu se přepne jako u prohlížeče):
  - Enter otevřít, mezerník / ⌘R ukázat v panelu (aktivní panel přejde do složky a postaví kurzor),
  - F3 prohlížeč (sekvence = výsledky), F4 editor, ⌘Y Quick Look, ⌘I vlastnosti,
  - F8 / ⌘⌫ do Koše (potvrzení, jako v panelu), ⌫ odebrat ze seznamu,
  - ⌘C soubory do schránky, ⌥⌘C úplné cesty, ⌘⇧C jména, ⌘A vybrat vše,
  - ⌘↩ Najít, ⌘. / Esc zastavit (Esc v nečinnosti zavře okno), ⌘⇧P výsledky do panelu.
- Výsledky do panelu: aktivní panel zobrazí seznam výsledků jako virtuální složku (relativní cesty),
  F3/F4/F5/F6/F8 na nich fungují; Backspace / historie vrací zpět.

## Mimo tuto etapu
Uložená hledání, upřesnění (průnik/rozdíl/přidat), hledání v archivech, atributy.
