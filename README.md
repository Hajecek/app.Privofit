# Privofit · nativní iOS aplikace

SwiftUI projekt pro iPhone a iOS 27. Soukromý trénink, rezervace, členství a vstup přes webové HTTPS API. Bez externích runtime závislostí, bez WebView jako náhrady aplikace, bez spojení s databází nebo zámkem.

**Stav předání:** implementovaný projekt se samostatným vývojovým režimem. Není připojen k produkčnímu API. Zde proběhla syntaktická a strukturální kontrola, nikoli sestavení aplikace: prostředí nemá macOS, Xcode ani iOS simulátor. Úspěšný build, testy a vizuální kontrolu na zařízení proto nelze poctivě tvrdit. Před nasazením spusťte přiložené kontroly na Macu a doplňte skutečný API kontrakt.

## Design 2 — přepracované rozhraní

- Přehled má nativní horní iOS toolbar: profil vlevo, PRIVOFIT uprostřed, oznámení vpravo. Pod ním je datum, pozdrav podle denní doby a jméno.
- Nová lime karta vstupu, menší členský přehled, čistší typografická hierarchie a jednotné odsazení. Všechny záložky používají inline nativní navigační lištu.
- Vstup vyplní obrazovku lime plochou. Vektorový prostorový zámek se při potvrzeném úspěchu odemkne a dveřní křídlo se otevře do hloubky. Akce je ukotvená dole přes safeAreaInset, aby zůstala dosažitelná i při scrollování. Nativní potvrzovací dialog a serverové kontroly zůstávají součástí vstupu.
- Přihlášení má horní toolbar, osobní uvítání, malý interaktivní přístupový klíč, Apple/Google vedle sebe a přehledná pojmenovaná pole. Prohlídka hosta je přímo v toolbaru.
- Registrace má tři oddělené kroky, vlastní nativní navigaci zpět, ukazatel průběhu a kompaktní prostorovou členskou kartu. Onboarding používá stejný vizuální styl.
- Reduce Motion zachovává srozumitelný statický/fade výsledek místo prostorového pohybu. Apple a Google tlačítka se při největším písmu přeskládají pod sebe.

Nové artwork komponenty jsou v `Shared/AccessArtwork.swift`. Jde o skutečný SwiftUI kód, ne předrenderované video. Animace úspěchu je navázaná na potvrzený stav DoorModel; přijetí požadavku nebo chyba dveře vizuálně neotevře. API konfigurace a bezpečnostní vrstva jsou zachované.

Použité nativní prvky: [ToolbarItem](https://developer.apple.com/documentation/swiftui/toolbaritem), [SwiftUI rotation3DEffect](https://developer.apple.com/documentation/swiftui/view/rotation3deffect(_:axis:anchor:anchorz:perspective:)). Vzhled ani animace zde nebyly vykreslené v iOS simulátoru; finální vizuální kontrola stále vyžaduje Xcode na Macu.

## Rychlé spuštění

1. Rozbalte celý archiv, otevřete `Privofit.xcodeproj` v **Xcode 27**. Žádný generátor ani instalace balíčků nejsou pro otevření projektu potřeba.
2. Vyberte schéma **Privofit Demo** a iPhone simulátor s iOS 27. Spusťte ⌘R.
3. Pro demo přihlášení vyplňte libovolné neprázdné jméno a heslo, například `alex` / `demo-password`. Použijte výhradně smyšlené údaje. Prohlédnout aplikaci můžete i jako host.
4. Projděte čtyři kroky onboardingu. Oznámení i biometrii lze přeskočit. U dveří nejdřív vyberte „Připravit otevření“ a potom potvrďte systémový dialog.
5. Pro skutečné služby vyberte schéma **Privofit** a doplňte níže uvedenou konfiguraci. Bez ní autentizace ani dveře nemohou hlásit úspěch.

Xcode 27 / iOS 27 SDK a požadavek macOS Tahoe 26.6+ jsou uvedené v [oficiálních požadavcích Apple](https://developer.apple.com/xcode/system-requirements). Projekt používá Swift 6 language mode a přísné kontroly concurrency. Výchozí deployment target je 27.0. Liquid Glass má kontrolu dostupnosti a fallback při omezené průhlednosti.

Na fyzickém zařízení vyberte vlastní Development Team a jedinečný Bundle ID. Apple přihlášení a APNs vyžadují odpovídající schopnosti App ID a provisioning; simulátorový demo build je na backendu nezávislý.

## Co je implementováno

- Root state machine: launch, signed out, onboarding, authenticated, guest, session expired, restricted; samostatné lokální biometrické uzamčení a ochranná vrstva při opuštění aplikace.
- Přihlášení e-mailem nebo username, registrace po třech krocích, zobrazení hesla, reset/změna hesla, zachování formuláře při chybě. Apple provider a Google OAuth provider, výměna identity/autorizačního kódu přes backend.
- Čtyři kroky onboardingu, explicitní žádosti o oprávnění, rozlišení Face ID / Touch ID / nedostupnosti, uložení dokončení pro jednotlivé účty i hosta.
- Nativních pět záložek: přehled, rezervace, vstup, členství, profil. Oznámení v samostatném sheetu.
- Dashboard s členstvím, nejbližší rezervací, historií, veřejnými informacemi a oprávněním ověřeným serverem. Prázdné, načítací a chybové stavy, pull-to-refresh.
- Výběr data a termínu, detail, vytvoření i zrušení rezervace. Serverové potvrzení, blokace dvojitého odeslání v rozhraní, předání idempotency klíče.
- Členství se stavem, dostupnou platností od–do a počtem vstupů; veřejné nabídky; nakonfigurovaný HTTPS checkout otevřený systémem. Žádný vymyšlený platební proces.
- Profil, nastavení vzhledu/biometrie/oznámení, změna hesla, konfigurovatelné odkazy, odhlášení a potvrzované smazání účtu přes API.
- Celoobrazovkový vstup, potvrzení před akcí, serverová kontrola oprávnění, volitelná biometrie, idempotence, rozlišení přijetí a fyzického otevření, ruční kontrola nejistého výsledku, krátký cooldown a haptika.
- Design systém PRIVOFIT, adaptivní sémantické barvy v asset catalogu, prostorová interaktivní členská karta ve SwiftUI, systémové písmo s Dynamic Type, SF Symbols, VoiceOver, Reduce Motion a Reduce Transparency.
- Český a anglický String Catalog, lokalizované vysvětlení Face ID, app icon, privacy manifest, development/staging/production konfigurace, unit/UI testy a 14 preview scénářů.

## Vizuální návaznost

Prozkoumaným podkladem byl dostupný statický web PRIVOFIT (`dist`), CSS, značka, favicon a webové 3D scény. Obsahoval marketing a demo formuláře; neobsahoval backend, OpenAPI ani reálné autentizační či dveřní endpointy. Místní macOS cestu `/Applications/XAMPP/xamppfiles/htdocs` toto linuxové prostředí nemá zpřístupněnou.

Aplikace navazuje na lime `#C6F21A`, deep lime `#8FBF00`, night `#0B1210`, ink `#101714`, fog `#E8F0E4` a zaoblené karty. Webové Figtree/Syne byly vzdálené Google Fonts, nikoli dodané licencované lokální soubory; nativní aplikace používá SF pro plnou systémovou adaptaci. Chcete-li přesné fonty, dodejte jejich soubory a licence, zaregistrujte `UIAppFonts` a nahraďte centrální typografii přes `.custom(..., relativeTo: ...)`. Nejde o kopii webového Three.js panáčka.

## Konfigurace API

- `Configuration/Base.xcconfig`: veřejné společné nastavení.
- `Configuration/Development.xcconfig`: Debug.
- `Configuration/Staging.xcconfig`: Staging; obsahuje DEBUG vývojové nástroje.
- `Configuration/Production.xcconfig`: Release, bez mock implementace.
- `Core/Configuration.swift`: jediné čtení konfigurace, odmítá prázdné hodnoty a placeholdery.
- **`Networking/BackendContract.swift`: jediné místo pro skutečné endpointy, payloady, DTO dekodéry, data, idempotency header a mapování odpovědí.**

Ve zvoleném `.xcconfig` nastavte například:

```xcconfig
// Nahraďte skutečnou doménou. $() zabraňuje tomu, aby // začalo komentář.
API_BASE_URL = https:/$()/DOPLNIT-DOMENU.CZ/api/v1/
```

Placeholder `DOPLNIT` aplikace záměrně odmítne. Prázdná výchozí konfigurace nic neposílá na domnělou doménu. Nestačí vyplnit URL: doplňte fabriky v `BackendContract` podle schválené dokumentace. Teď explicitně házejí `notConfigured`, nikdy nevyrábějí úspěšné odpovědi. `Models/Domain.swift` jsou doménové modely aplikace, **nikoli tvrzení o existujícím formátu JSON**.

Každý `Endpoint<Response>` definuje HTTP metodu, relativní cestu, tělo, hlavičky a bezpečný `@Sendable` dekodér DTO → doména. Datum a enumy mapujte podle skutečného API. Relativní cesta bez počátečního `/` respektuje base path `/api/v1/`. Opakování po refreshi zapněte `retryAfterRefresh` pouze u potvrzených idempotentních GET operací.

Potřebné schopnosti backendu (nejsou zde vydávány za existující cesty):

| Oblast | Potřebný kontrakt |
| --- | --- |
| Relace | Login, registrace, profil/status účtu, rotace refresh tokenu, revokace/odhlášení |
| Identity | Ověření Apple tokenu + nonce/code, Google kódu + PKCE/nonce; bezpečné propojení účtů |
| Účet | Neprozrazující reset hesla, změna hesla, autorizované a případně znovu ověřené smazání účtu |
| Veřejný obsah | Informace o fitku, skutečná otevírací doba, oznámení a nabídka tarifů |
| Členství | Autoritativní stav, platnost, zbývající vstupy, případně checkout |
| Rezervace | Dostupné termíny, seznam, vytvoření, zrušení, konflikty, idempotence |
| Návštěvy | Osobní historie návštěv |
| Vstup | Aktuální eligibility, identifikace dveří, jednorázový příkaz, idempotence, kontrola stavu příkazu podle request ID i při ztrátě první odpovědi |
| Oznámení | Inbox, APNs registrace zařízení ke správnému uživateli/prostředí, odpojení při odhlášení nebo smazání |
| Volitelné | Synchronizace dokončeného onboardingu; obsazenost jen pokud ji backend skutečně poskytuje |

Podrobnosti a podmínky bezpečného mapování jsou v `Docs/API-INTEGRATION.md`.

## Apple / Google / APNs

**Apple:** aktivujte Sign in with Apple pro svůj App ID, zvolte tým a provisioning. Zapněte `BackendContract.appleEnabled` až po implementaci serverové výměny. Provider vytváří náhodné state/nonce, posílá hash nonce Apple a raw nonce backendu. Backend ověří podpis, issuer, audience, expiraci a nonce; soukromý Apple klíč patří výhradně na server. Jméno Apple nemusí vrátit při opakovaném přihlášení, účet musí obsloužit backend.

**Google:** zaregistrujte správný iOS OAuth client ID pro svůj Bundle ID. Vyplňte `GOOGLE_CLIENT_ID`, `GOOGLE_CALLBACK_SCHEME` a `GOOGLE_REDIRECT_URI` přesně podle Google konfigurace. Callback schéma musí odpovídat URL Types. Zapněte `googleEnabled` až po dokončení serveru. Nativní provider používá `ASWebAuthenticationSession`, náhodné state/nonce a PKCE S256. Do aplikace nepatří client secret. Google vrací autorizační kód; místo jeho přímé výměny za token v telefonu jej aplikace předá webovému API, které získá a ověří identity token a vydá PRIVOFIT relaci. Tím veškerá autentizace PRIVOFIT zůstává na vašem serveru. Žádná webová API cesta nebyla pro tento účel vymyšlena. Ověřte nasazení podle [Google OAuth pro nativní aplikace](https://developers.google.com/identity/protocols/oauth2/native-app).

**Push:** aktivujte Push Notifications, nastavte odpovídající `aps-environment`, APNs Auth Key `.p8` / Key ID / Team ID bezpečně uložte na backend. iOS dostává device token, posílá jej až po přihlášení a neposílá demo tokeny. Při odhlášení musí backend revokovat vazbu zařízení a relace. Rozhraní při kliknutí na oznámení otevírá jen inbox; payload nikdy automaticky neotevírá dveře ani libovolnou URL. Zamítnutí notifikací nezablokuje onboarding. iOS nemá univerzální `NS...NotificationsUsageDescription`; přínos vysvětluje onboarding před systémovým dialogem.

## Demo a produkce

Mock je za `#if DEBUG`, z Release se nekompiluje. Schéma Demo předává `--demo`; hlavní schéma automaticky na mock nepřepíná ani při selhání API. Demo simuluje data, rezervace, členství, reset/změnu hesla a smazání demo účtu v paměti. Apple a Google v demo režimu nejsou falešně úspěšné. Vstup je viditelně označený jako simulace; host nemůže otevřít ani demo dveře.

Volitelné DEBUG argumenty: `--demo`, `--reset` (pouze demo preferences), `--no-biometry`, `--deny-door`, `--accepted-door`. Reálná oprávnění oznámení se nepřepisují argumentem `--reset`; UI test odmítnutí spouštějte na čistém simulátoru. Staging je vývojová konfigurace; distribuujte pouze Release. Neposílejte reálné přihlašovací údaje do demo formulářů.

Produkční host vidí ilustrační rezervační kartu jasně označenou jako ukázku. Skutečné hodiny/nabídky jsou veřejná API data; dokud API chybí, zobrazí se dostupný chybový stav, nikoli smyšlená fakta.

## Testování a ověření

Na Macu spusťte:

```bash
./Scripts/validate_on_mac.sh
xcrun simctl list devices available
PRIVOFIT_SIMULATOR_ID=<UUID-iPhone-s-iOS-27> ./Scripts/validate_on_mac.sh
```

Skript sestaví Debug i Release a při dodaném UUID spustí unit + UI testy. Testy jsou také dostupné přes ⌘U ve schématu Demo. Swift Testing pokrývá validaci, root/onboarding, guest/blocked režim, serverové zamítnutí, biometrii, dvojité otevření a cooldown. XCTest používá URLProtocol pro chyby HTTP, zákaz cizího hostu, single-flight refresh, zákaz automatického opakování příkazu a skutečný Keychain round-trip v izolované testovací service. UI testy pokrývají hosta, onboarding, chybějící biometrii, zamítnutí oznámení, login, mock úspěch a zamítnutý vstup.

`Scripts/static_check.py` ověřuje Swift syntax trees, strukturu `.pbxproj`, plist/scheme/asset metadata a úplnost lokalizovaných literálů. Vyžaduje vývojové Python balíčky `tree-sitter`, `tree-sitter-swift`, `pbxproj`; aplikace je nepotřebuje. Statická kontrola **není Swift type-check ani důkaz kompilace**. Výsledek aktuálního běhu je v `Docs/VALIDATION.md`.

## Před produkčním vydáním

Doplňte a integračně otestujte API, zejména transakční idempotenci a skutečné potvrzení fyzického otevření. Otestujte souběh/timeout/logout, refresh rotaci a revokaci, přístupnost, různá zařízení/rotaci a pozadí. Nakonfigurujte reálné odkazy `SUPPORT_URL`, `TERMS_URL`, `PRIVACY_URL`, `CHECKOUT_URL`. Bez nich aplikace ukáže nedostupnost, ne fiktivní odkaz.

Přiložený privacy manifest uvádí používání UserDefaults pouze pro vlastní nastavení (CA92.1), bez trackingu. Záznamy o shromažďování dat jsou zatím prázdné: **před distribucí je doplňte podle skutečného backendu**, včetně App Store privacy odpovědí. Nejde o prohlášení, že finální přihlášená aplikace žádná osobní data neshromažďuje. Finální platební model a obchodní dokumenty nebyly dodány.
