import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/auth_provider.dart';

/// Top bar user avatar that renders the user's profile image if available,
/// with graceful fallback to their initial or person icon.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    String? photoUrl;
    String initial = 'B';
    try {
      photoUrl = user?.photoURL;
      final name = user?.displayName;
      if (name != null && name.trim().isNotEmpty) {
        initial = name.trim()[0].toUpperCase();
      }
    } catch (_) {}

    return GestureDetector(
      onTap: () => GoRouter.of(context).push('/profile'),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primaryContainer, width: 2),
        ),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryFixed,
          child: ClipOval(
            child: photoUrl != null && photoUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
