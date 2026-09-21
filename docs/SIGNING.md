# Signering af release-builds

Denne guide beskriver, hvordan Skafferiet signeres til Google Play Store.
Den skal følges én gang — derefter fungerer `flutter build appbundle --release`
uden videre på den maskine.

---

## Hvorfor det betyder noget

Google Play identificerer en app ud fra **både** dens `applicationId`
(`com.skafferiet.skafferiet`) **og** den nøgle, den er signeret med. En app,
der er signeret med en anden nøgle end den første upload, bliver afvist som
en fremmed app.

> ⚠️ **Mister du din upload-keystore eller dens adgangskoder, kan du ikke
> længere udgive opdateringer til den eksisterende app.** Der findes ingen
> selvbetjent gendannelse. Tag backup, før du uploader første gang.

---

## Sådan er det sat op

Signering styres af `android/app/build.gradle.kts`, som læser hemmeligheder
fra `android/key.properties`. Den fil er git-ignored og må **aldrig** committes.

```
android/
├── key.properties            ← dine hemmeligheder (git-ignored, laver du selv)
├── key.properties.example    ← skabelon (committet)
└── app/build.gradle.kts      ← læser filen og opsætter signingConfig
```

**Fallback:** Findes `key.properties` ikke — f.eks. i CI, i en git worktree
eller hos en ny udvikler — falder release-builds tilbage til debug-nøgler, så
`flutter build` stadig virker. Gradle udskriver en advarsel:

```
ADVARSEL: android/key.properties mangler. Release-builden signeres med
debug-nøgler og kan ikke uploades til Play Store.
```

Flutter filtrerer normalt den linje væk. Vil du se den, brug `--verbose`.
Se afsnittet **Verificér signaturen** for en pålidelig kontrol.

---

## Opsætning, trin for trin

### 1. Generér en upload-keystore

Gem den **uden for** repoet, så den aldrig kan blive committet ved et uheld.
Opret f.eks. `C:/Users/<dig>/keys/` først.

```bash
keytool -genkeypair -v -keystore C:/Users/<dig>/keys/skafferiet-upload.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` følger med en JDK. Har du ikke kommandoen i din PATH, ligger den
typisk under `<JDK>/bin/keytool.exe` eller i Android Studios medfølgende JDK
(`<Android Studio>/jbr/bin/`).

Undervejs bliver du bedt om:

| Prompt | Hvad du skriver |
|---|---|
| Adgangskode til keystore | Vælg en stærk adgangskode — gem den i din adgangskodemanager |
| Navn, afdeling, organisation, by, land | Reelle oplysninger; de indgår i certifikatet, men vises ikke til brugerne |
| Adgangskode til nøgle | Kan godt være den samme som keystore-adgangskoden |

`-validity 10000` (ca. 27 år) er Googles anbefaling. Udløber certifikatet,
kan du ikke længere udgive opdateringer.

### 2. Opret `android/key.properties`

Kopiér skabelonen og udfyld den:

```bash
cp android/key.properties.example android/key.properties
```

```properties
storeFile=C:/Users/<dig>/keys/skafferiet-upload.jks
storePassword=<din keystore-adgangskode>
keyAlias=upload
keyPassword=<din nøgle-adgangskode>
```

**Om stien:** brug en absolut sti med skråstreger (`/`), også på Windows.
Relative stier fortolkes ud fra `android/app/` og bliver let forvirrende.
Baglæns skråstreger (`\`) fortolkes som escape-tegn i `.properties`-filer og
går i stykker.

### 3. Byg

```bash
flutter build appbundle --release
```

Resultatet ligger i `build/app/outputs/bundle/release/app-release.aab` og er
den fil, du uploader til Play Console.

---

## Verificér signaturen

Byggeloggen siger ikke, hvilken nøgle der blev brugt. Kontrollér det direkte
på artefaktet — det er den eneste pålidelige metode:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

`apksigner` ligger i Android SDK'et under
`<SDK>/build-tools/<version>/apksigner.bat`.

Er alt korrekt, matcher `certificate DN` de oplysninger, du indtastede i
trin 1. **Står der `CN=Android Debug`, er builden signeret med debug-nøgler**
og kan ikke uploades — så blev `key.properties` ikke fundet.

---

## Backup

Mindst to af disse, på hver sin lokation:

- Keystore-filen (`.jks`) — behandl den som en hemmelighed på linje med en adgangskode
- Begge adgangskoder samt alias — i en adgangskodemanager
- SHA-256-fingeraftrykket fra `apksigner`-outputtet, så du kan verificere en gendannet fil

**Overvej Play App Signing.** Google opbevarer da den endelige app-signeringsnøgle,
og din lokale keystore bliver blot en *upload*-nøgle, som Google kan nulstille,
hvis du mister den. Det fjerner den værste enkeltrisiko ved at udgive. Slås til
i Play Console ved første upload.

---

## Fejlfinding

| Symptom | Årsag |
|---|---|
| `apksigner` viser `CN=Android Debug` | `key.properties` blev ikke fundet. Filen skal ligge i `android/`, ikke i `android/app/` eller i repo-roden |
| `Keystore was tampered with, or password was incorrect` | Forkert `storePassword`, eller `storeFile` peger på en fil, der ikke er en keystore |
| `No key with alias 'upload' found` | `keyAlias` matcher ikke. Kør `keytool -list -v -keystore <fil>` for at se de faktiske aliasser |
| `FileNotFoundException` på keystoren | Sti-problem. Brug en absolut sti med `/` — ikke `\` |
| Play Console: *"Du har uploadet en APK, der er signeret med et certifikat, der ikke er gyldigt"* | Debug-signeret build. Samme årsag som første række |

---

## Relateret

- [PLAY_STORE_CHECKLIST.md](../PLAY_STORE_CHECKLIST.md) — samlet release-tjekliste
- [ROADMAP.md](../ROADMAP.md) — Fase 3: Play Store Release & Kvalitet
- `android/app/proguard-rules.pro` — R8-regler, der gælder for samme release-build
