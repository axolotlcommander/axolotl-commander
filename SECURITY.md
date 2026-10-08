# Bezpečnost

## Hlášení zranitelnosti

Bezpečnostní chyby **nehlas veřejným issue**. Použij soukromé hlášení na GitHubu:
[Report a vulnerability](https://github.com/ACiDekCZ/axolotl-commander/security/advisories/new).

Uveď prosím, čeho se chyba týká (např. rozbalování archivů, SFTP/FTP, náhled Markdownu/HTML,
ukládání hesel), jak ji zopakovat a jaký může mít dopad. Ozveme se do 14 dnů; opravu zveřejníme
společně s poděkováním, pokud o ně stojíš.

Za bezpečnostní chybu považujeme hlavně:

- zápis mimo cílovou složku při rozbalování archivu (`../`, absolutní cesty, symlinky),
- únik hesla (do historie, logu, URL, na disk mimo Klíčenku),
- spuštění kódu nebo načtení vzdáleného obsahu z náhledu bez souhlasu,
- ztrátu nebo přepsání dat, které operace nemá dovoleno měnit.

## Podporované verze

Opravy vycházejí pro poslední vydanou verzi a pro větev `main`.

*Please report vulnerabilities privately via GitHub's "Report a vulnerability", not as public issues.*
