import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import 'dart:developer' as developer;

class HouseholdState {
  final String? householdId;
  final String? householdName;
  final String? adminUid;
  final List<String> members; // Nu UID'er
  final List<Map<String, dynamic>> invitations;
  final Map<String, String> memberNames; // Map fra UID til Navn
  final bool isLoading;
  final String? error;

  HouseholdState({
    this.householdId,
    this.householdName,
    this.adminUid,
    this.members = const [],
    this.invitations = const [],
    this.memberNames = const {},
    this.isLoading = false,
    this.error,
  });

  HouseholdState copyWith({
    String? householdId,
    String? householdName,
    String? adminUid,
    List<String>? members,
    List<Map<String, dynamic>>? invitations,
    Map<String, String>? memberNames,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return HouseholdState(
      householdId: householdId ?? this.householdId,
      householdName: householdName ?? this.householdName,
      adminUid: adminUid ?? this.adminUid,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      memberNames: memberNames ?? this.memberNames,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HouseholdNotifier extends StateNotifier<HouseholdState> {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  HouseholdNotifier({FirebaseFirestore? firestore, FirebaseAuth? auth}) 
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        super(HouseholdState(isLoading: true)) {
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
        .where('toUserEmail', isEqualTo: email.trim().toLowerCase())
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
          // Vi tjekker om vi allerede er ved at oprette/loade
          if (!state.isLoading) {
            developer.log('Ingen husstand fundet. Opretter automatisk...', name: 'household_provider');
            await createHousehold('${user.displayName ?? 'Mit'} Skafferi');
          }
        } else {
          state = state.copyWith(isLoading: false);
        }
      }
    });
  }

  void _listenToHousehold(String householdId) {
    _firestore.collection('households').doc(householdId).snapshots().listen((doc) async {
      if (doc.exists) {
        final data = doc.data()!;
        final memberUids = List<String>.from(data['members'] ?? []);
        
        // Hent navne for alle medlemmer
        final names = await _fetchMemberNames(memberUids);
        
        state = state.copyWith(
          householdId: householdId,
          householdName: data['name'],
          adminUid: data['admin'] as String?,
          members: memberUids,
          memberNames: names,
          isLoading: false,
        );
      }
    });
  }

  Future<Map<String, String>> _fetchMemberNames(List<String> uids) async {
    final Map<String, String> names = {};
    for (final uid in uids) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        names[uid] = userDoc.data()?['displayName'] ?? 'Ukendt bruger';
      } else {
        names[uid] = 'Bruger';
      }
    }
    return names;
  }

  Future<void> renameHousehold(String newName) async {
    if (state.householdId == null) return;
    try {
      await _firestore.collection('households').doc(state.householdId).update({'name': newName});
    } catch (e) {
      developer.log('FEJL ved omdøbning af husstand', error: e, name: 'household_provider');
      state = state.copyWith(error: 'Kunne ikke omdøbe husstanden');
    }
  }

  Future<void> createHousehold(String name) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      state = state.copyWith(isLoading: true);
      
      final random = Random();
      final code = 'SK-${random.nextInt(900000) + 100000}';
      
      final householdData = {
        'name': name,
        'members': [user.uid],
        'admin': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(user.uid).set({
        'displayName': user.displayName ?? user.email,
        'email': user.email,
      }, SetOptions(merge: true));

      await _firestore.collection('households').doc(code).set(householdData);
      await _firestore.collection('users').doc(user.uid).set({
        'householdId': code,
      }, SetOptions(merge: true));
    } catch (e) {
      developer.log('FEJL ved oprettelse af husstand', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke oprette husstand');
    }
  }

  Future<void> joinHousehold(String code) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      state = state.copyWith(isLoading: true, clearError: true);
      
      final doc = await _firestore.collection('households').doc(code).get();
      if (doc.exists) {
        await _firestore.collection('households').doc(code).update({
          'members': FieldValue.arrayUnion([user.uid]),
        });
        await _firestore.collection('users').doc(user.uid).set({
          'householdId': code,
        }, SetOptions(merge: true));
      } else {
        developer.log('Husstandskode $code findes ikke', name: 'household_provider');
        state = state.copyWith(isLoading: false, error: 'Husstandskoden findes ikke');
      }
    } catch (e) {
      developer.log('FEJL ved tilslutning til husstand', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke tilslutte til husstand');
    }
  }

  Future<void> leaveHousehold() async {
    try {
      final user = _auth.currentUser;
      if (user == null || state.householdId == null) return;

      final hId = state.householdId!;
      await _firestore.collection('households').doc(hId).update({
        'members': FieldValue.arrayRemove([user.uid]),
      });
      await _firestore.collection('users').doc(user.uid).update({
        'householdId': FieldValue.delete(),
      });
      
      state = state.copyWith(householdId: null, members: [], memberNames: {}, clearError: true);
    } catch (e) {
      developer.log('FEJL ved udmeldelse af husstand', error: e, name: 'household_provider');
      state = state.copyWith(error: 'Kunne ikke forlade husstanden');
    }
  }

  Future<void> sendInvitation(String email) async {
    try {
      final user = _auth.currentUser;
      if (user == null || state.householdId == null) return;

      final cleanEmail = email.trim().toLowerCase();
      await _firestore.collection('invitations').add({
        'fromHouseholdId': state.householdId,
        'fromHouseholdName': state.householdName,
        'fromUserName': user.displayName ?? user.email,
        'toUserEmail': cleanEmail,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      developer.log('FEJL ved afsendelse af invitation', error: e, name: 'household_provider');
      state = state.copyWith(error: 'Kunne ikke sende invitation');
    }
  }

  Future<void> acceptInvitation(String invitationId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      state = state.copyWith(isLoading: true, clearError: true);

      final inviteDoc = await _firestore.collection('invitations').doc(invitationId).get();
      if (!inviteDoc.exists) return;

      final data = inviteDoc.data()!;
      final targetEmail = data['toUserEmail'] as String?;
      
      if (targetEmail != user.email?.toLowerCase()) {
        throw Exception('Sikkerhedsfejl: Invitation tilhører ikke denne bruger');
      }

      final householdId = data['fromHouseholdId'];

      if (state.householdId != null && state.householdId != householdId) {
        await leaveHousehold();
      }

      await joinHousehold(householdId);

      await _firestore.collection('invitations').doc(invitationId).update({
        'status': 'accepted',
      });
    } catch (e) {
      developer.log('FEJL ved accept af invitation', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke acceptere invitation');
    }
  }

  Future<void> declineInvitation(String invitationId) async {
    try {
      await _firestore.collection('invitations').doc(invitationId).update({
        'status': 'declined',
      });
    } catch (e) {
      developer.log('FEJL ved afvisning af invitation', error: e, name: 'household_provider');
      state = state.copyWith(error: 'Kunne ikke afvise invitation');
    }
  }
}

final householdProvider = StateNotifierProvider<HouseholdNotifier, HouseholdState>((ref) {
  return HouseholdNotifier();
});
