import 'package:flutter/material.dart';

/// Én fane i [AppNavBar].
class AppNavDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Grenens indeks i `StatefulShellRoute`.
  final int branchIndex;

  const AppNavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.branchIndex,
  });
}

/// Bundmenu med en hævet, rund knap i midten, der sidder i et udsnit
/// ("dråbe") i baren. Aktiv fane markeres med farve og en prik.
///
/// Fanerne er kun ikoner; navnet læses op af skærmlæsere og vises som
/// tooltip ved langt tryk.
class AppNavBar extends StatelessWidget {
  final List<AppNavDestination> leading;
  final AppNavDestination center;
  final List<AppNavDestination> trailing;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const AppNavBar({
    super.key,
    required this.leading,
    required this.center,
    required this.trailing,
    required this.currentIndex,
    required this.onSelect,
  });

  static const double barHeight = 64;
  static const double centerSize = 60;

  /// Hvor meget midterknappen rager op over baren.
  static const double _rise = 26;
  static const double _notchGap = 6;
  static const double _sideMargin = 16;
  static const double _bottomMargin = 8;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final centerActive = currentIndex == center.branchIndex;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_sideMargin, 0, _sideMargin, _bottomMargin),
        child: SizedBox(
          height: barHeight + _rise,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                top: _rise,
                child: CustomPaint(
                  painter: _NotchedBarPainter(
                    color: cs.surfaceContainerLowest,
                    shadowColor: cs.primary.withValues(alpha: 0.18),
                    notchRadius: centerSize / 2 + _notchGap,
                    notchCenterY: centerSize / 2 - _rise,
                  ),
                  child: Row(
                    children: [
                      for (final d in leading) Expanded(child: _tab(d)),
                      // Plads til midterknappen; prikken under den vises her.
                      SizedBox(
                        width: centerSize + 2 * _notchGap + 8,
                        child: Align(
                          alignment: const Alignment(0, 0.75),
                          child: _ActiveDot(visible: centerActive, color: cs.primary),
                        ),
                      ),
                      for (final d in trailing) Expanded(child: _tab(d)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: _CenterButton(
                  destination: center,
                  isActive: centerActive,
                  onTap: () => onSelect(center.branchIndex),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(AppNavDestination d) => _NavTab(
        destination: d,
        isActive: currentIndex == d.branchIndex,
        onTap: () => onSelect(d.branchIndex),
      );
}

class _NavTab extends StatelessWidget {
  final AppNavDestination destination;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTab({required this.destination, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isActive ? cs.primary : cs.outline;

    return Semantics(
      button: true,
      selected: isActive,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isActive ? destination.activeIcon : destination.icon,
                    key: ValueKey(isActive),
                    color: color,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 6),
                _ActiveDot(visible: isActive, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  final AppNavDestination destination;
  final bool isActive;
  final VoidCallback onTap;

  const _CenterButton({required this.destination, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: isActive,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: cs.primary,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: cs.primary.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: AppNavBar.centerSize,
              child: Icon(
                isActive ? destination.activeIcon : destination.icon,
                color: cs.onPrimary,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveDot extends StatelessWidget {
  final bool visible;
  final Color color;

  const _ActiveDot({required this.visible, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Tegner baren: et afrundet rektangel med et blødt, rundt udsnit øverst i
/// midten, hvor midterknappen sidder.
class _NotchedBarPainter extends CustomPainter {
  final Color color;
  final Color shadowColor;
  final double notchRadius;

  /// Udsnittets centrum målt fra barens overkant (negativ = over baren).
  final double notchCenterY;

  const _NotchedBarPainter({
    required this.color,
    required this.shadowColor,
    required this.notchRadius,
    required this.notchCenterY,
  });

  Path _path(Size size) {
    final host = Offset.zero & size;
    final guest = Rect.fromCircle(
      center: Offset(size.width / 2, notchCenterY),
      radius: notchRadius,
    );
    final notched = const CircularNotchedRectangle().getOuterPath(host, guest);
    final rounded = Path()..addRRect(RRect.fromRectAndRadius(host, const Radius.circular(24)));
    return Path.combine(PathOperation.intersect, notched, rounded);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawShadow(path, shadowColor, 8, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NotchedBarPainter old) =>
      old.color != color ||
      old.shadowColor != shadowColor ||
      old.notchRadius != notchRadius ||
      old.notchCenterY != notchCenterY;
}
