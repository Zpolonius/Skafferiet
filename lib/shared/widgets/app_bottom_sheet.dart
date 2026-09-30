import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Åbner et bottom sheet med appens faste regler. Brug altid denne i stedet
/// for `showModalBottomSheet` direkte (en test håndhæver det).
///
/// - `useRootNavigator`: sheetet ligger over bundmenuen, også når det åbnes
///   fra en skærm inde i en fane.
/// - `useSafeArea`: sheetet når aldrig op under statuslinjen/kameraet.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  Color? backgroundColor = Colors.transparent,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: backgroundColor,
    shape: shape,
    builder: builder,
  );
}

/// Luft i bunden af et sheet: tastaturets højde når det er åbent, ellers
/// hjem-stregen. Tastaturet dækker hjem-stregen, så de lægges ikke sammen.
double sheetBottomInset(BuildContext context) {
  final media = MediaQuery.of(context);
  return math.max(media.viewInsets.bottom, media.viewPadding.bottom);
}
