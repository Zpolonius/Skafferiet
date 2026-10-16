import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../grocery/recurring/recurring_items_provider.dart' show clockProvider;
import 'meal_plan_provider.dart';

/// Usynlig widget der får madplanen til at følge datoen, mens appen står åben
/// (#56): når appen kommer tilbage i forgrunden og ved midnat læses "i dag"
/// igen. Skifter ugen, flytter planen, overskriften, weekendhjælpen og
/// skrivningerne med – de udledes alle af [todayProvider].
class DayRollover extends ConsumerStatefulWidget {
  final Widget child;

  const DayRollover({super.key, required this.child});

  @override
  ConsumerState<DayRollover> createState() => _DayRolloverState();
}

class _DayRolloverState extends ConsumerState<DayRollover>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    ref.read(todayProvider.notifier).refresh();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = ref.read(clockProvider)();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _timer =
        Timer(midnight.difference(now) + const Duration(seconds: 5), _refresh);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
