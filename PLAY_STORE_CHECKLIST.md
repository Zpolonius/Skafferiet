# Google Play Store — Release Checklist

Baseret på kodeanalyse maj 2026.

---

## 🔴 Kritisk — Fix inden release

- [ ] Tilføj app-ikon (alle densities) — `android/app/src/main/res/mipmap-*/`
- [x] Tilføj INTERNET-permission i `android/app/src/main/AndroidManifest.xml`
- [x] Ret app-navn fra `"skafferiet"` til `"Skafferiet"` i AndroidManifest.xml
- [ ] Fjern alle `print()`-statements fra production-kode
  - `lib/features/auth/login_screen.dart:134–142`
  - `lib/features/profile/household_provider.dart:90`
  - `lib/features/profile/profile_screen.dart:196`

---

## 🟠 Høj — Vigtig for Play Store godkendelse

- [x] Implementer "Tilføj til madplan"-funktionen (`add_to_meal_plan_sheet.dart`)
- [ ] Implementer billede-picker til dagligvarer eller fjern knappen (`add_grocery_item_sheet.dart:87`)
- [ ] Opret og commit `firestore.rules` og `storage.rules` til repo
- [ ] Tilføj input-validering på login (email-format + password min. 6 tegn)
- [ ] Vis fejlbeskeder til brugeren i stedet for `print()` i providers
  - `household_provider.dart`
  - `recipes_provider.dart`

---

## 🟡 Medium — Kvalitet og UX

- [ ] Aktivér R8/ProGuard minifikation i `android/app/build.gradle.kts`
- [ ] Erstat `Image.network()` med `CachedNetworkImage` (`home_screen.dart:374`)
- [ ] Tilføj offline-fejl-UI (f.eks. `connectivity_plus` pakken)
- [ ] Fiksér Dark Mode toggle — `onChanged` er tom (`profile_screen.dart:98–102`)
- [ ] Fiksér Notifications-knap — gør intet pt.

---

## 🎨 Design-gap — Implementering matcher ikke mockups

### Høj prioritet
- [ ] **Profil:** Tilføj stats-række (antal opskrifter / madplaner / gemte varer)
- [ ] **Profil:** Tilføj manglende menupunkter: Mine opskrifter, Præferencer & Diæt, Hjælp & Support
- [ ] **Madplan:** Vis kalorie-sum badge ved siden af dagsoverskriften (f.eks. `1.850 kcal`)
- [ ] **Tilføj til madplan:** Implementer faktisk Firestore-skrivning (`add_to_meal_plan_sheet.dart:106`)

### Medium prioritet
- [ ] **Home:** Tilføj Snack-slot i "Dagens Plan" (viser kun 3 måltider, designet har 4)
- [ ] **Del & Samarbejd:** Vis medlemsliste med roller (Ejer / Kan redigere) direkte på profil-siden
- [ ] **Madplan:** Tilføj "Tilføj til indkøb"-knap på Direct Entry snack-kort

---

## 🟢 Lav — Nice to have

- [ ] Branded splash screen
- [ ] Onboarding-flow for nye brugere (husstand oprettes nu usynligt i baggrunden)
- [ ] **Profil:** Profilbillede med redigerings-ikon (viser nu kun bogstav-avatar)
