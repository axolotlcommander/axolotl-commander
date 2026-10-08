<!-- Děkujeme! Pull requesty v češtině i angličtině jsou vítány. / Thanks! PRs in Czech or English are welcome. -->

## Co a proč

<!-- Stručně: co změna dělá a jaký problém řeší. Odkaz na issue: "Closes #123". -->

## Jak jsem to ověřil(a)

- [ ] `swift build` bez varování
- [ ] `swift test` zelené
- [ ] Ručně v aplikaci (popiš, co a kde — **jen v testovací složce**, nikdy na skutečných datech)

## Kontrolní seznam

- [ ] Nové soubory mají SPDX hlavičku (`GPL-3.0-or-later`)
- [ ] Nečetl(a) jsem ani nekopíroval(a) C++ zdrojáky Tandem Commanderu / Open Salamanderu
      (vzorem je jen chování a dokumentace — viz [CONTRIBUTING.md](../CONTRIBUTING.md))
- [ ] Logika je v `CommanderCore` a má test; UI jen volá
- [ ] Nové texty v UI jsou v `Resources/Localizable.xcstrings` (i s českým překladem, pokud to umíš)
- [ ] Commity jsou podepsané (`git commit -s`, Developer Certificate of Origin)
