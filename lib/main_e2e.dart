// Indgang KUN til e2e-tests (se docs/E2E.md). Kører samme app som main.dart,
// men mod Firebase-emulatorerne i stedet for det rigtige projekt.
//
// Bygges med: flutter build web --target lib/main_e2e.dart --no-web-resources-cdn
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'main.dart' show MyApp;

/// Adressen emulatorerne kører på, set fra browseren.
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

const _demoOptions = FirebaseOptions(
  apiKey: 'fake-api-key',
  appId: '1:000000000000:web:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-skafferiet',
  authDomain: 'demo-skafferiet.firebaseapp.com',
  storageBucket: 'demo-skafferiet.appspot.com',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Gør widgets synlige i tilgængelighedstræet, så Playwright kan finde dem.
  SemanticsBinding.instance.ensureSemantics();

  await initializeDateFormatting('da_DK', null);
  await Firebase.initializeApp(options: _demoOptions);

  await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  await FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199);

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
