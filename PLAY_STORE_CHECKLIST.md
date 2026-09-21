# Google Play Store — Release Checklist

Baseret på kodeanalyse maj 2026, opdateret september 2026.

---

## 🔴 Kritisk — Fix inden release

- [x] Opsæt signing config til release-builds — [docs/SIGNING.md](docs/SIGNING.md)
- [ ] **Generér upload-keystore og opret `android/key.properties`** — uden den signeres release med debug-nøgler og afvises af Play Console. Følg [docs/SIGNING.md](docs/SIGNING.md)
- [x] Tilføj app-ikon (alle densities) — `android/app/src/main/res/mipmap-*/`
- [x] Tilføj INTERNET-permission i `android/app/src/main/AndroidManifest.xml`
- [x] Ret app-navn fra `"skafferiet"` til `"Skafferiet"` i AndroidManifest.xml
- [x] Fjern alle `print()`-statements fra production-kode
  - ~~`lib/features/auth/login_screen.dart:134–142`~~ ✓
  - ~~`lib/features/profile/household_provider.dart:90`~~ ✓
  - ~~`lib/features/profile/profile_screen.dart:196`~~ ✓

---

## 🟠 Høj — Vigtig for Play Store godkendelse

- [x] Implementer "Tilføj til madplan"-funktionen (`add_to_meal_plan_sheet.dart`) — 4 tests ✓
- [x] Implementer billede-picker til dagligvarer eller fjern knappen (`add_grocery_item_sheet.dart:87`)
- [x] Opret og commit `firestore.rules` og `storage.rules` til repo — kør `firebase deploy --only firestore:rules,storage`
- [x] Tilføj input-validering på login (email-format + password min. 6 tegn)
- [x] Vis fejlbeskeder til brugeren i stedet for `print()` i providers

---

## 🟡 Medium — Kvalitet og UX

- [x] Aktivér R8/ProGuard minifikation i `android/app/build.gradle.kts` — bundle 49,3 → 46,5 MB, regler i `android/app/proguard-rules.pro`
- [x] Erstat `Image.network()` med `CachedNetworkImage` (`home_screen.dart:374`)
- [x] Tilføj offline-fejl-UI (f.eks. `connectivity_plus` pakken)
- [ ] Implementér Dark Mode — kræver mørkt farvesæt + oprydning af 220 hårdkodede `AppColors`-opslag. Se [docs/DARK_MODE.md](docs/DARK_MODE.md)
- [ ] Fiksér Notifications-knap — viser pt. kun "Notifikationer kommer snart!"

---

## 🎨 Design-gap — Implementering matcher ikke mockups

### Høj prioritet
- [x] **Profil:** Tilføj stats-række (antal opskrifter / madplaner / gemte varer)
- [x] **Profil:** Tilføj manglende menupunkter: Mine opskrifter, Præferencer & Diæt, Hjælp & Support
- [x] **Del & Samarbejd:** Vis medlemsliste med roller (Ejer / Kan redigere) direkte på profil-siden
- [x] **Tilføj til madplan:** Implementer faktisk Firestore-skrivning (`add_to_meal_plan_sheet.dart:106`)
- [x] **Home:** Fiks ugedags-casing bug i "Dagens Plan" (`home_screen.dart:181`)
- [x] **Madplan:** Ret engelsk overskrift til dansk i `add_custom_meal_sheet.dart`

### Medium prioritet
- [x] **Home:** Tilføj Snack-slot i "Dagens Plan" (viser kun 3 måltider, designet har 4)
- [x] **Madplan:** Tilføj "Tilføj til indkøb"-knap på Direct Entry snack-kort

### lav prioritet
- [x] **Madplan:** Vis kalorie-sum badge ved siden af dagsoverskriften (f.eks. `1.850 kcal`)
---

## 🟢 Lav — Nice to have

- [ ] Branded splash screen
- [x] Onboarding-flow for nye brugere ("Den Personlige Setup-Wizard" med 3 trin, familiestørrelse, præferencer og instant aftensmad)
- [x] **Profil:** Profilbillede med redigerings-ikon (understøtter kamera, galleri og fjernelse)
