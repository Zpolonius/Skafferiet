import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'household_provider.dart';

/// En invitation husstanden har sendt, som endnu ikke er besvaret.
class SentInvitation {
  final String id;
  final String email;
  final String? fromUserName;
  final DateTime? createdAt;

  const SentInvitation({
    required this.id,
    required this.email,
    this.fromUserName,
    this.createdAt,
  });

  factory SentInvitation.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final created = data['createdAt'];
    return SentInvitation(
      id: doc.id,
      email: data['toUserEmail'] as String? ?? '',
      fromUserName: data['fromUserName'] as String?,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

/// Invitationer husstanden sender. Modtagne invitationer (accepter/afvis)
/// hører til [HouseholdNotifier], fordi en accept er et skift af husstand.
class InvitationService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  InvitationService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _invitations =>
      _firestore.collection('invitations');

  /// Inviterer [email] til husstanden [householdId]. Returnerer en
  /// fejlbesked, der kan vises til brugeren, eller null hvis den er gemt.
  Future<String?> send({
    required String householdId,
    required String? householdName,
    required String email,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'Du er ikke logget ind.';

    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail == user.email?.trim().toLowerCase()) {
      return 'Du kan ikke invitere dig selv.';
    }

    try {
      final existing = await _invitations
          .where('fromHouseholdId', isEqualTo: householdId)
          .where('toUserEmail', isEqualTo: cleanEmail)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return '$cleanEmail er allerede inviteret.';

      await _invitations.add({
        'fromHouseholdId': householdId,
        'fromHouseholdName': householdName,
        'fromUserName': user.displayName ?? user.email,
        'fromUid': user.uid,
        'toUserEmail': cleanEmail,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      developer.log('FEJL ved afsendelse af invitation', error: e, name: 'invitation_service');
      return 'Invitationen kunne ikke sendes. Tjek din forbindelse, og prøv igen.';
    }
  }

  /// Husstandens ubesvarede invitationer, nyeste først.
  Stream<List<SentInvitation>> watchPending(String householdId) {
    return _invitations
        .where('fromHouseholdId', isEqualTo: householdId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      // Ny invitation uden servertid endnu = nyeste.
      final far = DateTime(9999);
      return snapshot.docs.map(SentInvitation.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? far).compareTo(a.createdAt ?? far));
    });
  }

  /// Trækker en invitation tilbage. Returnerer en fejlbesked eller null.
  Future<String?> cancel(String invitationId) async {
    try {
      await _invitations.doc(invitationId).delete();
      return null;
    } catch (e) {
      developer.log('FEJL ved annullering af invitation', error: e, name: 'invitation_service');
      return 'Invitationen kunne ikke annulleres. Prøv igen.';
    }
  }
}

final invitationServiceProvider = Provider<InvitationService>((ref) => InvitationService());

/// Husstandens udsendte, ubesvarede invitationer.
final sentInvitationsProvider = StreamProvider.autoDispose<List<SentInvitation>>((ref) {
  final householdId = ref.watch(householdProvider.select((s) => s.householdId));
  if (householdId == null) return Stream.value(const []);
  return ref.watch(invitationServiceProvider).watchPending(householdId);
});
