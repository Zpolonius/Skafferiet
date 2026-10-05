import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/board_repository.dart';

/// Provider for the abstract [BoardRepository] (Dependency Inversion).
/// Override it in tests with a fake repository.
final boardRepositoryProvider = Provider<BoardRepository>((ref) {
  return FirestoreBoardRepository();
});
