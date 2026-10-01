import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/theme_context.dart';

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
          : _buildBannerContent(context, status),
    );
  }

  Widget _buildBannerContent(BuildContext context, NetworkStatus status) {
    final isOffline = status == NetworkStatus.offline;

    final bgColor =
        isOffline ? context.colors.secondaryFixed : context.colors.primaryFixed;
    final fgColor =
        isOffline ? context.colors.onSecondaryFixed : context.colors.onPrimaryFixed;
    final borderColor = isOffline
        ? context.colors.secondaryFixedDim.withValues(alpha: 0.4)
        : context.colors.primaryFixedDim.withValues(alpha: 0.4);
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
                style: context.text.bodySmall?.copyWith(
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
