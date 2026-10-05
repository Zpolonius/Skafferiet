import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_error_messages.dart';

/// Fejl under sletning af konto, med en besked der kan vises til brugeren.
class AccountDeletionException implements Exception {
  final String message;
  const AccountDeletionException(this.message);

  @override
  String toString() => message;
}

/// Sletter brugerens konto og data — Apple kræver, at det kan gøres i appen
/// (App Store Guideline 5.1.1(v)).
///
/// Rækkefølgen er vigtig:
/// 1. Bekræft adgangskoden. Firebase kræver et frisk login for at slette en
///    konto, og det sikrer, at det er ejeren selv, der sletter.
/// 2. Ryd op i husstanden, mens brugeren stadig er medlem — bagefter nægter
///    sikkerhedsreglerne adgang. Er brugeren eneste medlem, slettes hele
///    husstanden; ellers meldes brugeren ud, og ejerskabet gives videre.
/// 3. Slet invitationer til brugeren, profilbillede og profil.
/// 4. Slet selve login-kontoen til sidst.
///
/// Fejler et trin, kan det hele køres igen: hvert trin tåler, at det allerede
/// er gjort.
class AccountDeletionService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  AccountDeletionService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  /// Firestore tillader højst 500 skrivninger i ét batch.
  static const _batchLimit = 400;

  Future<void> deleteAccount({required String password}) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AccountDeletionException('Du er ikke logget ind.');
    }

    await _reauthenticate(user, email, password);

    try {
      await _cleanUpHousehold(user.uid);
      await _deleteInvitationsTo(email);
      await _deleteProfilePhoto(user.uid);
      await _firestore.collection('users').doc(user.uid).delete();
      await user.delete();
    } on FirebaseException catch (e) {
      developer.log('FEJL ved sletning af konto', error: e, name: 'account_deletion');
      throw AccountDeletionException(_messageFor(e.code));
    }
  }

  Future<void> _reauthenticate(User user, String email, String password) async {
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw AccountDeletionException(_messageFor(e.code));
    }
  }

  String _messageFor(String code) => authErrorMessage(
        code,
        fallback: 'Kontoen kunne ikke slettes. Prøv igen.',
        overrides: const {
          'requires-recent-login': 'Log ud og ind igen, og prøv så at slette kontoen.',
        },
      );

  Future<void> _cleanUpHousehold(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final householdId = userDoc.data()?['householdId'] as String?;
    if (householdId == null) return;

    final householdRef = _firestore.collection('households').doc(householdId);
    final DocumentSnapshot<Map<String, dynamic>> household;
    try {
      household = await householdRef.get();
    } on FirebaseException catch (e) {
      // Ikke medlem længere (fx efter et afbrudt forsøg) — intet at rydde op.
      if (e.code == 'permission-denied') return;
      rethrow;
    }
    final data = household.data();
    if (data == null) return;

    final members = List<String>.from(data['members'] ?? const []);
    if (!members.contains(uid)) return;
    final isAdmin = data['admin'] == uid;
    final others = members.where((m) => m != uid).toList();

    // Invitationer brugeren selv har sendt indeholder brugerens navn.
    await _deleteAll(_firestore
        .collection('invitations')
        .where('fromHouseholdId', isEqualTo: householdId)
        .where('fromUid', isEqualTo: uid));

    final joinCodes =
        _firestore.collection('join_codes').where('householdId', isEqualTo: householdId);

    if (others.isNotEmpty) {
      // Koder brugeren har lavet bærer brugerens ID.
      await _deleteAll(joinCodes.where('createdBy', isEqualTo: uid));
      // Andre bruger stadig husstanden: meld ud og giv ejerskabet videre.
      // Opskrifter brugeren har lavet bliver i husstanden.
      await householdRef.update({
        'members': FieldValue.arrayRemove([uid]),
        if (isAdmin) 'admin': others.first,
      });
      return;
    }

    // Eneste medlem: slet hele husstanden.
    await _deleteAll(householdRef.collection('grocery_list'));
    await _deleteAll(householdRef.collection('meal_plans'));
    await _deleteAll(householdRef.collection('recurring_items'));
    await _deleteAll(
      householdRef.collection('board_notes'),
      // Uden ejerrettigheder må man kun slette sine egne sedler (firestore.rules).
      keep: isAdmin ? null : (doc) => doc.data()['authorId'] != uid,
    );
    await _deleteAll(
      _firestore.collection('recipes').where('householdId', isEqualTo: householdId),
      // Uden ejerrettigheder (ældre husstande) må man kun slette sine egne.
      keep: isAdmin ? null : (doc) => doc.data()['createdBy'] != uid,
    );
    await _deleteAll(
        _firestore.collection('invitations').where('fromHouseholdId', isEqualTo: householdId));
    await _deleteAll(joinCodes);
    await _deleteStorageFolder('households/$householdId');

    if (isAdmin) {
      await householdRef.delete();
    } else {
      await householdRef.update({
        'members': FieldValue.arrayRemove([uid])
      });
    }
  }

  Future<void> _deleteInvitationsTo(String email) async {
    await _deleteAll(_firestore
        .collection('invitations')
        .where('toUserEmail', isEqualTo: email.trim().toLowerCase()));
  }

  Future<void> _deleteProfilePhoto(String uid) async {
    try {
      await _storage.ref('users/$uid/avatar.jpg').delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  /// Sletter alle billeder under [path] (opskrifter og varer). Billeder er
  /// ikke kritiske for selve kontosletningen, så fejl logges i stedet for at
  /// stoppe den — ellers kunne en enkelt fil forhindre brugeren i at slette.
  Future<void> _deleteStorageFolder(String path) async {
    try {
      final result = await _storage.ref(path).listAll();
      for (final item in result.items) {
        await item.delete();
      }
      for (final prefix in result.prefixes) {
        await _deleteStorageFolder(prefix.fullPath);
      }
    } catch (e) {
      developer.log('Kunne ikke slette billeder i $path', error: e, name: 'account_deletion');
    }
  }

  Future<void> _deleteAll(
    Query<Map<String, dynamic>> query, {
    bool Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? keep,
  }) async {
    final snapshot = await query.get();
    final docs = keep == null ? snapshot.docs : snapshot.docs.where((doc) => !keep(doc)).toList();
    for (var i = 0; i < docs.length; i += _batchLimit) {
      final batch = _firestore.batch();
      for (final doc in docs.skip(i).take(_batchLimit)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  return AccountDeletionService();
});
