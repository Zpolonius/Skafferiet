# Apple App Store — Analyse & Release Checklist

Baseret på kodeanalyse oktober 2026. Søster-dokument til [PLAY_STORE_CHECKLIST.md](PLAY_STORE_CHECKLIST.md) — det der står dér (signing, ikon, R8 m.m.) gælder Android; her er det iOS-specifikke plus profil-menuen, som begge platforme mangler.

**Rækkefølge:** 1 → 2 → 3 → 4. Sikkerheden kom først, fordi den ændrede hvordan man melder sig ind i en husstand — og det bygger "Husstand & deling" i punkt 3 videre på.

---

## Analyse: Profil-menuen (`lib/features/profile/profile_screen.dart`)

| Menupunkt | Status | Hvad det kræver |
|---|---|---|
| **Mine opskrifter** | ✅ Virker (hopper til Opskrifter-fanen) | Intet. Dublerer bundmenuen — kan fjernes |
| **Delte lister** | ⚠️ Åbner samme dialog som "Inviter et medlem" | Erstattes af en rigtig "Husstand & deling"-side (punkt 3) |
| **Notifikationer** | ❌ "Kommer snart" | Lokale påmindelser i v1; push (kræver server) i v1.1 |
| **Præferencer & Diæt** | ❌ "Kommer snart" | Data findes allerede fra onboarding — mangler redigeringsside |
| **Hjælp & Support** | ❌ "Kommer snart" | FAQ, kontakt, privatlivspolitik, version — Apple kræver alligevel support-URL |

> **Bemærk:** `preferences`, `adultsCount` og `childrenCount` gemmes, men **bruges ingen steder** i appen. Kan man redigere dem uden at noget ændrer sig, føles det i stykker. Giv dem en effekt (fx standard-portioner) eller hold siden meget enkel.

---

## 🔐 1. Sikkerhed — ✅ Gennemført

Testet mod Firebase-emulatoren: 49 tests i [`rules_test/`](rules_test/). Mod de gamle regler lykkedes **22 af angrebene** — nu blokeres de alle.

- [x] **Brugerlisten var åben** — enhver bruger kunne liste alle brugeres e-mail, navn og husstands-ID. Nu: kun egen profil + profiler i samme husstand, og ingen listning
- [x] **Man kunne pege sin profil på en fremmed husstand** og derved læse dens opskrifter. Nu: `householdId` kan kun sættes til en husstand man er medlem af
- [x] **Man kunne melde sig ind i enhver husstand** man kendte ID'et på (6 cifre = gætbart). Nu kræver indmeldelse et bevis: en gyldig invitationskode eller en invitation til ens egen e-mail
- [x] **Husstande kunne læses af alle**, der kendte ID'et. Nu kun af medlemmer
- [x] **Ethvert medlem kunne ændre alt** (gøre sig selv til ejer, smide andre ud). Nu: medlemmer må ændre navn/præferencer og forlade husstanden; kun ejeren kan fjerne andre og give ejerskab videre
- [x] **Alle kunne publicere "globale" opskrifter**, som alle brugere ser (spam/upassende indhold). Nu: nye opskrifter skal tilhøre en husstand
- [x] Opskrifters `createdBy`/`householdId` kan ikke ændres efter oprettelse
- [x] Invitationer: kun `status` kan ændres, og kun fra `pending` — et svar er endeligt
- [x] Grænser på længde/antal (husstandsnavn, medlemmer, præferencer, profilnavn)
- [x] **Nye invitationskoder** (`join_codes`): 10 tegn fra kryptografisk tilfældighed (~10¹⁵ muligheder), udløber efter 7 dage. Kan deles fra husstandskortet ("Del invitationskode") og indtastes via "Deltag i en anden husstand"
- [x] Husstands-ID'er laves nu med `Random.secure()` i stedet for `Random()`
- [x] **Lyttere lukkes ved log ud** — før kørte den forrige brugers Firestore-lyttere videre, når en ny bruger loggede ind på samme telefon
- [x] Skift af husstand sker i **ét atomart batch** (forlad gammel + meld ind i ny + accepter invitation) — før kunne en fejl undervejs efterlade brugeren i to husstande eller ingen
- [x] Ejer der forlader en husstand giver automatisk ejerskabet videre
- [x] Storage: filer i `users/` og `temp/` kan hentes, men ikke listes

### ⚠️ Skal gøres manuelt — ellers virker intet af ovenstående
- [ ] **Deploy reglerne:** `firebase deploy --only firestore:rules,storage`
- [ ] **Deploy samtidig med den nye app-version.** Den gamle app-kode for "accepter invitation" og "indtast kode" virker ikke med de nye regler (det er netop hullet, der er lukket)

### Tilbageværende risici (ikke kritiske, men noter dem)
- [ ] **E-mail-verifikation:** Firebase-konti med e-mail/adgangskode er ikke verificeret. Registrerer en angriber sig med en e-mail, der *endnu ikke* har en konto, kan de modtage invitationer sendt til den. Løsning: `sendEmailVerification()` ved oprettelse og kræv `email_verified` i invitation-reglen
- [ ] **Firebase App Check:** forhindrer at nogen kalder databasen direkte uden om appen (scriptede angreb, gæt-forsøg). Anbefales før release
- [ ] Invitationers `fromUserName` kan forfalskes af afsenderen (vises kun som tekst)

---

## 🍎 2. Apple-krav der giver afvisning

- [ ] **Slet konto i appen** (Guideline 5.1.1(v)) — kræver gen-login (`requires-recent-login`), sletning af `users/{uid}`, profilbillede i Storage, fjernelse fra husstanden (ejerskab videre / slet tom husstand). Mest robust som Cloud Function (`onDelete`), så data også ryddes hvis appen lukkes midt i
- [ ] **Ingen "Kommer snart" / døde knapper** (Guideline 2.1) — 3 menupunkter + **"Glemt adgangskode?"** (`login_screen.dart:174`, `onPressed: () {}`). Sidstnævnte er én linje: `sendPasswordResetEmail`
- [ ] **Privatlivspolitik** — skrives og hostes (fx GitHub Pages); link i appen og i App Store Connect
- [ ] **Support-URL** i App Store Connect (kan være samme side som Hjælp & Support)
- [ ] **Demo-konto til Apples reviewer** — appen kræver login
- [ ] **App Privacy-deklaration** i App Store Connect: e-mail, navn, fotos, brugerindhold (opskrifter/lister)
- [x] Sign in with Apple — *ikke* påkrævet, da der kun er e-mail-login (kræves først ved Google/Facebook-login)

### iOS-projektet (`ios/`)
- [ ] `IPHONEOS_DEPLOYMENT_TARGET = 13.0` → sandsynligvis **15.0** (nyeste Firebase-pakker). Viser sig ved første `pod install`
- [ ] `TARGETED_DEVICE_FAMILY = "1,2"` = iPad er slået til → kræver iPad-screenshots og -layout. Simplest i v1: kun iPhone (`"1"`)
- [ ] Liggende skærm er tilladt på iPhone (`Info.plist`) — layoutet er ikke lavet til det. Lås til portræt
- [ ] Tilføj `ITSAppUsesNonExemptEncryption = false` i `Info.plist` (slipper for eksport-spørgsmål ved hver upload)
- [ ] Tilføj `PrivacyInfo.xcprivacy` (Apples privatlivs-manifest)
- [ ] `NSUserNotificationUsageDescription` i `Info.plist` bruges ikke af iOS (notifikations-tilladelse kræver ingen forklaringstekst) — kan fjernes
- [ ] `firebase_messaging` er installeret men ubrugt → fjern hvis push ikke er med i v1 (ellers advarsel om manglende push-entitlement)
- [ ] `ios/Runner/GoogleService-Info.plist` mangler i repoet (git-ignoreret som `firebase_options.dart`) — skal med ved build

### Konto & bygning
- [ ] Apple Developer Program (99 USD/år)
- [ ] Bundle ID `com.skafferiet.skafferiet` registreret i App Store Connect
- [ ] Mac med Xcode — eller byggetjeneste (fx Codemagic)

---

## 🧭 3. Profil-menuen — bygges færdig

- [ ] **Hjælp & Support** — FAQ, "Kontakt os" (`mailto:` via `url_launcher`), privatlivspolitik, app-version
- [ ] **Husstand & deling** (erstatter "Delte lister"):
  - [x] Del invitationskode *(lavet i punkt 1)*
  - [x] Deltag i en anden husstand med kode *(lavet i punkt 1)*
  - [ ] Forlad husstand (`leaveHousehold()` findes og giver ejerskab videre — mangler knap + bekræftelse)
  - [ ] Ejer kan fjerne medlemmer (reglerne tillader det nu)
  - [ ] Se/annullér udsendte invitationer
  - [ ] "Invitation sendt" vises før serveren har svaret — også når det fejler (`profile_screen.dart`, `_showInviteDialog`)
  - [ ] Når man accepterer en invitation, forlades den nuværende husstand uden advarsel
  - [ ] Hvad ser en bruger, der er blevet fjernet? I dag: tomt husstandskort + besked "Du er ikke længere medlem"
- [ ] **Præferencer & Diæt** — redigeringsside der genbruger onboardingens vælgere
- [ ] **Notifikationer** — lokale påmindelser (fx "Hvad skal I have i aften?")
- [ ] **Ny "Konto"-sektion** — skift navn, skift adgangskode, **slet konto**, privatlivspolitik
- [ ] Bekræftelse før "Log ud"

---

## 🧪 4. QA & UI-oprydning

- [ ] Profilskærmen bruger hårdkodede farver (`Colors.red`, `Colors.green`, `Color(0xFFF8F9F8)`) — skal over på `Theme.of(context).colorScheme`
- [ ] Stats-label "MADPLANER" tæller dage i *denne uge* — omdøb eller tæl rigtigt
- [ ] "Aktiv" ved husstanden er hårdkodet
- [ ] Invitationsdialogen findes i to identiske kopier (`ProfileScreen` og `_HouseholdDetailCard`)
- [ ] `TextEditingController`s i dialoger disposes ikke
- [ ] Widget-tests for hvert nyt menupunkt i `test/features/profile_screen_test.dart`
- [ ] Test på fysisk iPhone (kamera/galleri-tilladelser, tastatur, safe area)
- [ ] Screenshots (6.9" og 6.5" iPhone), app-beskrivelse, nøgleord, kategori

---

## Sådan testes sikkerhedsreglerne

```bash
cd rules_test
npm install
npm test        # starter Firestore-emulatoren og kører alle regel-tests
```

Kræver Java 11+. Kør altid testene efter en ændring i `firestore.rules`.
