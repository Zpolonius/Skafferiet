import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';

/// Tegn i koder: uden 0/O og 1/I, så de er nemme at læse op og skrive af.
const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Længden på invitationskoder. 32^10 ≈ 10^15 kombinationer, så de ikke kan
/// gættes. Skal matche reglen for `join_codes` i firestore.rules.
const joinCodeLength = 10;

/// Hvor længe en invitationskode virker (firestore.rules tillader op til 8 dage).
const joinCodeValidity = Duration(days: 7);

/// Kryptografisk tilfældig kode af [length] tegn fra [_codeAlphabet].
String generateSecureCode(int length, {Random? random}) {
  final rnd = random ?? Random.secure();
  return List.generate(
    length,
    (_) => _codeAlphabet[rnd.nextInt(_codeAlphabet.length)],
  ).join();
}

/// Gør brugerens indtastning (fx "abcde-fghjk ") til "ABCDEFGHJK".
String normalizeJoinCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Viser en kode som "ABCDE-FGHJK", så den er nemmere at læse.
String formatJoinCode(String code) => code.length == joinCodeLength
    ? '${code.substring(0, 5)}-${code.substring(5)}'
    : code;

class HouseholdState {
  final String? householdId;
  final String? householdName;
  final String? adminUid;
  final List<String> members; // Nu UID'er
  final List<Map<String, dynamic>> invitations;
  final Map<String, String> memberNames; // Map fra UID til Navn
  final Map<String, String?> memberPhotos; // Map fra UID til Foto-URL
  final bool isLoading;
  final String? error;
  final bool hasCompletedOnboarding;
  final int adultsCount;
  final int childrenCount;
  final List<String> preferences;

  HouseholdState({
    this.householdId,
    this.householdName,
    this.adminUid,
    this.members = const [],
    this.invitations = const [],
    this.memberNames = const {},
    this.memberPhotos = const {},
    this.isLoading = false,
    this.error,
    this.hasCompletedOnboarding = true,
    this.adultsCount = 2,
    this.childrenCount = 2,
    this.preferences = const [],
  });

  HouseholdState copyWith({
    String? householdId,
    String? householdName,
    String? adminUid,
    List<String>? members,
    List<Map<String, dynamic>>? invitations,
    Map<String, String>? memberNames,
    Map<String, String?>? memberPhotos,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? hasCompletedOnboarding,
    int? adultsCount,
    int? childrenCount,
    List<String>? preferences,
  }) {
    return HouseholdState(
      householdId: householdId ?? this.householdId,
      householdName: householdName ?? this.householdName,
      adminUid: adminUid ?? this.adminUid,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      memberNames: memberNames ?? this.memberNames,
      memberPhotos: memberPhotos ?? this.memberPhotos,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      adultsCount: adultsCount ?? this.adultsCount,
      childrenCount: childrenCount ?? this.childrenCount,
      preferences: preferences ?? this.preferences,
    );
  }
}

class HouseholdNotifier extends StateNotifier<HouseholdState> {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  bool _isCreatingHousehold = false;

  // Lyttere til Firestore. De skal lukkes ved log ud, ellers kører den forrige
  // brugers lyttere videre, når en ny bruger logger ind på samme telefon.
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _householdSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invitationsSub;
  String? _subscribedHouseholdId;
  bool _hasCompletedOnboarding = true;

  // Mens vi selv skifter husstand, venter vi med at følge brugerdokumentet,
  // så vi ikke lytter på den nye husstand, før serveren har gjort os til medlem.
  Map<String, dynamic>? _latestUserData;
  bool _hasUserSnapshot = false;
  bool _membershipChangeInFlight = false;

  HouseholdNotifier({FirebaseFirestore? firestore, FirebaseAuth? auth}) 
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        super(HouseholdState(isLoading: true)) {
    _init();
  }

  void _init() {
    _authSub = _auth.authStateChanges().listen((user) {
      _cancelDataSubscriptions();
      if (user != null) {
        // Skift direkte fra én bruger til en anden: vis ikke den forriges data.
        if (state.householdId != null) state = HouseholdState(isLoading: true);
        _listenToUserHousehold(user.uid);
        _listenToInvitations(user.email);
      } else {
        state = HouseholdState();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelDataSubscriptions();
    super.dispose();
  }

  /// Stopper alle lyttere, før kontoen slettes. Ellers ville sletningen af
  /// profilen få appen til automatisk at oprette en ny husstand, og
  /// lytterne ville fejle, når brugeren meldes ud.
  void pauseForAccountDeletion() {
    _cancelDataSubscriptions();
    state = HouseholdState(isLoading: true);
  }

  /// Starter lytterne igen, hvis sletningen fejlede, og brugeren stadig er
  /// logget ind.
  void resumeAfterFailedAccountDeletion() {
    final user = _auth.currentUser;
    if (user == null || _userSub != null) return;
    _listenToUserHousehold(user.uid);
    _listenToInvitations(user.email);
  }

  void _cancelDataSubscriptions() {
    _userSub?.cancel();
    _userSub = null;
    _invitationsSub?.cancel();
    _invitationsSub = null;
    _latestUserData = null;
    _hasUserSnapshot = false;
    _cancelHouseholdSubscription();
  }

  void _cancelHouseholdSubscription() {
    _householdSub?.cancel();
    _householdSub = null;
    _subscribedHouseholdId = null;
  }

  void _listenToInvitations(String? email) {
    if (email == null) return;
    _invitationsSub = _firestore
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
    }, onError: (e) {
      developer.log('FEJL i invitations listener', error: e, name: 'household_provider');
    });
  }

  void _listenToUserHousehold(String uid) {
    _userSub = _firestore.collection('users').doc(uid).snapshots().listen((doc) {
      _latestUserData = doc.exists ? doc.data() : null;
      _hasUserSnapshot = true;
      if (!_membershipChangeInFlight) _applyUserData(_latestUserData);
    }, onError: (e) {
      developer.log('FEJL i user household listener', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke hente brugerdata');
    });
  }

  void _applyUserData(Map<String, dynamic>? data) {
    final householdId = data?['householdId'] as String?;
    _hasCompletedOnboarding = data?['hasCompletedOnboarding'] == true ||
        (householdId != null && data?['hasCompletedOnboarding'] != false);

    if (householdId != null) {
      if (householdId == _subscribedHouseholdId) {
        // Samme husstand — kun profilfelter er ændret (fx profilbillede).
        state = state.copyWith(hasCompletedOnboarding: _hasCompletedOnboarding);
      } else {
        _listenToHousehold(householdId);
      }
      return;
    }

    if (_subscribedHouseholdId != null) {
      // Brugeren har forladt sin husstand — vis ikke den gamle husstand længere.
      _cancelHouseholdSubscription();
      state = HouseholdState(isLoading: true, invitations: state.invitations);
    }

    // Hvis brugeren ikke har en husstand, opret en automatisk forberedt til onboarding
    final user = _auth.currentUser;
    if (user != null && !_isCreatingHousehold) {
      _isCreatingHousehold = true;
      developer.log('Ingen husstand fundet. Opretter automatisk...', name: 'household_provider');
      createHousehold('${user.displayName ?? 'Mit'} Skafferi', completedOnboarding: false)
          .whenComplete(() => _isCreatingHousehold = false);
    } else if (user == null) {
      state = state.copyWith(isLoading: false);
    }
  }

  void _listenToHousehold(String householdId) {
    _cancelHouseholdSubscription();
    _subscribedHouseholdId = householdId;
    _householdSub = _firestore.collection('households').doc(householdId).snapshots().listen((doc) async {
      if (doc.exists) {
        final data = doc.data()!;
        final memberUids = List<String>.from(data['members'] ?? []);
        
        // Hent navne og billeder for alle medlemmer
        final details = await _fetchMemberDetails(memberUids);

        // Brugeren kan have logget ud eller skiftet husstand, mens vi ventede.
        if (!mounted || _subscribedHouseholdId != householdId) return;

        state = state.copyWith(
          householdId: householdId,
          householdName: data['name'],
          adminUid: data['admin'] as String?,
          members: memberUids,
          memberNames: details.names,
          memberPhotos: details.photos,
          adultsCount: data['adultsCount'] ?? 2,
          childrenCount: data['childrenCount'] ?? 2,
          preferences: List<String>.from(data['preferences'] ?? []),
          hasCompletedOnboarding: _hasCompletedOnboarding,
          isLoading: false,
        );
      } else {
        // Husstanden findes ikke (f.eks. slettet eller ikke oprettet endnu)
        state = state.copyWith(isLoading: false);
      }
    }, onError: (Object e) {
      developer.log('FEJL i household listener', error: e, name: 'household_provider');
      if (!mounted || _subscribedHouseholdId != householdId) return;
      if (e is FirebaseException && e.code == 'permission-denied') {
        // Kun medlemmer må læse en husstand, så brugeren er blevet fjernet
        // (eller husstanden er slettet).
        _cancelHouseholdSubscription();
        state = HouseholdState(
          invitations: state.invitations,
          hasCompletedOnboarding: _hasCompletedOnboarding,
          error: 'Du er ikke længere medlem af husstanden',
        );
        return;
      }
      state = state.copyWith(isLoading: false, error: 'Kunne ikke hente husstand');
    });
  }

  Future<({Map<String, String> names, Map<String, String?> photos})> _fetchMemberDetails(List<String> uids) async {
    final details = await Future.wait(uids.map((uid) async {
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (!userDoc.exists) return (uid: uid, name: 'Bruger', photo: null);
        return (
          uid: uid,
          name: userDoc.data()?['displayName'] as String? ?? 'Ukendt bruger',
          photo: userDoc.data()?['photoURL'] as String?,
        );
      } catch (e) {
        // Fx et medlem hvis profil ikke længere peger på denne husstand —
        // så må vi ikke læse den. Vis medlemmet uden navn i stedet for at fejle.
        developer.log('Kunne ikke hente medlem $uid', error: e, name: 'household_provider');
        return (uid: uid, name: 'Bruger', photo: null);
      }
    }));
    return (
      names: {for (final d in details) d.uid: d.name},
      photos: {for (final d in details) d.uid: d.photo},
    );
  }

  /// Skriver en ændring af medlemskab (skift eller forlad husstand).
  ///
  /// Lytteren på den gamle husstand stoppes først — ellers fejler den med
  /// permission-denied, så snart vi ikke er medlem længere. Når skrivningen er
  /// færdig, følger vi brugerdokumentet igen, som nu peger på den nye husstand
  /// (eller den gamle, hvis skrivningen fejlede).
  Future<void> _commitMembershipChange(WriteBatch batch) async {
    _membershipChangeInFlight = true;
    _cancelHouseholdSubscription();
    try {
      await batch.commit();
    } finally {
      _membershipChangeInFlight = false;
      // Uden et modtaget brugerdokument ved vi intet — og "ingen husstand"
      // ville fejlagtigt oprette en ny. Det første snapshot klarer det selv.
      if (mounted && _hasUserSnapshot) _applyUserData(_latestUserData);
    }
  }

  /// Fjerner [uid] fra [householdId]. Er brugeren ejer, gives ejerskabet
  /// videre til et andet medlem — reglerne kræver, at ejeren er medlem.
  void _addLeaveToBatch(WriteBatch batch, String householdId, String uid) {
    final update = <String, dynamic>{
      'members': FieldValue.arrayRemove([uid]),
    };
    if (state.adminUid == uid) {
      final successor = state.members.where((m) => m != uid).firstOrNull;
      if (successor != null) update['admin'] = successor;
    }
    batch.update(_firestore.collection('households').doc(householdId), update);
  }

  /// Forlader den nuværende husstand og melder sig ind i [householdId] i ét
  /// samlet batch, så brugeren aldrig ender halvvejs mellem to husstande.
  ///
  /// [proof] fortæller sikkerhedsreglerne, hvorfor brugeren må komme ind:
  /// en gyldig kode (`{'type': 'code', 'id': kode}`) eller en invitation
  /// (`{'type': 'invite', 'id': invitationsId}`).
  Future<void> _switchHousehold(
    String householdId, {
    required Map<String, String> proof,
    String? acceptInvitationId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final batch = _firestore.batch();
    final current = state.householdId;
    if (current != null && current != householdId) {
      _addLeaveToBatch(batch, current, user.uid);
    }
    batch.update(_firestore.collection('households').doc(householdId), {
      'members': FieldValue.arrayUnion([user.uid]),
      'joinedWith': proof,
    });
    batch.set(
      _firestore.collection('users').doc(user.uid),
      {'householdId': householdId},
      SetOptions(merge: true),
    );
    if (acceptInvitationId != null) {
      batch.update(
        _firestore.collection('invitations').doc(acceptInvitationId),
        {'status': 'accepted'},
      );
    }
    await _commitMembershipChange(batch);
  }

  /// Husstands-ID'et er ikke en hemmelighed længere (reglerne kræver kode
  /// eller invitation for at komme ind), men det skal være tilfældigt nok til
  /// aldrig at ramme en eksisterende husstand.
  String _newHouseholdId() => 'SK-${generateSecureCode(joinCodeLength)}';

  Future<void> renameHousehold(String newName) async {
    if (state.householdId == null) return;
    try {
      await _firestore.collection('households').doc(state.householdId).update({'name': newName});
    } catch (e) {
      developer.log('FEJL ved omdøbning af husstand', error: e, name: 'household_provider');
      state = state.copyWith(error: 'Kunne ikke omdøbe husstanden');
    }
  }

  Future<void> createHousehold(String name, {bool completedOnboarding = true}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      state = state.copyWith(isLoading: true);
      
      final code = _newHouseholdId();
      
      final householdData = {
        'name': name,
        'members': [user.uid],
        'admin': user.uid,
        'adultsCount': 2,
        'childrenCount': 2,
        'preferences': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(user.uid).set({
        'displayName': user.displayName ?? user.email,
        'email': user.email,
        'hasCompletedOnboarding': completedOnboarding,
      }, SetOptions(merge: true));

      await _firestore.collection('households').doc(code).set(householdData);
      await _firestore.collection('users').doc(user.uid).set({
        'householdId': code,
      }, SetOptions(merge: true));

      state = state.copyWith(
        householdId: code,
        householdName: name,
        hasCompletedOnboarding: completedOnboarding,
      );
    } catch (e) {
      developer.log('FEJL ved oprettelse af husstand', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke oprette husstand');
    }
  }

  Future<void> completeOnboarding({
    required String householdName,
    required int adultsCount,
    required int childrenCount,
    required List<String> preferences,
    Recipe? starterRecipe,
    String? customMeal,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      state = state.copyWith(isLoading: true);

      String hId = state.householdId ?? '';
      if (hId.isEmpty) {
        hId = _newHouseholdId();
        await _firestore.collection('households').doc(hId).set({
          'name': householdName,
          'members': [user.uid],
          'admin': user.uid,
          'adultsCount': adultsCount,
          'childrenCount': childrenCount,
          'preferences': preferences,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _firestore.collection('households').doc(hId).set({
          'name': householdName,
          'adultsCount': adultsCount,
          'childrenCount': childrenCount,
          'preferences': preferences,
        }, SetOptions(merge: true));
      }

      await _firestore.collection('users').doc(user.uid).set({
        'displayName': user.displayName ?? user.email,
        'email': user.email,
        'householdId': hId,
        'hasCompletedOnboarding': true,
      }, SetOptions(merge: true));

      // Dagens ugedag på dansk
      const danishDays = {
        DateTime.monday: 'Mandag',
        DateTime.tuesday: 'Tirsdag',
        DateTime.wednesday: 'Onsdag',
        DateTime.thursday: 'Torsdag',
        DateTime.friday: 'Fredag',
        DateTime.saturday: 'Lørdag',
        DateTime.sunday: 'Søndag',
      };
      final now = DateTime.now();
      final dayName = danishDays[now.weekday] ?? 'Mandag';

      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekId = '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      if (starterRecipe != null) {
        final recipeRef = await _firestore.collection('recipes').add({
          'title': starterRecipe.title,
          'imageUrl': starterRecipe.imageUrl,
          'calories': starterRecipe.calories,
          'time': starterRecipe.time,
          'category': starterRecipe.category.toString(),
          'ingredients': starterRecipe.ingredients
              .map((i) => {
                    'name': i.name,
                    'quantity': i.quantity,
                    'unit': i.unit,
                    'category': i.category,
                  })
              .toList(),
          'instructions': starterRecipe.instructions,
          'createdAt': FieldValue.serverTimestamp(),
          'householdId': hId,
          'createdBy': user.uid,
        });

        await _firestore.collection('households').doc(hId).collection('meal_plans').doc(weekId).set({
          'days': {
            dayName: {
              'dinner': {
                'recipeId': recipeRef.id,
                'directEntry': null,
              }
            }
          }
        }, SetOptions(merge: true));

        final batch = _firestore.batch();
        for (final ing in starterRecipe.ingredients) {
          final itemRef = _firestore.collection('households').doc(hId).collection('grocery_list').doc();
          batch.set(itemRef, {
            'name': ing.name,
            'category': ing.category,
            'quantity': ing.quantity.toString(),
            'unit': ing.unit,
            'source': 'meal_plan',
            'isChecked': false,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
        await batch.commit();
      } else if (customMeal != null && customMeal.trim().isNotEmpty) {
        await _firestore.collection('households').doc(hId).collection('meal_plans').doc(weekId).set({
          'days': {
            dayName: {
              'dinner': {
                'recipeId': null,
                'directEntry': customMeal.trim(),
              }
            }
          }
        }, SetOptions(merge: true));

        await _firestore.collection('households').doc(hId).collection('grocery_list').add({
          'name': customMeal.trim(),
          'category': 'Måltider',
          'quantity': '1',
          'unit': 'stk',
          'source': 'meal_plan',
          'isChecked': false,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      state = state.copyWith(
        householdId: hId,
        householdName: householdName,
        adultsCount: adultsCount,
        childrenCount: childrenCount,
        preferences: preferences,
        hasCompletedOnboarding: true,
        isLoading: false,
      );
    } catch (e) {
      developer.log('FEJL ved gennemførelse af onboarding', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke gennemføre onboarding');
    }
  }

  /// Melder brugeren ind i den husstand, som invitationskoden [input] hører til.
  /// Er brugeren allerede i en husstand, forlades den samtidig.
  Future<void> joinHousehold(String input) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final code = normalizeJoinCode(input);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      String? householdId;
      if (code.length == joinCodeLength) {
        final codeDoc = await _firestore.collection('join_codes').doc(code).get();
        final expiresAt = codeDoc.data()?['expiresAt'];
        if (expiresAt is Timestamp && expiresAt.toDate().isAfter(DateTime.now())) {
          householdId = codeDoc.data()?['householdId'] as String?;
        }
      }

      if (householdId == null) {
        developer.log('Ugyldig eller udløbet kode', name: 'household_provider');
        state = state.copyWith(isLoading: false, error: 'Koden er ugyldig eller udløbet');
        return;
      }
      if (householdId == state.householdId) {
        state = state.copyWith(isLoading: false);
        return;
      }

      await _switchHousehold(householdId, proof: {'type': 'code', 'id': code});
    } catch (e) {
      developer.log('FEJL ved tilslutning til husstand', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke tilslutte til husstand');
    }
  }

  /// Laver en invitationskode til den nuværende husstand, som andre kan
  /// indtaste. Returnerer null (og sætter en fejl) hvis det mislykkes.
  Future<String?> createJoinCode() async {
    final user = _auth.currentUser;
    final householdId = state.householdId;
    if (user == null || householdId == null) return null;

    try {
      final code = generateSecureCode(joinCodeLength);
      await _firestore.collection('join_codes').doc(code).set({
        'householdId': householdId,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(joinCodeValidity)),
      });
      return code;
    } catch (e) {
      developer.log('FEJL ved oprettelse af invitationskode', error: e, name: 'household_provider');
      state = state.copyWith(error: 'Kunne ikke lave en invitationskode');
      return null;
    }
  }

  Future<void> leaveHousehold() async {
    final user = _auth.currentUser;
    final hId = state.householdId;
    if (user == null || hId == null) return;

    try {
      final batch = _firestore.batch();
      _addLeaveToBatch(batch, hId, user.uid);
      batch.update(_firestore.collection('users').doc(user.uid), {
        'householdId': FieldValue.delete(),
      });
      await _commitMembershipChange(batch);

      state = HouseholdState(isLoading: true, invitations: state.invitations);
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
        'fromUid': user.uid,
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

      final inviteRef = _firestore.collection('invitations').doc(invitationId);
      final inviteDoc = await inviteRef.get();
      if (!inviteDoc.exists) {
        state = state.copyWith(isLoading: false, error: 'Invitationen findes ikke længere');
        return;
      }

      final data = inviteDoc.data()!;
      final targetEmail = data['toUserEmail'] as String?;
      
      if (targetEmail != user.email?.toLowerCase()) {
        throw Exception('Sikkerhedsfejl: Invitation tilhører ikke denne bruger');
      }

      final householdId = data['fromHouseholdId'] as String;

      if (householdId == state.householdId) {
        // Allerede medlem — marker bare invitationen som besvaret.
        await inviteRef.update({'status': 'accepted'});
        state = state.copyWith(isLoading: false);
        return;
      }

      // Skift husstand og accepter invitationen i ét batch. Reglerne tjekker,
      // at invitationen stadig er 'pending', når vi melder os ind.
      await _switchHousehold(
        householdId,
        proof: {'type': 'invite', 'id': invitationId},
        acceptInvitationId: invitationId,
      );
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
