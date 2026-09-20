# Ověření při předání

Datum: 20. 9. 2026.

## Provedeno v dostupném prostředí

- Prozkoumán dostupný statický web PRIVOFIT, značka, CSS a assety. Backend ani API specifikace nebyly nalezeny.
- Ověřeny oficiální požadavky Xcode 27 / iOS 27 a dokumentace Google OAuth pro nativní aplikace; odkazy jsou v README.
- Syntaktické stromy 35 souborů Swift bez diagnostik parseru tree-sitter.
- Soubor `project.pbxproj` úspěšně načten parserem XcodeProject.
- Úspěšně načteny XML scheme/workspace metadata, plist, entitlements, privacy manifest a JSON asset metadata.
- String Catalog obsahuje 209 klíčů s českou i anglickou hodnotou. Všechny staticky použité literální klíče jsou přítomné. Dynamické klíče pro 4 kroky onboardingu, vzhled a stav členství jsou vypsané v katalogu.
- Provedena kontrola cest souborů v projektu, oddělení DEBUG mocku, ukládání tokenů, produkčních chybových stavů a konfigurace bez tajných klíčů.
- Při ruční kontrole opraveny: race při refreshi tokenu, opakovaná obsluha expired session, ochrana před souběhem dveřních obrazovek, nevyřešené příkazy po restartu, scope příkazů na jednotlivé členy, zákaz přechodu blocked účtu přes onboarding a opakovaná kontrola foreground před odesláním.

## Neprovedeno — vyžaduje Mac / backend

**Swift type-check, xcodebuild, XCTest, Swift Testing, UI testy a simulátorové vykreslení nebyly spuštěny.** Prostředí neobsahuje Swift compiler, Xcode ani iOS SDK. Úspěšná syntaktická kontrola nezaručuje úspěšnou kompilaci nebo bezchybný vzhled. Zde není žádný vymyšlený výsledek buildu ani testů.

Nebyla ověřena distribuce, signing, Face ID na fyzickém zařízení, skutečný Apple/Google OAuth, doručení APNs ani žádný fyzický zámek. Live API je explicitně nenakonfigurované.

Další krok je `Scripts/validate_on_mac.sh`, vybraný iOS 27 simulátor a následně integrace skutečného `BackendContract`. Na zařízení zkontrolujte malý i velký iPhone, landscape, největší Dynamic Type, světlý/tmavý režim, VoiceOver, Reduce Motion, Reduce Transparency, přechod do pozadí a offline/timeout během vstupu. UI test notifikačního zamítnutí vyžaduje čistý stav oprávnění simulátoru.

## Design 2 — aktuální revize

Přepracovány dashboard, přihlášení/registrace, onboarding, členská karta a celé vstupní rozhraní; doplněny společné vektorové komponenty zámku, klíče a dveří. Native toolbar a inline titulky sjednoceny napříč záložkami. Při kontrole byly znovu vygenerovány Xcode source references a katalog lokalizací. Statické kontroly aktuální revize prošly; typová kontrola Swiftu, build, UI testy a vizuální QA v simulátoru zůstávají neprovedené.
