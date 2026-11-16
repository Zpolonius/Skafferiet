import 'package:flutter/material.dart';
import '../../core/models/item_history.dart';
import 'item_history_provider.dart';

typedef SnackBarController
    = ScaffoldFeatureController<SnackBar, SnackBarClosedReason>;

/// Fjerner et forslag fra husstandens varehistorik og viser "Forslag fjernet"
/// med Fortryd (som i madplanen). Bruges af både hurtig-tilføj og "Tilføj
/// vare". Forslaget forsvinder med det samme og Fortryd bringer det tilbage
/// med det samme – ingen af delene venter på serveren, så det virker offline.
///
/// [messenger] er den der vises for brugeren (i arket arkets egen, ikke rodens,
/// som ligger bag det modale ark). Svar fra serveren kan komme efter at arket
/// er lukket og dens messenger væk; så bruges [fallback] (rodens), og intet
/// rører en messenger der ikke længere er monteret.
///
/// [onShown] får hver vist SnackBar og en funktion der flytter den til
/// [fallback] – arket kalder den når det lukkes, så fortrydelsesvinduet ikke
/// slutter med arket (den flyttes ikke hvis den allerede er lukket/fortrudt).
void removeSuggestionWithUndo({
  required ScaffoldMessengerState? Function() messenger,
  ScaffoldMessengerState? Function()? fallback,
  required ItemHistoryNotifier notifier,
  required ItemHistoryEntry entry,
  required Color errorColor,
  void Function(SnackBarController controller, VoidCallback moveToFallback)?
      onShown,
}) {
  ScaffoldMessengerState? usable(ScaffoldMessengerState? m) =>
      m != null && m.mounted ? m : null;
  ScaffoldMessengerState? target() =>
      usable(messenger()) ?? usable(fallback?.call());

  SnackBarController? current;
  ScaffoldMessengerState? currentOn;
  // Sat når serveren afviser sletningen: forslaget er da stadig i historikken,
  // så Fortryd må ikke gendanne (det ville lægge useCount oven i den
  // eksisterende) og en "Forslag fjernet" i kø må ikke dukke op.
  var deleteFailed = false;
  // Om [current] faktisk vises. En bar i kø bag en anden må ikke lukkes med
  // close() – det rammer den der vises (og fejler et assert i debug).
  var currentVisible = false;

  SnackBarController show(
      ScaffoldMessengerState m,
      SnackBar Function(Duration duration, VoidCallback onVisible) build,
      Duration duration) {
    late final SnackBarController c;
    c = m.showSnackBar(build(duration, () {
      if (!identical(current, c)) return;
      currentVisible = true;
      if (deleteFailed) c.close();
    }));
    current = c;
    currentOn = m;
    currentVisible = false;
    c.closed.whenComplete(() {
      if (identical(current, c)) currentVisible = false;
    });
    return c;
  }

  void present(
      SnackBar Function(Duration duration, VoidCallback onVisible) build,
      Duration duration) {
    final shownAt = DateTime.now();
    final m = target();
    if (m == null) return;
    m.hideCurrentSnackBar();
    final c = show(m, build, duration);
    var finished = false;
    c.closed.whenComplete(() => finished = true);
    onShown?.call(c, () {
      if (finished || deleteFailed) return;
      // Udskudt: arket afmonteres lige nu, og en messenger må ikke ændres
      // midt i det.
      Future.microtask(() {
        final f = usable(fallback?.call());
        if (f == null || f == currentOn || deleteFailed) return;
        // Køes bag det der allerede vises i roden (fx en bekræftelse): aldrig
        // hide/erstat. Resten af de oprindelige sekunder, dog mindst 2.
        final left = duration - DateTime.now().difference(shownAt);
        const floor = Duration(seconds: 2);
        show(f, build, left < floor ? floor : left);
      });
    });
  }

  Future<void> restore() async {
    if (deleteFailed) return;
    try {
      await notifier.restore(entry);
    } catch (_) {
      present(
          (d, onVisible) => SnackBar(
                onVisible: onVisible,
                content: const Text('Kunne ikke fortryde. Prøv igen.'),
                backgroundColor: errorColor,
                behavior: SnackBarBehavior.floating,
                duration: d,
                action: SnackBarAction(label: 'Prøv igen', onPressed: restore),
              ),
          const Duration(seconds: 8));
    }
  }

  present(
      (d, onVisible) => SnackBar(
            onVisible: onVisible,
            content: const Text('Forslag fjernet'),
            behavior: SnackBarBehavior.floating,
            duration: d,
            action: SnackBarAction(label: 'Fortryd', onPressed: restore),
          ),
      const Duration(seconds: 6));
  notifier.remove(entry.key).then((ok) {
    // Sletningen fejlede: listen er sat tilbage, så der er intet at fortryde.
    // En bar i kø lukkes først når den vises (se show).
    if (ok) return;
    deleteFailed = true;
    if (currentVisible && currentOn?.mounted == true) current?.close();
  });
}
