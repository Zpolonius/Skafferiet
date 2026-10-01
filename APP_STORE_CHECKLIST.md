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

## 🍎 2. Apple-krav der giver afvisning — ✅ koden er klar

- [x] **Slet konto i appen** (Guideline 5.1.1(v)) — Profil → Konto → Slet konto. Kræver adgangskoden og forklarer først, hvad der slettes. Rækkefølge i `AccountDeletionService`: bekræft adgangskode → ryd op i husstanden (eneste medlem: alt slettes; ellers meldes man ud og ejerskabet gives videre) → invitationer → profilbillede → profil → login-konto. Kan køres igen, hvis den afbrydes. 13 tests + 9 regel-tests mod emulatoren
- [x] **"Glemt adgangskode?"** sender nu en nulstillingsmail (på dansk) og afslører ikke, om e-mailen har en konto
- [x] **Privatlivspolitik** i appen (Profil → Konto, og fra login/opret konto — også uden at være logget ind) og som [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) til hosting. Én kilde: `lib/features/legal/privacy_policy_content.dart` → `dart run tool/export_privacy_policy.dart`. En test fejler, hvis de to er ude af trit
- [x] Nye invitationer gemmer afsenderens `fromUid`, så de kan slettes med kontoen (reglerne forhindrer at udgive sig for en anden)
- [x] Sign in with Apple — *ikke* påkrævet, da der kun er e-mail-login (kræves først ved Google/Facebook-login)

### ⚠️ Skal gøres manuelt
- [ ] **Udfyld kontaktoplysninger** i `lib/core/app_info.dart` (`dataControllerName`, `contactEmail` står som pladsholdere) og kør `dart run tool/export_privacy_policy.dart`
- [ ] **Læs privatlivspolitikken igennem** — den beskriver det appen gør i dag, men er ikke juridisk rådgivning
- [ ] **Host `docs/PRIVACY_POLICY.md`** (fx GitHub Pages) og indsæt URL'en i App Store Connect
- [ ] **Deploy reglerne** igen: `firebase deploy --only firestore:rules,storage` (nye slette-regler)
- [ ] **Support-URL** i App Store Connect (kan være samme side, til Hjælp & Support er bygget i punkt 3)
- [ ] **Demo-konto til Apples reviewer** — opret en testbruger med en husstand, et par opskrifter og en indkøbsliste, og skriv login i "App Review Information"
- [ ] **App Privacy-deklaration** i App Store Connect — skal matche `ios/Runner/PrivacyInfo.xcprivacy`: Navn, E-mail, Bruger-ID, Fotos, Andet brugerindhold. Alle "knyttet til brugeren", "ikke sporing", formål "App-funktionalitet"
- [ ] "Kommer snart"-menupunkterne (Notifikationer, Præferencer, Hjælp) bygges eller skjules i punkt 3 — ellers afvisning efter Guideline 2.1

### iOS-projektet (`ios/`)
- [x] `IPHONEOS_DEPLOYMENT_TARGET` 13.0 → **15.0** — bekræftet: `firebase_core` kræver iOS 15 (Firebase iOS SDK 12)
- [x] Kun iPhone (`TARGETED_DEVICE_FAMILY = 1`) — ingen iPad-screenshots eller -layout nødvendigt i v1
- [x] Kun stående skærm på iPhone
- [x] `ITSAppUsesNonExemptEncryption = false` i `Info.plist`
- [x] `PrivacyInfo.xcprivacy` tilføjet og registreret i Runner-targetets Resources
- [x] `NSUserNotificationUsageDescription` fjernet
- [x] `firebase_messaging` fjernet (ubrugt) — tilføjes igen, når push bygges
- [ ] `ios/Runner/GoogleService-Info.plist` mangler i repoet (git-ignoreret som `firebase_options.dart`) — skal med ved build
- [ ] **Første build på en Mac:** `flutter build ios` → åbn `ios/Runner.xcworkspace` i Xcode og tjek at projektet åbner, signing virker, og at `PrivacyInfo.xcprivacy` ligger under Runner. Projektfilen er redigeret uden Xcode (valideret med en parser, men ikke bygget)

### Konto & bygning
- [ ] Apple Developer Program (99 USD/år)
- [ ] Bundle ID `com.skafferiet.skafferiet` registreret i App Store Connect
- [ ] Mac med Xcode — eller byggetjeneste (fx Codemagic)

---

## 🧭 3. Profil-menuen — ✅ Gennemført

Ingen "Kommer snart" tilbage — Apple afviser apps med pladsholdere (retningslinje 2.1).

- [x] **Hjælp & Support** (`/profile/help`) — FAQ, "Skriv til os" (åbner mail-appen; findes der ingen, kopieres adressen), privatlivspolitik og app-version
- [x] **Husstand & deling** (`/profile/household`, erstatter "Delte lister"):
  - [x] Del invitationskode / deltag med kode *(fra punkt 1, flyttet hertil)*
  - [x] Forlad husstand — med bekræftelse; man får en ny, tom husstand i samme batch og sendes ikke gennem onboarding igen. Ikke muligt som eneste medlem (data ville ellers ligge tilbage, uden at nogen kan se eller slette dem)
  - [x] Ejer kan fjerne medlemmer — med bekræftelse. Husstandens invitationskoder slettes i samme batch, så den fjernede ikke kan komme ind igen med en gemt kode
  - [x] Se og annullér ventende invitationer
  - [x] "Invitation sendt" vises først, når invitationen er gemt; fejl (fx allerede inviteret, din egen e-mail) vises i dialogen. Teksten siger ærligt, at der ikke sendes en mail
  - [x] Accept af en invitation advarer først om, at den nuværende husstand forlades — og om data går tabt, hvis man er eneste medlem
  - [x] En fjernet bruger får automatisk en ny husstand og en besked ("Du er ikke længere medlem af …"), uanset hvilken skærm de står på
- [x] **Præferencer & Diæt** (`/profile/preferences`) — genbruger onboardingens vælgere (nu i `onboarding/household_setup_widgets.dart`)
- [x] **Notifikationer** — fjernet fra menuen i v1 (se nedenfor)
- [x] **Konto** — skift navn, skift adgangskode (`/profile/change-password`), privatlivspolitik, slet konto
- [x] Bekræftelse før "Log ud"

### ⚠️ Skal gøres manuelt
- [ ] **Deploy reglerne igen** (`firebase deploy --only firestore:rules`) — medlemmer skal nu kunne liste husstandens invitationskoder, ellers fejler "Fjern medlem"
- [ ] **Udfyld `AppInfo.contactEmail`** i `lib/core/app_info.dart` — bruges nu også af "Skriv til os"
- [ ] Første iOS-build: kør `pod install` — `url_launcher` og `package_info_plus` er nye

### Bevidst udskudt
- **Notifikationer** (fx "Hvad skal I have i aften?"): kræver `flutter_local_notifications`, en tilladelsesdialog og test på en rigtig iPhone. Bedre som v1.1 end halvfærdigt i v1
- **Præferencerne bruges stadig ingen steder** i appen. Siden er ærlig om det (lover ingen effekt), men en naturlig næste ting er at bruge antal personer som standard-portioner
- **Eneste medlem der deltager i en anden husstand** efterlader den gamle husstand uden medlemmer. Brugeren advares nu, men data slettes ikke automatisk

---

## 🧪 4. QA & UI-oprydning

- [ ] Login: fejl-snackbaren vises igen ved hver genopbygning, så længe fejlen står i state (`login_screen.dart`, `addPostFrameCallback` i `build`)
- [x] Login: "Har du ikke en konto? Tilmeld dig" løb ud af skærmen ved stor tekst — nu `Wrap`
- [x] Profilskærmen bruger hårdkodede farver — hele profilen og dens undersider følger nu temaet og mockuppene (`profilside_1`, `del_samarbejd_1`); `test/design_system_test.dart` holder dem rene
- [x] Temaet manglede de fleste tekstroller (dialogtitler, ListTile m.m. faldt tilbage til Roboto) og fladefarverne (`surfaceContainer*`) — nu komplet og testet
- [ ] Resten af appen (login, onboarding, madplan, indkøb, opskrifter, bundmenu) bruger stadig `AppColors`/`GoogleFonts` direkte — læg dem om én ad gangen og tilføj dem til `test/design_system_test.dart`
- [ ] Stats-label "MADPLANER" tæller dage i *denne uge* — omdøb eller tæl rigtigt
- [x] "Aktiv" ved husstanden er hårdkodet — fjernet i punkt 3
- [x] Invitationsdialogen findes i to identiske kopier — nu én, i `household_dialogs.dart`
- [x] `TextEditingController`s i profilens dialoger disposes nu (dialogerne ejer selv deres felter). Tjek resten af appen
- [x] Widget-tests for hvert nyt menupunkt (`profile_screen_test.dart`, `household_screen_test.dart`, `profile_subpages_test.dart`)
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
