import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        !_preferences.containsAll(household.preferences);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    // Behold rækkefølgen fra listen, så den gemte værdi er stabil.
    final ordered = [
      for (final p in availablePreferences)
        if (_preferences.contains(p.label)) p.label,
      // Gamle valg, der ikke længere findes i listen, bevares.
      ..._preferences.where((p) => !availablePreferences.any((a) => a.label == p)),
    ];
    final error = await ref.read(householdProvider.notifier).updatePreferences(
          adultsCount: _adults,
          childrenCount: _children,
          preferences: ordered,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: errorColor));
      return;
    }
    messenger.showSnackBar(const SnackBar(
      content: Text('Præferencerne er gemt.'),
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final householdName = ref.watch(householdProvider.select((s) => s.householdName));
    // Gem-knappen følger med husstanden, hvis en anden ændrer den imens.
    ref.watch(householdProvider.select((s) => (s.adultsCount, s.childrenCount, s.preferences)));
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
