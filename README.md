# Skafferiet - Kitchen Harmony

En moderne indkøbs- og madplanlægnings-app bygget med Flutter og Firebase.

## Status
Appen er fuldt integreret med Firebase (Authentication, Cloud Firestore, Firebase Storage) og understøtter delte husholdninger, madplanlægning i realtid og dynamiske indkøbslister.

### Implementerede Features:
- **Onboarding (Den Personlige Setup-Wizard)**: 3-trins interaktivt flow for nye brugere (familiestørrelse, madstil-præferencer og instant aftensmad lagt direkte i madplanen og indkøbslisten).
- **Madplan**: Ugevisning med 4 daglige slots (Morgenmad, Frokost, Aftensmad, Snack), kalorie-sum badge (`🔥 1.850 kcal`), 1-klik overførsel af opskrift-ingredienser og fritekst-måltider til indkøbslisten.
- **Indkøbsliste**: Real-time synkronisering, kategorisering, reorder/sortering, swipe-to-check, swipe-to-delete, billed-upload og empty states med hurtighandlinger.
- **Opskrifter**: Bento-grid layout med søgning, kategorifiltrering, oprettelse og redigering af opskrifter med billed-upload samt 1-klik nulstilling ved tomme søgninger.
- **Husstand & Samarbejde**: Flere brugere kan dele madplan og indkøbsliste via e-mail invitationer, omdøbning af husstand og rollebaseret medlemsvisning.
- **Empty States**: Konsekvent `EmptyStateWidget` på tværs af appen med handlingsorienterede opfordringer.
- **Design System**: "Kitchen Harmony" – lyst, friskt og minimalistisk Material 3 design med typografi (Plus Jakarta Sans & Be Vietnam Pro).
- **Sikkerhed & Regler**: Fuldt afskærmede Firestore- og Storage-regler med streng data-isolation pr. husstand.

Se også:
- [Produkt & Udviklings-Roadmap](ROADMAP.md)
- [Google Play Store Release Checklist](PLAY_STORE_CHECKLIST.md)
- [Signering af release-builds](docs/SIGNING.md)
- [Dark Mode — analyse og plan](docs/DARK_MODE.md)

## Kom i gang

1. **Installér afhængigheder**:
   ```bash
   flutter pub get
   ```

2. **Kør appen**:
   ```bash
   flutter run
   ```

3. **Test og analyse**:
   ```bash
   flutter analyze
   flutter test
   ```

> **Bemærk:** `lib/firebase_options.dart` og `android/app/google-services.json`
> er git-ignored. De genereres med `flutterfire configure` og findes derfor ikke
> i et frisk klon eller i en git worktree — Android-builds fejler, indtil de er
> på plads.

## Release-builds

```bash
flutter build appbundle --release
```

Release-builds er minificerede med R8 (`android/app/proguard-rules.pro`) og
signeres med nøglen i den git-ignorerede `android/key.properties`. Mangler den
fil, falder builden tilbage til debug-nøgler og kan ikke uploades til Play Store.

Se [docs/SIGNING.md](docs/SIGNING.md) for opsætning og verifikation af signaturen.

## Arkitektur
- **State Management**: Flutter Riverpod (v2.x) med `AsyncNotifier`, `StreamNotifier` og `StateNotifier`.
- **Navigation**: GoRouter med `StatefulShellRoute` (4 primære faner + sub-routes).
- **Backend**: Firebase Auth, Firestore og Firebase Storage.
- **Design**: Custom Theme (Material 3) + Google Fonts (Plus Jakarta Sans & Be Vietnam Pro).
