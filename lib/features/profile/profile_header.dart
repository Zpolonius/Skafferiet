import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/profile_image_provider.dart';
import '../../shared/widgets/settings_list.dart';
import '../auth/auth_provider.dart';
import '../grocery/grocery_provider.dart';
import '../meal_plan/meal_plan_provider.dart';
import '../recipes/recipes_provider.dart';

/// Toppen af profilen (design/profilside_1): billede, navn og e-mail.
class ProfileHeader extends StatelessWidget {
  final User? user;
  const ProfileHeader({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = user?.displayName;

    return Column(
      children: [
        _ProfileAvatar(
          user: user,
          initial: name != null && name.isNotEmpty ? name[0].toUpperCase() : 'U',
        ),
        const SizedBox(height: 16),
        Text(
          name ?? 'Bruger',
          textAlign: TextAlign.center,
          style: text.headlineLarge,
        ),
        const SizedBox(height: 4),
        Text(
          user?.email ?? '',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends ConsumerStatefulWidget {
  final User? user;
  final String initial;

  const _ProfileAvatar({required this.user, required this.initial});

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _isUploading = false;

  String? get _photoUrl {
    try {
      return widget.user?.photoURL;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleTap() async {
    final user = widget.user;
    if (user == null) return;

    final imageService = ref.read(profileImageServiceProvider);
    final photoUrl = _photoUrl;
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;

    setState(() => _isUploading = true);
    try {
      final newUrl = await imageService.pickAndUploadProfileImage(
        context,
        userId: user.uid,
        showDeleteOption: photoUrl != null && photoUrl.isNotEmpty,
      );
      if (!mounted) return;

      final auth = ref.read(authProvider.notifier);
      if (newUrl == '') {
        // Brugeren valgte at fjerne billedet.
        final success = await auth.removeProfilePhoto();
        showResultSnackBar(messenger, colors,
            error: success ? null : 'Kunne ikke fjerne profilbilledet.',
            success: 'Profilbillede fjernet');
      } else if (newUrl != null && newUrl.isNotEmpty) {
        final success = await auth.updateProfilePhoto(newUrl);
        showResultSnackBar(messenger, colors,
            error: success ? null : 'Kunne ikke opdatere profilbilledet.',
            success: 'Profilbillede opdateret');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final photoUrl = _photoUrl;
    final initial = Text(
      widget.initial,
      style: text.displayLarge?.copyWith(color: colors.onPrimary),
    );

    return Semantics(
      button: true,
      label: 'Skift profilbillede',
      child: GestureDetector(
        onTap: _isUploading ? null : _handleTap,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: colors.primaryContainer,
              child: ClipOval(
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
                          ),
                        ),
                        errorWidget: (context, url, error) => initial,
                      )
                    : initial,
              ),
            ),
            if (_isUploading)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.scrim.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3, color: colors.onPrimary),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surfaceContainerLowest, width: 2),
                ),
                child: Icon(Icons.camera_alt_rounded, size: 16, color: colors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tallene under navnet: opskrifter, planlagte dage i denne uge og varer på listen.
class ProfileStatsRow extends ConsumerWidget {
  const ProfileStatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeCount = ref.watch(recipesProvider).value?.length;
    // Dage i denne uge med mindst ét måltid — tomme dage tæller ikke med.
    final mealDays =
        ref.watch(mealPlanProvider).value?.days.values.where((day) => !day.isEmpty).length;
    final groceryCount = ref.watch(groceryListProvider).value?.length;
    final divider = SizedBox(
      height: 40,
      child: VerticalDivider(width: 1, color: Theme.of(context).colorScheme.surfaceContainerHigh),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            _Stat(value: recipeCount, label: 'OPSKRIFTER'),
            divider,
            _Stat(value: mealDays, label: 'PLANLAGTE DAGE'),
            divider,
            _Stat(value: groceryCount, label: 'GEMTE VARER'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int? value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value?.toString() ?? '–',
            style: text.displayMedium?.copyWith(color: colors.primaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}
