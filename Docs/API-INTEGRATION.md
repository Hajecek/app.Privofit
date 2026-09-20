# Hranice API a bezpečnostní rozhodnutí

## Zdroje a neznámé části

Dostupný marketingový web neposkytuje API dokumentaci. V projektu proto nejsou domnělé `/login`, `/doors/open` apod. Každá metoda `BackendContract` je úmyslně nenakonfigurovaná. Reálná doména, endpointy, API verze, DTO, autentizační schéma, idempotency header, status/denial kódy, časové zóny, lhůty a význam fyzického stavu zámku musí být potvrzeny provozovatelem backendu.

Doménové Codable modely nejsou automaticky používané jako neznámý wire format. U každé fabriky vytvořte skutečné request/response DTO a mapujte je do domény. Neznámé enumy a chybějící povinná bezpečnostní data musí selhat bezpečně, ne získat optimistický default.

## Relace

`HTTPClient` je actor nad URLSession, HTTPS only, stejný origin, bez HTTP redirectů, persistentní cache a cookies. Timeout je 20 s/request a 30 s/resource. Do logu se zapisuje jen status code, nikdy URL, tělo, identifikátor člena, heslo ani token. Úkoly používají async/await; čtecí SwiftUI task lze zrušit životním cyklem obrazovky. Fyzický příkaz se po zahájení nesmí naivně opakovat ani považovat za neodeslaný jen kvůli lokálnímu zrušení.

`AuthorizedClient` sdílí jeden refresh Task. Přes Keychain ukládá rotovanou relaci; generation guard odmítá opožděné odpovědi po změně přihlášení. Obnoví téměř expirovaný token před operací; po 401 opakuje pouze výslovně povolené GET. Dveřní příkaz, vytvoření a zrušení rezervace se po 401 automaticky neopakují. Backend musí rozlišit neplatné credentials od zrušené existující session ve svém dekodéru; UI nesmí ukázat raw backend text.

Keychain používá `WhenUnlockedThisDeviceOnly`, tokeny nejsou v UserDefaults. Hesla existují jen v paměti formuláře. Preferences ukládají jen vzhled, biometrickou preferenci a dokončení onboardingu. Logout vždy zruší lokální relaci; backendová revokace musí zároveň odpojit APNs registraci. Revokace při nedostupné síti nemusí být potvrzena; serverové tokeny musí mít omezenou životnost. Není implementována certifikátová pinning infrastruktura, protože nebyly dodány certifikáty ani strategie rotace; používá se systémová TLS validace.

Apple: podpis/audience/issuer/expiry a hash nonce ověřuje server. Google: public client + ASWebAuthenticationSession + PKCE, přesný redirect, state/nonce; backend vymění jednorázový code a ověří identity token. Nelze akceptovat neověřený klientský user ID/e-mail jako identitu. Serverové tajné klíče nikdy nepřidávejte do xcconfig.

## Dveře

1. UI nabízí samostatné potvrzení v nativním confirmation dialogu. Nejde o jediné klepnutí; zvolen byl přístupný dvoukrokový mechanismus namísto gesta závislého na motorice.
2. App state musí být authenticated, aktivní a lokálně odemčený. Guest a restricted účty nesmějí zahájit command. Společná blokace v AppModel chrání i více instancí obrazovky.
3. Aplikace znovu ověří nevyřešený uložený příkaz, potom načte serverovou eligibility a její expiry. Lokální členství nerozhoduje o vstupu. Backend příkazu musí znovu ověřit aktuální membership/booking/účet; preflight není bezpečnostní oprávnění samo o sobě.
4. Je-li zvolena biometrie, systém ji provede. Před odesláním je kontrolovaná session, foreground a čerstvost eligibility.
5. UUID request ID se před síťovou akcí zapíše do Keychain. Backend musí idempotency key transakčně svázat s uživatelem, dveřmi a akcí, vynutit rate limit, odmítnout replay a vrátit stejný výsledek pro duplicitu. Klientský UUID bez serverové implementace neposkytuje ochranu zámku.
6. `accepted` znamená jen přijetí, **nikoli otevření**. `confirmedOpen` může dekodér vytvořit výhradně z doloženého fyzického potvrzení se správnou čerstvostí. Stav historického commandu „někdy provedeno“ nelze mapovat na tvrzení, že jsou dveře teď otevřené. Pokud backend fyzický stav nezná, zůstává accepted/uncertain.
7. Při timeoutu nebo přerušení se další command automaticky neposílá. Uživatel může požádat o bezpečný read statusu stejného request ID. Backend musí umět dohledat request ID i tehdy, když klient nikdy neobdržel operation ID. Pokud lookup není dostupný, nelze tento bezpečný tok plně nasadit.
8. Nevyřešené command metadata jsou v Keychain oddělená pro každého člena a zůstávají i po restartu/odhlášení, aby opětovné přihlášení nezpůsobilo duplicitní otevření. Neobsahují access token. Vymažou se po potvrzeném definitivním výsledku. Při smazání účtu implementujte navíc řízený úklid jeho metadat až po vypořádání příkazu.
9. Úspěch má haptiku a krátký osmivteřinový UI cooldown. Ten je jen UX ochrana, ne serverový rate limit ani deklarovaná doba odemčení. Doba pro vstup se zobrazuje jen při dodaném `entryUntil` z API. Fyzický stav není nepřetržitě sledován.

Žádný credential/provider, local biometric úspěch, mock či notification payload nesmí obejít serverové dveřní oprávnění. Reálný zámek se připojuje výhradně k backendu.

## Rezervace a platby

UI nepovolí souběžné odeslání. Nevyřešenému opakování stejné rezervace v otevřené obrazovce zůstává stejný request ID. Po timeoutu aktualizuje seznam a označí výsledek jako nejistý. Backend musí transakčně zabránit duplicitní rezervaci stejného slotu a vynucovat pravidla konfliktů také po restartu aplikace; klíče rezervací nejsou v této verzi trvale uchovávané. Zrušení rezervace musí být serverově idempotentní. Nikdy neodečítejte kredity pouze na klientu.

Checkout je ručně nakonfigurovaná HTTPS URL otevřená systémem. Nepřidávejte bearer tokeny do query stringu. Pro personalizovaný checkout může API vystavit krátkodobou one-time session; jeho skutečný kontrakt zde zatím neexistuje.

## Co doplnit s backendem

- Finální DTO a chybové kódy, paginaci historie/inboxu a termínů, pravidla hesel a účetních stavů.
- Door sensor semantics / timestampy / definitivní výsledky / reconciliation a idempotenci.
- Device registration/unregistration a revokaci relací; account deletion případně s čerstvým ověřením identity.
- Serverovou synchronizaci onboardingu, pouze pokud backend takovou hodnotu podporuje. Lokální per-user dokončení již funguje.
- Skutečné checkout/support/legal URL, Google callback a Apple/APNs provisioning.
