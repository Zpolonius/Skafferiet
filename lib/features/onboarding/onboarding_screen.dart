import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gap/gap.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_provider.dart';
import '../profile/household_provider.dart';
import 'starter_recipes.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Step 1 data
  late TextEditingController _householdNameController;
  int _adultsCount = 2;
  int _childrenCount = 2;

  // Step 2 data
  final Set<String> _selectedPreferences = {'Børnevenligt', 'Hurtigt & nemt (<30 min)'};

  final List<Map<String, String>> _availablePreferences = [
    {'label': 'Børnevenligt', 'icon': '👶'},
    {'label': 'Hurtigt & nemt (<30 min)', 'icon': '⏱️'},
    {'label': 'Grønt & Sundt', 'icon': '🥗'},
    {'label': 'Budgetvenligt', 'icon': '💰'},
    {'label': 'Klassisk hverdagsmad', 'icon': '🇩🇰'},
    {'label': 'Vegetarisk / Plantebaseret', 'icon': '🌱'},
  ];

  // Step 3 data
  Recipe? _selectedStarterRecipe = starterRecipes.first;
  bool _isCustomMeal = false;
  final _customMealController = TextEditingController();
  final _customMealFocusNode = FocusNode();
  String? _customMealError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    final defaultName = auth.user?.displayName != null
        ? 'Familien ${auth.user!.displayName!.split(' ').last}\'s Skafferi'
        : 'Mit Skafferi';
    _householdNameController = TextEditingController(text: defaultName);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _householdNameController.dispose();
    _customMealController.dispose();
    _customMealFocusNode.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    if (_isCustomMeal && _customMealController.text.trim().isEmpty) {
      setState(() {
        _customMealError = 'Indtast venligst et måltid, eller vælg en opskrift ovenfor';
      });
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(householdProvider.notifier).completeOnboarding(
            householdName: _householdNameController.text.trim().isEmpty
                ? 'Mit Skafferi'
                : _householdNameController.text.trim(),
            adultsCount: _adultsCount,
            childrenCount: _childrenCount,
            preferences: _selectedPreferences.toList(),
            starterRecipe: _isCustomMeal ? null : _selectedStarterRecipe,
            customMeal: _isCustomMeal ? _customMealController.text.trim() : null,
          );

      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Velkommen til dit Skafferi! Vi har gjort madplanen og indkøbslisten klar til dig.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _skipMealSelection() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(householdProvider.notifier).completeOnboarding(
            householdName: _householdNameController.text.trim().isEmpty
                ? 'Mit Skafferi'
                : _householdNameController.text.trim(),
            adultsCount: _adultsCount,
            childrenCount: _childrenCount,
            preferences: _selectedPreferences.toList(),
            starterRecipe: null,
            customMeal: null,
          );

      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Velkommen til dit Skafferi! Din profil er nu oprettet.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _currentStep = page),
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Image.asset('assets/images/logo.png', height: 28),
                  const Gap(8),
                  Text(
                    'Skafferiet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (_currentStep == 2)
                TextButton(
                  onPressed: _isSubmitting ? null : _skipMealSelection,
                  child: const Text(
                    'Spring over',
                    style: TextStyle(
                      color: AppColors.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Text(
                  'Trin ${_currentStep + 1} af 3',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.outline,
                  ),
                ),
            ],
          ),
          const Gap(16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              minHeight: 6,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Hvem spiser med? ───────────────────────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.family_restroom_rounded, color: AppColors.primary, size: 32),
          ),
          const Gap(16),
          Text(
            'Hvem spiser med?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const Gap(8),
          const Text(
            'Giv jeres husstand et navn og fortæl, hvor mange I typisk er ved middagsbordet.',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const Gap(28),
          Text(
            'Husstandens navn',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const Gap(8),
          TextFormField(
            controller: _householdNameController,
            decoration: InputDecoration(
              hintText: 'F.eks. Familien Jensens Skafferi',
              prefixIcon: const Icon(Icons.home_outlined, color: AppColors.primary),
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
          const Gap(28),
          Text(
            'Familiestørrelse',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const Gap(12),
          _CounterCard(
            title: 'Voksne',
            subtitle: '13+ år',
            count: _adultsCount,
            canDecrement: _adultsCount + _childrenCount > 1,
            onChanged: (val) => setState(() => _adultsCount = val),
          ),
          const Gap(12),
          _CounterCard(
            title: 'Børn',
            subtitle: '0-12 år',
            count: _childrenCount,
            canDecrement: _adultsCount + _childrenCount > 1,
            onChanged: (val) => setState(() => _childrenCount = val),
          ),
          const Gap(12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                const Gap(8),
                Text(
                  'Giver ca. ${_adultsCount + _childrenCount} portioner pr. opskrift',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Familiens madstil ───────────────────────────────────────────────
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.restaurant_menu_rounded, color: AppColors.primary, size: 32),
          ),
          const Gap(16),
          Text(
            'Familiens madstil',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const Gap(8),
          const Text(
            'Vælg de temaer, der bedst beskriver jeres hverdag. Vælg én, flere eller spring over (valgfrit).',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const Gap(28),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: _availablePreferences.map((pref) {
              final label = pref['label']!;
              final icon = pref['icon']!;
              final isSelected = _selectedPreferences.contains(label);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedPreferences.remove(label);
                    } else {
                      _selectedPreferences.add(label);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryContainer.withValues(alpha: 0.12)
                        : AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const Gap(8),
                      Text(
                        label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppColors.primary : AppColors.onSurface,
                        ),
                      ),
                      if (isSelected) ...[
                        const Gap(8),
                        const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Aftensmad til i aften ───────────────────────────────────────────
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.dinner_dining_rounded, color: AppColors.primary, size: 32),
          ),
          const Gap(16),
          Text(
            'Hvad skal I have i aften?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const Gap(8),
          const Text(
            'Vælg et måltid, så lægger vi det i madplanen og overfører ingredienserne til indkøbslisten med det samme.',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const Gap(24),
          ...starterRecipes.map((recipe) {
            final isSelected = !_isCustomMeal && _selectedStarterRecipe?.id == recipe.id;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isCustomMeal = false;
                    _selectedStarterRecipe = recipe;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryContainer.withValues(alpha: 0.08)
                        : AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          recipe.imageUrl ?? '',
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64,
                            height: 64,
                            color: AppColors.surfaceContainerHigh,
                            child: const Icon(Icons.restaurant, color: AppColors.outline),
                          ),
                        ),
                      ),
                      const Gap(14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recipe.title,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const Gap(4),
                            Text(
                              '🔥 ${recipe.calories} kcal • ⏱️ ${recipe.time}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                            ),
                            const Gap(4),
                            Text(
                              '${recipe.ingredients.length} ingredienser til indkøb',
                              style: const TextStyle(fontSize: 12, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? AppColors.primary : AppColors.outline,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Gap(12),
          InkWell(
            onTap: () {
              setState(() => _isCustomMeal = true);
              _customMealFocusNode.requestFocus();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isCustomMeal
                    ? AppColors.primaryContainer.withValues(alpha: 0.08)
                    : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isCustomMeal ? AppColors.primary : AppColors.outlineVariant,
                  width: _isCustomMeal ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryFixed,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.edit_note, color: AppColors.secondary, size: 24),
                      ),
                      const Gap(14),
                      Expanded(
                        child: Text(
                          'Eller skriv jeres eget måltid',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        _isCustomMeal ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: _isCustomMeal ? AppColors.primary : AppColors.outline,
                      ),
                    ],
                  ),
                  if (_isCustomMeal) ...[
                    const Gap(14),
                    TextFormField(
                      controller: _customMealController,
                      focusNode: _customMealFocusNode,
                      onChanged: (_) {
                        if (_customMealError != null) {
                          setState(() => _customMealError = null);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'F.eks. Hakkebøffer med bløde løg',
                        errorText: _customMealError,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.outlineVariant),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: _isSubmitting ? null : _previousPage,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: AppColors.outlineVariant),
              ),
              child: const Text('Tilbage'),
            ),
            const Gap(12),
          ],
          Expanded(
            child: FilledButton(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      if (_currentStep < 2) {
                        _nextPage();
                      } else {
                        _finishOnboarding();
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      _currentStep == 2 ? 'Færdiggør og åbn Skafferiet' : 'Næste',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final bool canDecrement;
  final ValueChanged<int> onChanged;

  const _CounterCard({
    required this.title,
    required this.subtitle,
    required this.count,
    this.canDecrement = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.outline,
                    ),
              ),
            ],
          ),
          Row(
            children: [
              _CircleBtn(
                icon: Icons.remove,
                onTap: (count > 0 && canDecrement) ? () => onChanged(count - 1) : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              _CircleBtn(
                icon: Icons.add,
                onTap: count < 10 ? () => onChanged(count + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isEnabled
              ? AppColors.primaryContainer.withValues(alpha: 0.1)
              : AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: isEnabled ? AppColors.primary : AppColors.outline,
        ),
      ),
    );
  }
}
