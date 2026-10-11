# Udviklingsloop: udvikler → tester → godkendelse

En fast arbejdsgang for at løse ét GitHub-issue ad gangen i Skafferiet, så hver ændring er testet, gennemgået og afprøvet i den rigtige app, før den merges.

Flowet er uafhængigt af værktøj. Hver rolle kan udfyldes af en AI-agent (Claude Code, en anden kodeagent) eller af et menneske. Prompt-skabelonerne nederst kan kopieres direkte ind i en agent.

---

## Roller

| Rolle | Opgave | Må | Må ikke |
|---|---|---|---|
| **Udvikler** | Løser issuet: skriver først en test, der fejler, og retter derefter koden | Ændre kode og tests på issue-branchen | Committe, pushe, ændre `firestore.rules` uden at issuet beder om det, omformatere filer, den ikke ændrer |
| **Tester** | Gennemgår udviklerens arbejde kritisk og afgiver en dom | Køre alt, skrive ekstra tests under `test/` eller `e2e/tests/` | Ændre noget under `lib/`, committe, pushe |
| **Integrator** | Styrer loopet, laver den afsluttende kontrol, committer og opretter PR | Alt på issue-branchen | Merge |
| **Godkender (dig)** | Afprøver på egen PC eller telefon og merger | Merge | — |

**Tips til valg af model:** Udvikler og tester kan godt være billigere modeller. Brug gerne **to forskellige modeller** til udvikler og tester, for samme model har de samme blinde vinkler. Integratoren bør være den stærkeste model eller et menneske.

---

## Forudsætninger

- Flutter (samme version som `pubspec.lock` kræver), Node 18+, Java 21+.
- `lib/firebase_options.dart` (hentes med `flutterfire configure` – ligger ikke i git).
- E2E-opsætningen: `tool/e2e.sh` og `docs/E2E.md`. På egen PC én gang: `cd e2e && npm ci && npx playwright install chromium`.
- Issuet har **acceptkriterier** som en tjekliste. Mangler de, skal de skrives før loopet starter.

### Kendt udgangspunkt
Før et nyt issue: kør testene på `main` og skriv tallene ned. Så kan man se, om noget er blevet værre.

```bash
flutter test      # notér: X består, Y fejler (og hvilke)
flutter analyze   # notér antal issues
tool/e2e.sh       # notér resultat
```
Uden `lib/firebase_options.dart` fejler `test/widget_test.dart` og `flutter analyze` viser 2 fejl i `lib/main.dart`. Det er forventet.

---

## Flowet trin for trin

### 0. Vælg issue
Følg rækkefølgen i milestonen. Tjek, om issuet afhænger af en anden PR (står i issuet). Gør det, så skal issue-branchen tage udgangspunkt i den PR's branch i stedet for `main`.

### 1. Opret branch
```bash
git fetch origin
git switch -c claude/issue-<NR> origin/main
```
**Én branch og én PR pr. issue.**

### 2. Udvikler
Giv udvikleren [skabelonen nedenfor](#skabelon-udvikler). Krav:
1. **Skriv en test, der fejler, først.** Den skal fange fejlen eller kræve funktionen, og den skal fejle på `main` af den *rigtige* grund (en forkert værdi, ikke en manglende mock).
2. Lav så rettelsen.
3. Kør `flutter test`, `flutter analyze` og, hvis issuet rører UI eller data, `tool/e2e.sh`.
4. Kør kun `dart format` på **nye** filer, aldrig på hele eksisterende filer. Det giver støj i diffen.
5. Aflever en rapport: filer + én linje om hvorfor, nye tests, testtal, `git diff --stat` og hvad der er usikkert.

### 3. Tester
Giv testeren [skabelonen nedenfor](#skabelon-tester) **plus issuets acceptkriterier**. Testeren:
1. Beviser, at de nye tests fejler på den gamle kode, og at de fejler af den rigtige grund.
2. Kører alle unit-tests, analyse og e2e-tests.
3. Gennemgår diffen kritisk: kanttilfælde, fejlhåndtering, sikkerhed (Firestore-regler), UI-regler (tema, dansk tekst, tilgængelighed) og om eksisterende tests er blevet **svækket**.
4. **Afprøver brugerrejsen i den rigtige app** med en e2e-test.
5. Starter rapporten med `VERDICT: PASS` eller `VERDICT: CHANGES NEEDED` og går acceptkriterierne igennem ét for ét.

### 4. Loop
- `CHANGES NEEDED` → send testerens fund **uændret** tilbage til udvikleren. Bed om rettelser og en ny rapport. Send derefter til testeren igen.
- **Maks. 3 runder.** Er dommen ikke PASS efter 3 runder, stopper loopet, og et menneske kigger på det. Så er opgaven typisk uklar eller for stor.
- Der committes **ikke** mens loopet kører. Filerne er halvfærdige, og testeren bytter midlertidigt filer ud.

### 5. Integratorens afsluttende kontrol
Efter `VERDICT: PASS`:
1. Læs hele diffen selv (`git diff`). Se efter ting, begge agenter kan have overset, fx fælder i hjælpefunktioner, ubrugt kode og testfiler med rod.
2. Kør `flutter test`, `flutter analyze` og `tool/e2e.sh` igen, og sammenlign med udgangspunktet.
3. Tjek at ingen hemmeligheder eller `lib/firebase_options.dart` er med (`git status`).
4. Commit med en beskrivende besked (bydeform i emnelinjen og en brødtekst, der forklarer *hvorfor*), og skriv `Closes #<NR>` i brødteksten.

### 6. PR
```bash
git push -u origin claude/issue-<NR>
```
Opret PR'en mod `main` (eller mod den branch, issuet afhænger af). PR-beskrivelsen skal have:
- **Problem** – hvad brugeren oplevede, og årsagen.
- **Ændringer** – kort pr. fil eller område.
- **Tests** – nye tests og testtal før og efter.
- **Ikke testet** – vær ærlig, fx "ikke prøvet på iPhone".
- **Sådan afprøver du** – 2–3 konkrete trin til godkenderen.

### 7. Godkendelse (dig)
På din egen PC:
```bash
git fetch origin && git switch claude/issue-<NR>
flutter pub get
flutter test
tool/e2e.sh
flutter run            # på emulator eller telefon – følg "Sådan afprøver du"
```
Gå acceptkriterierne igennem i appen. Er alt i orden, så merge. Ellers skriv en kommentar på PR'en, og send den tilbage i loopet.

### 8. Efter merge
- Fjern `test.fail()`-markeringer i e2e-tests, der var markeret "Fjernes når #<NR> er merget".
- Hvis andre åbne branches bygger på denne, skal `main` merges ind i dem.
- Vælg næste issue.

---

## Faldgruber vi har lært af

| Faldgrube | Hvad gør man |
|---|---|
| Udvikleren omformaterer hele filer, og diffen vokser fra 200 til 500 linjer | Krav: `dart format` kun på nye filer. Testeren tjekker `git diff --stat` mod `git diff -w --stat`. |
| En test "fejler på den gamle kode", men kun fordi en mock mangler | Testeren skal vise *hvorfor* testen fejler. Det skal være en forkert værdi, ikke en manglende mock. |
| Unit-tests er grønne, men brugeren ser en spinner eller tom skærm | Testeren skal tænke på, hvad brugeren *ser*, mens data opdateres, og afprøve det med en e2e-test. |
| Udvikler og tester overser det samme | Brug to forskellige modeller, og lad integratoren læse hele diffen selv. |
| Testerens hjælpekode efterlader advarsler | `flutter analyze` i den afsluttende kontrol skal have samme antal issues som udgangspunktet. |
| Commit mens agenter arbejder | Commit først efter PASS og den afsluttende kontrol. |
| Netværk blokerer `gstatic.com` (Flutter Web og Firebase JS) | E2E-opsætningen leverer filerne fra npm. Se `docs/E2E.md`. |
| `lib/firebase_options.dart` kommer med i et commit | Den er git-ignored. Tjek `git status` før commit. |

---

## Skabeloner

Erstat `<NR>`, `<BRANCH>` og `<ACCEPTKRITERIER>`. Indsæt hele issue-teksten, hvor der står `<ISSUE-TEKST>`.

### Skabelon: Udvikler

```text
Du er udvikler på GitHub-issue #<NR> i Flutter-appen Skafferiet (repo-rod: <STI>, branch <BRANCH>).
Læs CLAUDE.md først og følg konventionerne (tema via context.colors/context.text, danske UI-tekster, tests i test/features/, mocktail).
Du må IKKE committe, pushe eller oprette PR'er. Ændr ikke firestore.rules medmindre issuet kræver det.

Issue:
<ISSUE-TEKST>

Udgangspunkt på main: <X> tests består, <Y> fejler (<hvilke og hvorfor>). flutter analyze: <N> issues.

Krav:
1. Skriv FØRST en test, der fejler på den nuværende kode af den rigtige grund (forkert adfærd, ikke en manglende mock). Kør den og vis, at den fejler.
2. Lav rettelsen. Bevar offentlige API'er, som andre filer bruger (grep efter kaldere), eller opdatér alle kaldere.
3. Rører issuet UI eller data, så tilføj eller opdatér en e2e-test i e2e/tests/ for brugerrejsen.
4. Kør flutter test, flutter analyze og tool/e2e.sh. Intet må blive værre end udgangspunktet.
5. Kør kun dart format på NYE filer. Omformatér ikke eksisterende filer.

Aflever: ændrede filer (én linje om hvorfor for hver), navne på nye tests, præcise testtal, `git diff --stat`, og hvad du er usikker på eller ikke nåede. Vær ærlig om fejl.
```

### Skabelon: Tester

```text
Du er tester og reviewer på en ikke-committet løsning af GitHub-issue #<NR> i Flutter-appen Skafferiet (repo-rod: <STI>, branch <BRANCH>; se `git diff` og `git status`).
Læs CLAUDE.md først. Du må IKKE committe, pushe eller ændre noget under lib/. Du må tilføje tests under test/ eller e2e/tests/ og skal liste dem.

Issue:
<ISSUE-TEKST>

Acceptkriterier:
<ACCEPTKRITERIER>

Udgangspunkt på main: <X> tests består, <Y> fejler. flutter analyze: <N> issues.

Opgave:
1. Bevis at de nye tests fejler på den gamle kode (hent filerne fra origin/main midlertidigt), og at de fejler af den RIGTIGE grund. Læg derefter udviklerens version tilbage, og tjek med `git diff --stat`, at den er uændret.
2. Kør flutter test, flutter analyze og tool/e2e.sh. Rapportér præcise tal.
3. Gennemgå diffen kritisk: kanttilfælde, fejlhåndtering, rækkefølge og timing, lækager, sikkerhed (Firestore-regler), UI-regler (tema, dansk, tilgængelighed og hvad brugeren SER mens data opdateres), om eksisterende tests er svækket, og om der er formateringsstøj (`git diff --stat` mod `git diff -w --stat`).
4. Afprøv brugerrejsen i den rigtige app med en e2e-test.
5. Skriv tests der afprøver de huller, du har mistanke om.

Rapport:
- Første linje: `VERDICT: PASS` eller `VERDICT: CHANGES NEEDED`.
- Hvert acceptkriterium: ✅ eller ❌ med dokumentation.
- Nummererede fund: alvor (blocker / should-fix / nit), fil:linje, hvad der er galt, bevis (testnavn og output) og forslag til rettelse. Marker gætterier som gætterier.
- Testtal og de testfiler, du har tilføjet.
```

### Skabelon: Tilbagemelding til udvikler (runde 2+)

```text
Testerens gennemgang af din løsning på #<NR> gav CHANGES NEEDED. Samme regler som før.
Ret disse fund:
<TESTERENS FUND, UÆNDRET>
Aflever en ny rapport i samme format.
```

---

## Tjekliste til integratoren (kopiér ind i PR'en eller dine noter)

- [ ] Testeren har givet `VERDICT: PASS`, og alle acceptkriterier er ✅
- [ ] Jeg har selv læst hele diffen
- [ ] `flutter test` er ikke værre end udgangspunktet
- [ ] `flutter analyze` er ikke værre end udgangspunktet
- [ ] `tool/e2e.sh` er grøn (eller `test.fail` med begrundelse)
- [ ] De nye tests fejler på `main` af den rigtige grund
- [ ] Ingen formateringsstøj, ingen ubrugt kode, ingen `firebase_options.dart`
- [ ] Commit-besked forklarer *hvorfor*, og `Closes #<NR>` er med
- [ ] PR-beskrivelsen har "Ikke testet" og "Sådan afprøver du"
