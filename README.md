# Skafferiet - Kitchen Harmony

En moderne indkøbs- og madplanlægnings-app bygget med Flutter og Firebase.

## Status
Appen er pt. i prototype-fasen med fuldt implementeret UI og mock-data. 

### Implementerede Features:
- **Madplan**: Ugevisning med 4 daglige slots (Morgenmad, Frokost, Aftensmad, Snack).
- **Indkøbsliste**: Kategorisering, swipe-to-check (venstre), swipe-to-delete (højre), og mængde-vælger.
- **Opskrifter**: Bento-grid layout med kategorifiltrering.
- **Design System**: "Kitchen Harmony" – et lyst, friskt og minimalistisk design.

## Kom i gang

1. **Installér afhængigheder**:
   ```bash
   flutter pub get
   ```

2. **Kør appen**:
   ```bash
   flutter run
   ```

3. **Firebase Setup (Næste skridt)**:
   - Kør `flutterfire configure` for at forbinde projektet til din Firebase-instans.
   - Aktivér Firestore og Authentication.

## Arkitektur
- **State Management**: Flutter Riverpod
- **Navigation**: GoRouter
- **Design**: Custom Theme (Material 3) + Google Fonts (Plus Jakarta Sans & Be Vietnam Pro)
