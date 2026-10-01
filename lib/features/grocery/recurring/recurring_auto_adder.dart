import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/recurring_item.dart';
import '../../profile/household_provider.dart';
import 'recurring_items_provider.dart';

/// Usynlig widget der lægger forfaldne faste varer på indkøbslisten:
/// - når appen åbnes, og når listen af faste varer ændres,
/// - når appen kommer tilbage i forgrunden,
/// - ved midnat, hvis appen står åben.
class RecurringAutoAdder extends ConsumerStatefulWidget {
  final Widget child;

  const RecurringAutoAdder({super.key, required this.child});

  @override
  ConsumerState<RecurringAutoAdder> createState() => _RecurringAutoAdderState();
}

class _RecurringAutoAdderState extends ConsumerState<RecurringAutoAdder>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AsyncValue<List<RecurringItem>>>(
      recurringItemsProvider,
      (_, next) => next.whenData(_process),
      fireImmediately: true,
    );
    _scheduleMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _processCurrent();
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = ref.read(clockProvider)();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextMidnight.difference(now) + const Duration(minutes: 1),
      () {
        _processCurrent();
        _scheduleMidnight();
      },
    );
  }

  void _processCurrent() {
    final items = ref.read(recurringItemsProvider).valueOrNull;
    if (items != null) _process(items);
  }

  void _process(List<RecurringItem> items) {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null || items.isEmpty) return;
    ref.read(recurringItemsServiceProvider).processDue(householdId, items);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
