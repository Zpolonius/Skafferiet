import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => GoRouter.of(context).push('/profile'),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primaryContainer, width: 2),
        ),
        child: const CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryFixed,
          child: Icon(Icons.person, size: 20, color: AppColors.primary),
        ),
      ),
    );
  }
}
