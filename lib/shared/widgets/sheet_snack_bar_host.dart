import 'package:flutter/material.dart';

/// Giver et modalt ark (på root-navigatoren) en SnackBar der faktisk kan ses.
///
/// En SnackBar fra rodens `ScaffoldMessenger` tegnes på skærmens Scaffold og
/// ligger derfor bag arkets barriere. Her lægges en lille egen
/// messenger + Scaffold i root-overlayet, helt øverst på skærmen (over
/// barrieren, hvor arket aldrig når op – arkets højde er højst 85 %), så den
/// hverken dækker arkets felter eller knapper. Overlayet lukker pegere
/// igennem, medmindre en SnackBar vises, og fjernes med arket.
class SheetSnackBarHost {
  static const _height = 72.0;

  final GlobalKey<ScaffoldMessengerState> _key =
      GlobalKey<ScaffoldMessengerState>();
  final ValueNotifier<int> _active = ValueNotifier(0);
  OverlayEntry? _entry;
  bool _disposed = false;

  /// Messengeren, eller `null` før overlayet er bygget første gang.
  ScaffoldMessengerState? get messenger => _key.currentState;

  /// Lægger overlayet ind. Kaldes når arket er bygget (efter første frame).
  void attach(BuildContext context) {
    if (_disposed || _entry != null) return;
    _entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.paddingOf(ctx).top,
        left: 0,
        right: 0,
        height: _height,
        child: ValueListenableBuilder<int>(
          valueListenable: _active,
          builder: (_, active, child) =>
              IgnorePointer(ignoring: active == 0, child: child),
          child: MediaQuery.removePadding(
            context: ctx,
            removeTop: true,
            removeBottom: true,
            child: MediaQuery.removeViewInsets(
              context: ctx,
              removeBottom: true,
              child: ScaffoldMessenger(
                key: _key,
                child: const Scaffold(
                  backgroundColor: Colors.transparent,
                  resizeToAvoidBottomInset: false,
                  body: SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  final List<VoidCallback> _onDispose = [];

  /// Registrerer en vist SnackBar, så overlayet tager imod tryk mens den ses.
  /// [onDispose] kaldes når arket lukkes (før overlayet fjernes), så en
  /// SnackBar der stadig er aktiv kan flyttes til rodens messenger.
  void track(ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? c,
      {VoidCallback? onDispose}) {
    if (c == null || _disposed) return;
    if (onDispose != null) _onDispose.add(onDispose);
    _active.value++;
    c.closed.whenComplete(() {
      if (!_disposed) _active.value--;
    });
  }

  void dispose() {
    for (final f in _onDispose) {
      f();
    }
    _onDispose.clear();
    _disposed = true;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _active.dispose();
  }
}
