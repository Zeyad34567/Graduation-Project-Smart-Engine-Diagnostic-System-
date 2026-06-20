import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Draws a simplified decorative world-map dot grid used as the dashboard BG.
class MapBackground extends StatelessWidget {
  const MapBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.amber.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Simple dot-grid approximation of a world map
    const cols = 38;
    const rows = 20;
    final dx = size.width / cols;
    final dy = size.height / rows;

    // Rough continent mask (very simplified)
    final continents = _buildContinentRects(size);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final cx = c * dx + dx / 2;
        final cy = r * dy + dy / 2;
        final pt = Offset(cx, cy);

        for (final rect in continents) {
          if (rect.contains(pt)) {
            canvas.drawCircle(pt, 2.2, paint);
            break;
          }
        }
      }
    }
  }

  List<Rect> _buildContinentRects(Size s) {
    final w = s.width;
    final h = s.height;
    return [
      // North America
      Rect.fromLTWH(w * 0.04, h * 0.12, w * 0.22, h * 0.38),
      // South America
      Rect.fromLTWH(w * 0.16, h * 0.52, w * 0.14, h * 0.38),
      // Europe
      Rect.fromLTWH(w * 0.42, h * 0.08, w * 0.12, h * 0.28),
      // Africa
      Rect.fromLTWH(w * 0.44, h * 0.36, w * 0.12, h * 0.42),
      // Asia
      Rect.fromLTWH(w * 0.52, h * 0.06, w * 0.30, h * 0.44),
      // Australia
      Rect.fromLTWH(w * 0.72, h * 0.56, w * 0.14, h * 0.26),
    ];
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
