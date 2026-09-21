import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/app_colors.dart';

/// A subtle, non-intrusive banner that informs users when the app is offline
/// or when connectivity has just been restored.
///
/// Designed in accordance with the "Kitchen Harmony" design system.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      child: status == NetworkStatus.online
          ? const SizedBox.shrink()
          : _buildBannerContent(status),
    );
  }

  Widget _buildBannerContent(NetworkStatus status) {
    final isOffline = status == NetworkStatus.offline;

    final bgColor =
        isOffline ? AppColors.secondaryFixed : AppColors.primaryFixed;
    final fgColor =
        isOffline ? AppColors.onSecondaryFixed : AppColors.onPrimaryFixed;
    final borderColor = isOffline
        ? AppColors.secondaryFixedDim.withValues(alpha: 0.4)
        : AppColors.primaryFixedDim.withValues(alpha: 0.4);
    final icon = isOffline
        ? Icons.wifi_off_rounded
        : Icons.cloud_done_outlined;
    final text = isOffline
        ? 'Offline-tilstand – ændringer gemmes og synkroniseres'
        : 'Forbindelse genoprettet – synkroniserer...';

    return Container(
      key: ValueKey<NetworkStatus>(status),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
          bottom: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: fgColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
