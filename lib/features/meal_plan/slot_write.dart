import 'dart:async';

/// Resultat af [awaitSlotWrite].
enum SlotWriteResult {
  /// Skrivningen er bekræftet.
  done,

  /// Skrivningen er lagt i Firestores lokale kø, men serveren har ikke
  /// svaret endnu (typisk offline). Appen viser allerede den nye tilstand.
  pending,
}

/// Venter kort på en Firestore-skrivning.
///
/// Firestore anvender skrivninger lokalt med det samme, men fuldfører først
/// fremtiden når serveren har svaret. Offline ville et ark der venter på
/// svaret derfor aldrig kunne lukkes. Svarer serveren inden for [wait] (det
/// gør den normalt, også med fejl som `permission-denied`), kan arket vise en
/// fejl og blive åbent. Ellers returneres [SlotWriteResult.pending], og en
/// fejl der kommer senere meldes til [onLateError].
Future<SlotWriteResult> awaitSlotWrite(
  Future<void> write, {
  required void Function(Object error) onLateError,
  Duration wait = const Duration(seconds: 1),
}) {
  final result = Completer<SlotWriteResult>();
  final timer = Timer(wait, () {
    if (!result.isCompleted) result.complete(SlotWriteResult.pending);
  });
  write.then((_) {
    timer.cancel();
    if (!result.isCompleted) result.complete(SlotWriteResult.done);
  }, onError: (Object error, StackTrace stack) {
    timer.cancel();
    if (result.isCompleted) {
      onLateError(error);
    } else {
      result.completeError(error, stack);
    }
  });
  return result.future;
}
