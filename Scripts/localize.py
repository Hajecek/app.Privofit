from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
# Explicit, manually maintained Czech / English string catalog.
rows=r'''
auth.headline|Tvoje tělo.\nTvoje tempo.|Your body.\nYour pace.
auth.intro|Soukromý prostor pro trénink. Rezervace i vstup ve tvé dlani.|A private space to train. Book and enter from your phone.
auth.identifier|E-mail nebo uživatelské jméno|Email or username
auth.password|Heslo|Password
auth.confirmPassword|Heslo znovu|Confirm password
auth.login|Přihlásit se|Sign in
auth.create|Vytvořit účet|Create account
auth.forgot|Zapomenuté heslo|Forgot password
auth.guest|Pokračovat bez přihlášení|Continue as a guest
auth.apple|Pokračovat přes Apple|Continue with Apple
auth.google|Pokračovat přes Google|Continue with Google
auth.or|nebo|or
auth.hidePassword|Skrýt heslo|Hide password
auth.showPassword|Zobrazit heslo|Show password
auth.signout|Odhlásit se|Sign out
common.continue|Pokračovat|Continue
common.notNow|Teď ne|Not now
common.back|Zpět|Back
common.close|Zavřít|Close
common.cancel|Zrušit|Cancel
common.ok|Rozumím|OK
common.submit|Odeslat|Submit
common.retry|Zkusit znovu|Try again
common.loading|Načítání|Loading
validation.identifier|Vyplň e-mail nebo uživatelské jméno.|Enter your email or username.
validation.email|Zkontroluj prosím e-mailovou adresu.|Please check your email address.
registration.title|Tvůj prostor začíná tady.|Your space starts here.
registration.passwordPolicy|Zvol silné, jedinečné heslo. Pravidla hesla ověříme při vytvoření účtu.|Choose a strong, unique password. Password requirements are checked when creating your account.
pass.yourName|Tvoje členská karta|Your member card
pass.headline|TVŮJ PROSTOR.\nTVOJE TEMPO.|YOUR SPACE.\nYOUR PACE.
pass.label|PRIVOFIT / MEMBER|PRIVOFIT / MEMBER
launch.tagline|Tvoje tělo. Tvoje tempo. Tvoje pravidla.|Your body. Your pace. Your rules.
profile.name|Jméno|First name
profile.username|Uživatelské jméno|Username
profile.email|E-mail|Email
profile.support|Podpora|Support
profile.terms|Obchodní podmínky|Terms of service
profile.privacy|Ochrana osobních údajů|Privacy policy
profile.footer|PRIVOFIT · Tvůj soukromý prostor|PRIVOFIT · Your private space
password.current|Současné heslo|Current password
password.new|Nové heslo|New password
password.change|Změna hesla|Change password
password.resetSent|Pokud účet existuje, pošleme ti postup obnovení hesla.|If the account exists, we will send password reset instructions.
password.changed|Heslo bylo změněno.|Password changed.
error.generic|Akci se nepodařilo dokončit. Zkus to prosím znovu později.|We could not complete this action. Please try again later.
error.configuration|Tato služba zatím není připojená. Zkus to prosím později.|This service is not connected yet. Please try again later.
error.session|Přihlášení vypršelo. Přihlas se prosím znovu.|Your session expired. Please sign in again.
error.credentials|Přihlášení se nepodařilo. Zkontroluj své údaje.|Could not sign in. Please check your credentials.
error.denied|Pro tuto akci nemáš oprávnění.|You are not permitted to perform this action.
error.offline|Není dostupné připojení. Zkontroluj internet.|You appear to be offline. Check your connection.
error.timeout|Server neodpověděl včas. Zkus to znovu.|The server did not respond in time. Please try again.
error.biometry|Biometrické ověření není dostupné.|Biometric authentication is unavailable.
error.cancelled|Ověření bylo zrušeno.|Authentication was cancelled.
session.title|Přivítáme tě znovu.|Welcome back.
account.restricted|Účet není aktivní.|Your account is not active.
account.restricted.body|Vstup ani rezervace teď nejsou dostupné. Obrať se na podporu PRIVOFIT.|Entry and bookings are unavailable. Please contact PRIVOFIT support.
account.delete|Smazat účet|Delete account
account.delete.title|Opravdu smazat účet?|Delete your account?
account.delete.body|Požádáme server o smazání účtu. Tato akce je nevratná a může ukončit přístup k rezervacím a členství.|We will request account deletion from the server. This cannot be undone and may end access to bookings and membership.
lock.title|Tvůj prostor je chráněný.|Your space is protected.
lock.unlock|Odemknout aplikaci|Unlock app
biometry.unavailable|Biometrie není dostupná|Biometrics unavailable
biometry.reason|Potvrď svou identitu pro PRIVOFIT|Confirm your identity for PRIVOFIT
tab.dashboard|Přehled|Overview
tab.reservations|Rezervace|Bookings
tab.door|Vstup|Entry
tab.membership|Členství|Membership
tab.profile|Profil|Profile
guest.gate.title|Tenhle prostor je pro členy.|This space is for members.
guest.gate.body|Přihlas se nebo si vytvoř účet. Pak můžeš rezervovat termín a bezpečně vstoupit.|Sign in or create an account to book a session and enter securely.
guest.name|Vítej v PRIVOFIT|Welcome to PRIVOFIT
guest.badge|Prohlídka bez přihlášení|Guest tour
guest.dashboard.title|Představ si svůj další trénink.|Picture your next workout.
guest.dashboard.body|Prohlédni si aplikaci. Osobní členství, návštěvy a rezervace se zobrazí až po přihlášení.|Explore the app. Your membership, visits and bookings appear after signing in.
guest.reservations|Ukázka rezervací|Booking example
guest.reservations.body|Toto je ilustrační termín, nikoli skutečná dostupnost fitka.|This is an illustrative time slot, not live gym availability.
guest.membership|Nabídku si můžeš prohlédnout. Své členství najdeš po přihlášení.|Browse the offers. Sign in to see your personal membership.
guest.profile|Prohlížíš si aplikaci jako host.|You are browsing as a guest.
demo.badge|VÝVOJOVÁ UKÁZKA|DEVELOPMENT DEMO
demo.credentials|Testovací účet: alex / demo-password|Test account: alex / demo-password
demo.quickLogin|Přihlásit jako Alex|Sign in as Alex
demo.notice|Vývojová ukázka: data jsou smyšlená, rezervace a vstupy nejsou skutečné.|Development demo: fictional data, no real bookings or door access.
demo.door|SIMULACE · žádné skutečné dveře|SIMULATION · no real door
demo.door.success|Úspěšný stav je simulovaný. Žádné skutečné dveře se neotevřely.|This success is simulated. No real door was opened.
onboarding.progress|Průvodce prvním spuštěním|Getting started
onboarding.0.title|Vítej ve svém.|Welcome to your space.
onboarding.0.body|Vyber si čas. Přijď. Otevři telefonem. A soustřeď se jen na svůj trénink.|Pick a time. Arrive. Enter with your phone. Focus on your workout.
onboarding.0.action|Pokračovat|Continue
onboarding.1.title|Důležité věci včas.|Stay in the loop.
onboarding.1.body|Připomenutí rezervace, potvrzení vstupu a informace o tvém členství. Oznámení můžeš kdykoliv změnit v nastavení.|Booking reminders, entry confirmations and membership updates. You can change notifications anytime in Settings.
onboarding.1.action|Povolit oznámení|Allow notifications
onboarding.2.title|Tvoje identita. Tvůj klíč.|Your identity. Your key.
onboarding.2.body|Biometrie chrání aplikaci a potvrzuje citlivé akce. Povolení ke vstupu vždy ověřujeme také na serveru.|Biometrics protect the app and confirm sensitive actions. Entry permission is always verified by the server too.
onboarding.2.action|Zapnout biometrii|Enable biometrics
onboarding.3.title|Můžeš začít.|Ready when you are.
onboarding.3.body|Všechno důležité najdeš v přehledu. Tvoje tělo. Tvoje tempo. Tvoje pravidla.|Everything you need is on your overview. Your body. Your pace. Your rules.
onboarding.3.action|Vstoupit do aplikace|Enter the app
greeting.morning|Dobré ráno,|Good morning,
greeting.day|Hezký den,|Hello,
greeting.evening|Hezký večer,|Good evening,
dashboard.yourSpace|Tvůj prostor|Your space
visits.title|Poslední návštěvy|Recent visits
visits.empty|Zatím tu není žádná návštěva.|No visits yet.
gym.title|O tvém fitku|About your gym
gym.demo.description|Ukázkové soukromé fitko. Prostor pro tebe, bez čekání na stroje.|A sample private gym. Space for you, without waiting for equipment.
gym.demo.hours|Ukázková otevírací doba: 6:00–22:00|Example opening hours: 6 am–10 pm
offer.name|Soukromý trénink|Private workout
offer.description|Ukázkový tarif. Skutečnou nabídku a cenu poskytne webové API.|Sample plan. Live offers and prices will come from the web API.
offer.price|Cena bude dostupná po připojení nabídky|Price available when connected
membership.offers|Najdi svůj rytmus.|Find your rhythm.
membership.noOffers|Žádné dostupné tarify|No plans available
membership.choose|Vybrat členství|Choose membership
membership.checkout|Přejít na bezpečný checkout|Open secure checkout
membership.from|Platí od|Valid from
membership.until|Platí do|Valid until
membership.entries|Zbývající vstupy|Remaining entries
membership.status.active|Aktivní|Active
membership.status.ending|Brzy končí|Ending soon
membership.status.paused|Pozastavené|Paused
membership.status.inactive|Neaktivní|Inactive
wallet.open|Otevřít v Peněžence|Open in Wallet
wallet.tap|Klepni na kartu a přidej ji do Peněženky.|Tap the card to add it to Wallet.
wallet.inWallet|Karta je v Peněžence|The card is in Wallet
wallet.unavailable|Na tomhle zařízení nejde kartu do Peněženky přidat.|This device cannot add a card to Wallet.
wallet.invalid|Kartu se nepodařilo připravit pro Peněženku.|The card could not be prepared for Wallet.
wallet.demo|Je to sběratelská karta, ne platební. Apple ji uloží, až ji podepíše server.|This is a collectible card, not a payment card. Apple saves it once the server signs it.
wallet.description|Sběratelská členská karta|Collectible member card
wallet.field.status|Stav|Status
reservations.new|Rychlá rezervace|Quick booking
reservations.next|Nejbližší rezervace|Next booking
reservations.empty|Zatím žádná rezervace|No bookings yet
reservations.mine|Tvoje rezervace|Your bookings
reservations.plan|Naplánuj trénink|Plan your workout
reservations.planHint|Vyber den v týdnu a rezervuj si volný čas.|Pick a day in the week and book an open slot.
reservations.week|Týden|Week
reservations.previousWeek|Předchozí týden|Previous week
reservations.nextWeek|Další týden|Next week
reservations.previousMonth|Předchozí měsíc|Previous month
reservations.nextMonth|Další měsíc|Next month
reservations.todayJump|Dnes|Today
reservations.tab.slots|Termíny|Slots
reservations.tab.mine|Moje termíny|My bookings
reservations.mineHint|Tady máš všechny zaplacené tréninky, odděleně od výběru nových termínů.|Here are all your paid sessions, separate from picking new slots.
reservations.mineEmpty|Zatím nemáš žádný termín.|You don't have any bookings yet.
reservations.mineEmptyHint|Vyber si čas v záložce Termíny a zaplať ho.|Pick a time in Slots and pay for it.
reservations.past|Proběhlé|Past
reservations.goToMine|Zobrazit moje termíny|View my bookings
reservations.bookedOnDayOne|Tento den už máš termín|You already have a booking this day
reservations.bookedOnDayMany|termíny tento den|bookings this day
reservations.legend.free|Volné|Open
reservations.legend.mine|Moje|Mine
reservations.legend.selected|Vybrané|Selected
reservations.today|Dnes|Today
reservations.tomorrow|Zítra|Tomorrow
reservations.upcoming|Nadcházející|Upcoming
reservations.slotsOne|1 volný termín|1 open slot
reservations.slotsMany|volných termínů|open slots
reservations.minutes|min|min
reservations.overlap|V tomto čase už máš rezervaci.|You already have a booking at this time.
reservations.period.morning|Ráno|Morning
reservations.period.afternoon|Odpoledne|Afternoon
reservations.period.evening|Večer|Evening
reservations.available|Vyber si svůj čas.|Choose your time.
reservations.date|Datum tréninku|Workout date
reservations.noSlots|V tento den nejsou dostupné termíny.|No time slots available on this day.
reservations.reserve|Rezervovat|Book session
reservations.detail|Tvůj další trénink|Your next workout
reservations.confirmBody|Zaplatíš Apple Pay přímo v aplikaci. Po potvrzení platby se termíny rezervují.|You'll pay with Apple Pay in the app. After payment the slots are booked.
reservations.confirmAction|Potvrdit rezervaci|Confirm booking
reservations.confirmed|Změna byla potvrzena serverem|Change confirmed by the server
reservations.selectHint|Označ všechny termíny, které chceš, a zaplať je najednou.|Mark every slot you want, then pay for them together.
reservations.checkout|Potvrdit a zaplatit|Confirm and pay
reservations.checkoutHint|Vybrané termíny zaplatíš v dalším kroku.|You'll pay for the selected slots next.
reservations.checkoutTitle|Shrnutí rezervace|Booking summary
reservations.checkoutCountOne|1 vstup|1 entry
reservations.checkoutCountMany|vstupy|entries
reservations.entryOne|vstup|entry
reservations.whereTitle|Kam jdeš|Where you're going
reservations.whenTitle|Kdy|When
reservations.roomsOne|1 místnost|1 room
reservations.roomsMany|místnosti|rooms
reservations.roomOne|místnost|room
reservations.intoRoom|do|in
reservations.payFooter|K úhradě|Due now
reservations.nextSession|Další trénink|Next session
reservations.happening|Právě teď|Happening now
reservations.confirmedBadge|Potvrzeno|Confirmed
reservations.pastBadge|Proběhlo|Completed
reservations.pay|Zaplatit Apple Pay|Pay with Apple Pay
reservations.payDemo|V demu se Apple Pay otevře na zařízení s kartou, ale nic nestrhne. V simulátoru můžeš platbu ověřit bez karty.|In demo, Apple Pay opens on a device with a card but nothing is charged. In Simulator you can verify the booking without a card.
reservations.payDemoAction|Ověřit platbu v demu|Verify payment in demo
reservations.applePayUnavailable|Apple Pay na tomto zařízení není k dispozici. Přidej kartu v aplikaci Peněženka.|Apple Pay isn’t available on this device. Add a card in the Wallet app.
reservations.applePayFailed|Apple Pay se nepodařilo otevřít. Na zařízení s kartou v Peněžence to zkus znovu.|Apple Pay couldn’t be opened. Try again on a device with a card in Wallet.
reservations.applePay.itemOne|Rezervace termínu|Session booking
reservations.applePay.itemMany|rezervované termíny|booked sessions
reservations.paid|Platba prošla. Termíny jsou rezervované.|Payment succeeded. Your slots are booked.
reservations.cartOne|1 vybraný termín|1 selected slot
reservations.cartMany|vybrané termíny|selected slots
reservations.clearCart|Zrušit výběr|Clear selection
reservations.remove|Odebrat|Remove
reservations.total|Celkem|Total
reservations.perSlot|Cena za termín|Price per slot
reservations.cancel|Zrušit rezervaci|Cancel booking
reservations.cancelConfirm|Opravdu zrušit tento termín?|Cancel this booking?
reservations.example|Ilustrační rezervace|Illustrative booking
reservations.example.time|Zítra · 17:00–18:00|Tomorrow · 5–6 pm
reservations.uncertain|Výsledek zatím nelze potvrdit. Aktualizuj seznam před další rezervací.|The result could not be confirmed. Refresh your bookings before trying again.
door.entryUntil|Serverem potvrzený vstup do|Server-confirmed entry until
door.open|Otevřít dveře|Open door
door.guest|Pro vstup se přihlas.|Sign in to enter.
door.eligible|Server aktuálně povoluje vstup. Před otevřením ověříme znovu.|Entry is currently allowed. We will verify again before opening.
door.checkAgain|Oprávnění ověříme před vstupem.|We will verify your access before entry.
door.entry.title|Tvůj trénink začíná tady.|Your workout starts here.
door.entry.body|Postav se před vstup. Připrav telefon a potvrď otevření.|Stand at the entrance. Get your phone ready and confirm entry.
door.security|Každý vstup ověřuje server PRIVOFIT.|Every entry is verified by the PRIVOFIT server.
door.ready|Připravený vstoupit?|Ready to enter?
door.checking|Ověřujeme oprávnění…|Checking access…
door.authenticating|Potvrď svou identitu.|Confirm your identity.
door.sending|Čekáme na potvrzení…|Waiting for confirmation…
door.success|Dveře jsou otevřené.|The door is open.
door.cooldown|Chvilku počkej.|Please wait a moment.
door.accepted|Požadavek byl přijat.|Request accepted.
door.uncertain|Stav vstupu není potvrzený.|Entry status is unconfirmed.
door.denied|Vstup nebyl povolen.|Access denied.
door.failed|Vstup se nepodařil.|Entry failed.
door.entrance|Vstup PRIVOFIT|PRIVOFIT entrance
door.confirmAction|Připravit otevření|Prepare entry
door.confirmHint|V dalším kroku otevření potvrdíš.|Confirm opening in the next step.
door.reconcile|Ověřit stav požadavku|Check request status
door.confirmTitle|Stojíš před dveřmi?|Are you at the door?
door.confirmBody|Potvrzením požádáš o jednorázové otevření. Nejdřív ověříme oprávnění a identitu.|Confirm to request one opening. We will verify your permission and identity first.
door.ready.body|Otevření vyžaduje potvrzení a platné oprávnění ze serveru.|Opening requires confirmation and valid server permission.
door.success.body|Server potvrdil otevření. Můžeš vstoupit. Aktuální fyzický stav dál nesledujeme.|The server confirmed opening. You may enter. We are not continuously monitoring the physical door.
door.cooldown.body|Krátká pauza chrání před opakovaným požadavkem. Nejde o dobu odemčení dveří.|A brief pause prevents repeated requests. This is not the door unlock duration.
door.failure.body|Zkontroluj členství a připojení. Pokud potíže trvají, kontaktuj podporu.|Check your membership and connection. Contact support if the issue persists.
door.failure.denied.body|Teď nemáš platný vstup. Zkontroluj rezervaci nebo členství.|You don't have valid entry right now. Check your booking or membership.
door.biometry.failed|Ověření se nepovedlo. Dveře zůstávají zavřené.|Identity check failed. The door stays closed.
door.uncertain.body|Neposíláme další příkaz. Nejprve ověř stav na serveru; dveře nemusí být otevřené.|We will not send another command. Check the server status first; the door may not be open.
door.wait|Nezavírej prosím tuto obrazovku.|Please keep this screen open.
settings.title|Nastavení|Settings
settings.appearance|Vzhled|Appearance
settings.security|Zabezpečení|Security
settings.biometry.body|Biometrie uzamkne aplikaci po opuštění a potvrdí vstup do fitka.|Biometrics lock the app when you leave and confirm gym entry.
settings.system|Otevřít systémové nastavení|Open system settings
appearance.system|Podle systému|System
appearance.dark|Tmavý|Dark
appearance.light|Světlý|Light
notifications.title|Oznámení|Notifications
notifications.allowed|Oznámení jsou povolená.|Notifications are allowed.
notifications.denied|Oznámení jsou vypnutá v iOS. Zapni je v Nastavení systému, aby ti mohla chodit.|Notifications are off in iOS. Turn them on in system Settings to receive them.
notifications.notSet|Povol oznámení, abys mohl vybrat, které typy ti mají chodit.|Allow notifications so you can choose which types you receive.
notifications.enable|Povolit oznámení|Allow notifications
notifications.push|Push oznámení|Push notifications
notifications.footer|Token se po přihlášení odešle na backend. Typy oznámení můžeš kdykoli změnit.|The token is sent to the backend after sign-in. You can change notification types anytime.
notifications.registration.failed|Oznámení zatím nebyla připojena k účtu.|Notifications have not been linked to your account yet.
notifications.empty|Zatím žádná oznámení|No notifications yet
notifications.channel.reservations|Rezervace|Reservations
notifications.channel.reservations.body|Připomínky a změny tréninků|Reminders and changes to workouts
notifications.channel.door|Vstup|Entry
notifications.channel.door.body|Potvrzení a stav otevření dveří|Door confirmation and status
notifications.channel.membership|Členství|Membership
notifications.channel.membership.body|Platnost členství a zbývající vstupy|Membership validity and remaining visits
notifications.channel.gym|Novinky z fitka|Gym news
notifications.channel.gym.body|Oznámení provozovatele a systémové zprávy|Operator announcements and system messages
link.unavailable|Odkaz zatím není dostupný.|Link not available yet.
link.unavailable.body|Tuto část ještě připojujeme. Zkus to prosím později.|This section is not connected yet. Please try again later.
skeleton.membership|Tvoje členství|Your membership
skeleton.body|Načítáme tvůj prostor.|Loading your space.
'''
# Escaped newlines in this source are handled explicitly below.
rows += r"""
redesign.guestGreeting|Máš prostor.|Make room for yourself.
redesign.dashboardSubtitle|Dnes je dobrý den udělat něco pro sebe.|Today is a good day to do something for yourself.
redesign.upNext|Tvůj další trénink|Your next workout
redesign.allBookings|Všechny|View all
redesign.privateSpace|TVŮJ SOUKROMÝ PROSTOR|YOUR PRIVATE SPACE
redesign.accessAvailable|Vstup je dostupný|Entry available
redesign.authWelcome|Vítej\nzpátky.|Welcome\nback.
redesign.authSubtitle|Tvůj prostor.\nJeden dotyk od tréninku.|Your space.\nA touch away from your workout.
redesign.orAccount|nebo přes svůj účet|or with your account
redesign.identifierExample|E-mail / username|Email / username
redesign.passwordPlaceholder|Tvoje heslo|Your password
redesign.emailExample|ty@example.com|you@example.com
redesign.newHere|Jsi tu poprvé?|New here?
redesign.explore|Prohlédnout|Explore
redesign.registration.0.title|Začíná to tebou.|It starts with you.
redesign.registration.0.body|Pojďme vytvořit tvůj účet. Nejdřív se seznamme.|Let's create your account. First, a little introduction.
redesign.registration.1.title|Zůstaneme v kontaktu.|Stay connected.
redesign.registration.1.body|Na e-mail ti pošleme vše důležité k tvému účtu a rezervacím.|We'll email you important account and booking information.
redesign.registration.2.title|Klíč máš jen ty.|The key is yours.
redesign.registration.2.body|Zabezpeč svůj účet heslem. A můžeš začít.|Protect your account with a password. You're nearly there.
redesign.digitalPass|DIGITÁLNÍ ČLENSKÁ KARTA|DIGITAL MEMBER PASS
redesign.entry.1|Postav se před vstup do fitka.|Stand at the gym entrance.
redesign.entry.2|Potvrď otevření a ověř se Face ID nebo Touch ID.|Confirm entry and verify with Face ID or Touch ID.
redesign.entry.3|Počkej na potvrzení. A pojď dovnitř.|Wait for confirmation. Then step inside.
redesign.backToOverview|Zpět do přehledu|Back to overview
redesign.doorReadyBody|Potvrď otevření. Oprávnění bezpečně ověříme za tebe.|Confirm entry. We'll securely check your access.
redesign.reminderTitle|Tvůj trénink se blíží.|Your workout is coming up.
redesign.reminderExample|Ukázka připomenutí rezervace|Sample booking reminder
home.book|Rezervovat|Book
home.sessionEmpty|Vyber si termín a prostor bude tvůj.|Pick a time and the space is yours.
home.hi|Ahoj,|Hi,
home.line.morning|Ještě je klid. Tvůj prostor čeká.|It's still quiet. Your space is waiting.
home.line.day|Dnes je dobrý den na trénink.|Today is a good day to train.
home.line.evening|Večer patří tobě.|The evening is yours.
home.line.now|Právě teď máš prostor.|You have the space right now.
home.line.today|Dnes máš trénink v|You have a session at
home.now|Právě teď|Right now
home.sessionHint|Jeden termín a prostor je jen tvůj.|One booking and the space is yours.
home.doorHint|Vstup na jeden dotyk|Entry in one tap
home.bookHint|Vyber si volný čas|Pick an open time
home.entry.one|zbývající vstup|entry left
home.entry.many|zbývajících vstupů|entries left
home.week|Tento týden|This week
home.week.empty|zatím volno|still open
home.week.one|trénink|session
home.week.many|tréninky|sessions
home.private.title|Jen ty.|Just you.
home.private.body|Žádný dav. Žádné čekání na stroje.|No crowd. No waiting for machines.
home.inbox|Nová zpráva|New message
"""
entries={}
for row in rows.strip().splitlines():
    if '|' not in row: continue
    key,cs,en=row.split('|',2)
    entries[key]={'extractionState':'manual','localizations':{lang:{'stringUnit':{'state':'translated','value':value.replace('\\n','\n')}} for lang,value in [('cs',cs),('en',en)]}}
# Multiline slogans are explicit to keep the table readable and unambiguous.
for key,cs,en in [('auth.headline','Tvoje tělo.\nTvoje tempo.','Your body.\nYour pace.'),('pass.headline','TVŮJ PROSTOR.\nTVOJE TEMPO.','YOUR SPACE.\nYOUR PACE.')]:
    entries[key]={'extractionState':'manual','localizations':{lang:{'stringUnit':{'state':'translated','value':value}} for lang,value in [('cs',cs),('en',en)]}}
(root/'Privofit/Resources/Localizable.xcstrings').write_text(json.dumps({'sourceLanguage':'cs','strings':entries,'version':'1.0'},ensure_ascii=False,indent=2))
print(f'{len(entries)} localized keys')
