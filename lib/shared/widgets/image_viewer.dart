import 'package:flutter/material.dart';
import '../../core/theme/theme_context.dart';

/// Netværksbillede med pladsholder mens det indlæses og et ikon hvis det ikke
/// kan hentes – så en død URL aldrig giver en rød fejlboks.
class AppNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double iconSize;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: context.colors.surfaceContainerHigh,
          child: Center(
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: context.colors.surfaceContainerHigh,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: iconSize,
            color: context.colors.outline,
          ),
        ),
      ),
    );
  }
}

/// Åbner [url] i fuld skærm med pinch-zoom. Lukkes med krydset, et tryk på
/// baggrunden eller ved at stryge nedad. Med samme [heroTag] som miniaturen
/// glider billedet ud fra den.
Future<void> showImageViewer(
  BuildContext context, {
  required String url,
  required Object heroTag,
  required String label,
}) {
  return Navigator.of(context, rootNavigator: true)
      .push<void>(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) =>
        _ImageViewerPage(url: url, heroTag: heroTag, label: label),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class _ImageViewerPage extends StatefulWidget {
  final String url;
  final Object heroTag;
  final String label;

  const _ImageViewerPage({
    required this.url,
    required this.heroTag,
    required this.label,
  });

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  final _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final heroTag = widget.heroTag;
    final label = widget.label;
    final colors = context.colors;
    return Material(
      key: const Key('image_viewer'),
      color: colors.scrim.withValues(alpha: 0.92),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Dismissible(
            key: const Key('image_viewer_dismiss'),
            // Zoomet billede skal kunne panoreres uden at lukke vieweren.
            direction: _zoomed ? DismissDirection.none : DismissDirection.down,
            onDismissed: (_) => Navigator.of(context).pop(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _zoomed ? null : () => Navigator.of(context).pop(),
              child: Semantics(
                image: true,
                label: label,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Hero(
                      tag: heroTag,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : Center(
                                    child: CircularProgressIndicator(
                                      color: colors.surface,
                                    ),
                                  ),
                        errorBuilder: (context, error, stackTrace) =>
                            // FittedBox, så hero-animationen fra den lille
                            // miniature ikke giver overflow.
                            FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined,
                                    size: 48, color: colors.surface),
                                const SizedBox(height: 8),
                                Text(
                                  'Billedet kunne ikke indlæses',
                                  style: context.text.bodyMedium
                                      ?.copyWith(color: colors.surface),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: 'Luk',
                  icon: Icon(Icons.close, color: colors.surface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
