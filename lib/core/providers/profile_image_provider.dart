import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/profile_image_service.dart';

/// Provider exposing the abstract [ProfileImageService] (Dependency Inversion).
/// Can be easily overridden in tests with mock or fake services.
final profileImageServiceProvider = Provider<ProfileImageService>((ref) {
  return FirebaseProfileImageService();
});
