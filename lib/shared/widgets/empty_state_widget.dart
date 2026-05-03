import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../core/theme/app_colors.dart';

class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final String lottieUrl;

  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.message,
    required this.lottieUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.network(
              lottieUrl,
              height: 200,
              repeat: true,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.displaySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
