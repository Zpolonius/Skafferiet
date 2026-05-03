import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';

class HouseholdState {
  final String? householdId;
  final String? householdName;
  final List<String> members;
  final List<Map<String, dynamic>> invitations;
  final bool isLoading;

  HouseholdState({
    this.householdId,
    this.householdName,
    this.members = const [],
    this.invitations = const [],
    this.isLoading = false,
  });

  HouseholdState copyWith({
    String? householdId,
    String? householdName,
    List<String>? members,
    List<Map<String, dynamic>>? invitations,
    bool? isLoading,
  }) {
    return HouseholdState(
      householdId: householdId ?? this.householdId,
      householdName: householdName ?? this.householdName,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HouseholdNotifier extends StateNotifier<HouseholdState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  HouseholdNotifier() : super(HouseholdState(isLoading: true)) {
    _init();
  }

  void _init() {
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        _listenToUserHousehold(user.uid);
        _listenToInvitations(user.email);
      } else {
        state = HouseholdState();
      }
    });
  }

  void _listenToInvitations(String? email) {
    if (email == null) return;
    _firestore
        .collection('invitations')
        .where('toUserEmail', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      final invites = snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
      state = state.copyWith(invitations: invites);
    });
  }

  void _listenToUserHousehold(String uid) {
    _firestore.collection('users').doc(uid).snapshots().listen((doc) async {
      if (doc.exists && doc.data()?['householdId'] != null) {
        _listenToHousehold(doc.data()!['householdId']);
      } else {
        // Hvis brugeren ikke har en husstand, opret en automatisk
        final user = _auth.currentUser;
        if (user != null) {
          print('DEBUG: Ingen husstand fundet. Opretter automatisk...');
          await createHousehold('${user.displayName ?? 'Mit'} Skafferi');
        } else {
          state = HouseholdState(isLoading: false);
        }
      }
    });
  }

  void _listenToHousehold(String householdId) {
    _firestore.collection('households').doc(householdId).snapshots().listen((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        state = state.copyWith(
          householdId: householdId,
          householdName: data['name'],
          members: List<String>.from(data['members'] ?? []),
          isLoading: false,
        );
      }
    });
  }

  Future<void> createHousehold(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;

    state = state.copyWith(isLoading: true);
    
    final random = Random();
    final code = 'SK-${random.nextInt(9000) + 1000}';
    
    final householdData = {
      'name': name,
      'members': [user.displayName ?? user.email],
      'admin': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('households').doc(code).set(householdData);
    await _firestore.collection('users').doc(user.uid).set({
      'householdId': code,
    }, SetOptions(merge: true));
  }

  Future<void> joinHousehold(String code) async {
    final user = _auth.currentUser;
    if (user == null) return;

    state = state.copyWith(isLoading: true);
    
    final doc = await _firestore.collection('households').doc(code).get();
    if (doc.exists) {
      await _firestore.collection('households').doc(code).update({
        'members': FieldValue.arrayUnion([user.displayName ?? user.email]),
      });
      await _firestore.collection('users').doc(user.uid).set({
        'householdId': code,
      }, SetOptions(merge: true));
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> leaveHousehold() async {
    final user = _auth.currentUser;
    if (user == null || state.householdId == null) return;

    final hId = state.householdId!;
    await _firestore.collection('households').doc(hId).update({
      'members': FieldValue.arrayRemove([user.displayName ?? user.email]),
    });
    await _firestore.collection('users').doc(user.uid).update({
      'householdId': FieldValue.delete(),
    });
  }

  Future<void> sendInvitation(String email) async {
    final user = _auth.currentUser;
    if (user == null || state.householdId == null) return;

    final cleanEmail = email.trim().toLowerCase();
    print('DEBUG: Sender invitation til $cleanEmail fra husstand ${state.householdId}');

    await _firestore.collection('invitations').add({
      'fromHouseholdId': state.householdId,
      'fromHouseholdName': state.householdName,
      'fromUserName': user.displayName ?? user.email,
      'toUserEmail': cleanEmail,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptInvitation(String invitationId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final inviteDoc = await _firestore.collection('invitations').doc(invitationId).get();
    if (!inviteDoc.exists) return;

    final data = inviteDoc.data()!;
    final householdId = data['fromHouseholdId'];

    // Join the household
    await joinHousehold(householdId);

    // Mark invitation as accepted
    await _firestore.collection('invitations').doc(invitationId).update({
      'status': 'accepted',
    });
  }

  Future<void> declineInvitation(String invitationId) async {
    await _firestore.collection('invitations').doc(invitationId).update({
      'status': 'declined',
    });
  }
}

final householdProvider = StateNotifierProvider<HouseholdNotifier, HouseholdState>((ref) {
  return HouseholdNotifier();
});
