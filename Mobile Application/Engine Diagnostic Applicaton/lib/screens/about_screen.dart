import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('About Us',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: _ShieldIconSmall(size: 60),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Engine Checker',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Version 1.0.0',
                style:
                    TextStyle(color: AppColors.textMuted, fontSize: 14)),
            const SizedBox(height: 32),
            _AboutCard(
              icon: Icons.bolt_rounded,
              title: 'AI-Powered Detection',
              description:
                  'Uses on-device TFLite machine learning to identify engine faults from audio — no internet required.',
            ),
            const SizedBox(height: 12),
            _AboutCard(
              icon: Icons.lock_outline_rounded,
              title: '100% Offline',
              description:
                  'All analysis happens on your device. Your data stays private and never leaves your phone.',
            ),
            const SizedBox(height: 12),
            _AboutCard(
              icon: Icons.speed_rounded,
              title: 'Fast & Accurate',
              description:
                  'Get engine health results in under 5 seconds with high-accuracy fault classification.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ShieldIconSmall extends StatelessWidget {
  final double size;
  const _ShieldIconSmall({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShieldPainter()),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.22)
      ..lineTo(w, h * 0.62)
      ..quadraticBezierTo(w, h * 0.88, w * 0.5, h)
      ..quadraticBezierTo(0, h * 0.88, 0, h * 0.62)
      ..lineTo(0, h * 0.22)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _AboutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _AboutCard(
      {required this.icon,
      required this.title,
      required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.amber, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
