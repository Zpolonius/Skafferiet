import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import 'dart:developer' as developer;
import '../../core/models/recipe.dart';

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
    }, onError: (e) {
      developer.log('FEJL i invitations listener', error: e, name: 'household_provider');
    });
  }

  void _listenToUserHousehold(String uid) {
    _firestore.collection('users').doc(uid).snapshots().listen((doc) async {
      final hasCompleted = doc.data()?['hasCompletedOnboarding'] == true ||
          (doc.exists && doc.data()?['householdId'] != null && doc.data()?['hasCompletedOnboarding'] != false);

      if (doc.exists && doc.data()?['householdId'] != null) {
        _listenToHousehold(doc.data()!['householdId'], hasCompletedOnboarding: hasCompleted);
      } else {
        // Hvis brugeren ikke har en husstand, opret en automatisk forberedt til onboarding
        final user = _auth.currentUser;
        if (user != null && !_isCreatingHousehold) {
          _isCreatingHousehold = true;
          developer.log('Ingen husstand fundet. Opretter automatisk...', name: 'household_provider');
          try {
            await createHousehold('${user.displayName ?? 'Mit'} Skafferi', completedOnboarding: false);
          } finally {
            _isCreatingHousehold = false;
          }
        } else if (user == null) {
          state = state.copyWith(isLoading: false);
        }
      }
    }, onError: (e) {
      developer.log('FEJL i user household listener', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke hente brugerdata');
    });
  }

  void _listenToHousehold(String householdId, {bool hasCompletedOnboarding = true}) {
    _firestore.collection('households').doc(householdId).snapshots().listen((doc) async {
      if (doc.exists) {
        final data = doc.data()!;
        final memberUids = List<String>.from(data['members'] ?? []);
        
        // Hent navne og billeder for alle medlemmer
        final details = await _fetchMemberDetails(memberUids);
        
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
          hasCompletedOnboarding: hasCompletedOnboarding,
          isLoading: false,
        );
      } else {
        // Husstanden findes ikke (f.eks. slettet eller ikke oprettet endnu)
        state = state.copyWith(isLoading: false);
      }
    }, onError: (e) {
      developer.log('FEJL i household listener', error: e, name: 'household_provider');
      state = state.copyWith(isLoading: false, error: 'Kunne ikke hente husstand');
    });
  }

  Future<({Map<String, String> names, Map<String, String?> photos})> _fetchMemberDetails(List<String> uids) async {
    final Map<String, String> names = {};
    final Map<String, String?> photos = {};
    for (final uid in uids) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        names[uid] = userDoc.data()?['displayName'] ?? 'Ukendt bruger';
        photos[uid] = userDoc.data()?['photoURL'] as String?;
      } else {
        names[uid] = 'Bruger';
        photos[uid] = null;
      }
    }
    return (names: names, photos: photos);
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

  Future<void> createHousehold(String name, {bool completedOnboarding = true}) async {
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
        final random = Random();
        hId = 'SK-${random.nextInt(900000) + 100000}';
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
