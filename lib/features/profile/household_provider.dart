import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';

class HouseholdState {
  final String? householdId;
  final String? householdName;
  final List<String> members;
  final bool isLoading;

  HouseholdState({
    this.householdId,
    this.householdName,
    this.members = const [],
    this.isLoading = false,
  });

  HouseholdState copyWith({
    String? householdId,
    String? householdName,
    List<String>? members,
    bool? isLoading,
  }) {
    return HouseholdState(
      householdId: householdId ?? this.householdId,
      householdName: householdName ?? this.householdName,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HouseholdNotifier extends StateNotifier<HouseholdState> {
  HouseholdNotifier() : super(HouseholdState(
    householdId: 'HK92-L01X',
    householdName: 'Hjemme hos Polonius',
    members: ['Zacharias', 'Emma'],
  ));

  Future<void> createHousehold(String name) async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1));
    
    // Generer en tilfældig kode
    final random = Random();
    final code = 'SK-${random.nextInt(9000) + 1000}';
    
    state = HouseholdState(
      householdId: code,
      householdName: name,
      members: ['Dig'],
      isLoading: false,
    );
  }

  Future<void> joinHousehold(String code) async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1));
    
    state = HouseholdState(
      householdId: code,
      householdName: 'Delt husholdning',
      members: ['Anden person', 'Dig'],
      isLoading: false,
    );
  }

  void leaveHousehold() {
    state = HouseholdState();
  }
}

final householdProvider = StateNotifierProvider<HouseholdNotifier, HouseholdState>((ref) {
  return HouseholdNotifier();
});
