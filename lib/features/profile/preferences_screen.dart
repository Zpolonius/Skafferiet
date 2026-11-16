import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_context.dart';
import '../../core/services/meal_plan_dates.dart';
import '../../shared/utils/danish_dates.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/settings_list.dart';
import '../onboarding/household_setup_widgets.dart';
import 'household_provider.dart';

/// "Præferencer & Diæt": husstandens størrelse og madstil — de samme valg
/// som i onboardingen. Gælder for hele husstanden.
class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  late int _adults;
  late int _children;
  late Set<String> _preferences;

  /// Madplanens startdag brugeren har valgt her. null = intet valgt endnu; så
  /// skrives intet, og husstandens værdi (eller mandag) gælder stadig.
  int? _startWeekday;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final household = ref.read(householdProvider);
    _adults = household.adultsCount.clamp(0, maxHouseholdCount);
    _children = household.childrenCount.clamp(0, maxHouseholdCount);
    _preferences = {...household.preferences};
  }

  bool get _hasChanges {
    final household = ref.read(householdProvider);
    return _adults != household.adultsCount ||
        _children != household.childrenCount ||
        _preferences.length != household.preferences.length ||
        !_preferences.containsAll(household.preferences) ||
        (_startWeekday != null && _startWeekday != household.mealPlanStartWeekday);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;
    // Behold rækkefølgen fra listen, så den gemte værdi er stabil.
    final ordered = [
      for (final p in availablePreferences)
        if (_preferences.contains(p.label)) p.label,
      // Gamle valg, der ikke længere findes i listen, bevares.
      ..._preferences.where((p) => !availablePreferences.any((a) => a.label == p)),
    ];
    final notifier = ref.read(householdProvider.notifier);
    // Startdagen sendes kun med, når brugeren har valgt en (forslaget skrives ikke).
    final start = _startWeekday;
    final error = start == null
        ? await notifier.updatePreferences(
            adultsCount: _adults, childrenCount: _children, preferences: ordered)
        : await notifier.updatePreferences(
            adultsCount: _adults,
            childrenCount: _children,
            preferences: ordered,
            mealPlanStartWeekday: start);
    if (!mounted) return;
    setState(() => _saving = false);
    showResultSnackBar(messenger, colors, error: error, success: 'Præferencerne er gemt.');
    if (error == null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final householdName = ref.watch(householdProvider.select((s) => s.householdName));
    // Gem-knappen følger med husstanden, hvis en anden ændrer den imens.
    ref.watch(householdProvider
        .select((s) => (s.adultsCount, s.childrenCount, s.preferences, s.mealPlanStartWeekday)));
    final household = ref.watch(householdProvider);
    // Valgt dag; ellers husstandens; ellers dagen efter indkøbsdagen som forslag.
    final saved = household.mealPlanStartWeekday;
    final suggestion = suggestedPlanStart(household.shoppingWeekday);
    final shownStart = _startWeekday ?? saved ?? suggestion;
    final startSubtitle = _startWeekday == null && saved == null
        ? (household.shoppingWeekday != null
            ? 'Forslag: dagen efter indkøbsdagen'
            : 'Standard')
        : null;
    final canSave = !_saving && _hasChanges;

    return Scaffold(
      appBar: AppBar(title: const Text('Præferencer & Diæt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              householdName != null
                  ? 'Gælder for alle i "$householdName".'
                  : 'Gælder for alle i husstanden.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text('Familiestørrelse', style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            CounterCard(
              title: 'Voksne',
              subtitle: '13+ år',
              count: _adults,
              canDecrement: _adults + _children > 1,
              onChanged: (v) => setState(() => _adults = v),
            ),
            const SizedBox(height: 12),
            CounterCard(
              title: 'Børn',
              subtitle: '0-12 år',
              count: _children,
              canDecrement: _adults + _children > 1,
              onChanged: (v) => setState(() => _children = v),
            ),
            const SizedBox(height: 28),
            Text('Madstil', style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Vælg de temaer, der passer til jeres hverdag.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            PreferenceChips(
              selected: _preferences,
              onToggle: (label) => setState(() {
                if (!_preferences.remove(label)) _preferences.add(label);
              }),
            ),
            const SizedBox(height: 28),
            const SectionTitle('Madplan'),
            SettingsGroup(children: [
              SettingsTile(
                key: const Key('meal-plan-start-tile'),
                icon: Icons.calendar_month_outlined,
                title: 'Madplanen starter',
                subtitle: startSubtitle == null
                    ? weekdayName(shownStart)
                    : '${weekdayName(shownStart)} · $startSubtitle',
                onTap: () async {
                  final chosen = await showAppBottomSheet<int>(
                    context: context,
                    builder: (_) => _StartDaySheet(current: shownStart),
                  );
                  if (chosen != null) setState(() => _startWeekday = chosen);
                },
              ),
            ]),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Gem'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vælg hvilken ugedag madplanen starter på.
class _StartDaySheet extends StatelessWidget {
  final int current;
  const _StartDaySheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.only(top: 24, bottom: sheetBottomInset(context) + 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Madplanen starter',
                  style: context.text.displayMedium),
            ),
            const SizedBox(height: 8),
            for (var day = DateTime.monday; day <= DateTime.sunday; day++)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(weekdayName(day)),
                trailing: day == current ? Icon(Icons.check, color: colors.primary) : null,
                selected: day == current,
                onTap: () => Navigator.pop(context, day),
              ),
          ],
        ),
      ),
    );
  }
}
