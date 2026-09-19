# Skafferiet - Kitchen Harmony

En moderne indkøbs- og madplanlægnings-app bygget med Flutter og Firebase.

## Status
Appen er fuldt integreret med Firebase (Authentication, Cloud Firestore, Firebase Storage) og understøtter delte husholdninger, madplanlægning i realtid og dynamiske indkøbslister.

### Implementerede Features:
- **Madplan**: Ugevisning med 4 daglige slots (Morgenmad, Frokost, Aftensmad, Snack), tilføjelse af opskrifter eller egne måltider, samt 1-klik overførsel af ingredienser til indkøbslisten.
- **Indkøbsliste**: Real-time synkronisering, kategorisering, reorder/sortering, swipe-to-check, swipe-to-delete og billed-upload.
- **Opskrifter**: Bento-grid layout med søgning og kategorifiltrering, samt oprettelse og redigering af opskrifter med billed-upload.
- **Husstand & Samarbejde**: Flere brugere kan dele madplan og indkøbsliste via e-mail invitationer, omdøbning af husstand og rollebaseret medlemsvisning.
- **Design System**: "Kitchen Harmony" – lyst, friskt og minimalistisk Material 3 design med typografi (Plus Jakarta Sans & Be Vietnam Pro).
- **Sikkerhed & Regler**: Fuldt afskærmede Firestore- og Storage-regler med data-isolation pr. husstand.

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

## Arkitektur
- **State Management**: Flutter Riverpod (v2.x) med `AsyncNotifier`, `StreamNotifier` og `StateNotifier`.
- **Navigation**: GoRouter med `StatefulShellRoute` (4 primære faner + sub-routes).
- **Backend**: Firebase Auth, Firestore og Firebase Storage.
- **Design**: Custom Theme (Material 3) + Google Fonts (Plus Jakarta Sans & Be Vietnam Pro).
