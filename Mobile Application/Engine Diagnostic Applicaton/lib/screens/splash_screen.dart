import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.amber,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: _ShieldIcon(size: 140),
          ),
        ),
      ),
    );
  }
}

class _ShieldIcon extends StatelessWidget {
  final double size;
  const _ShieldIcon({required this.size});

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

    // Outer shield – slightly lighter amber
    final outerPaint = Paint()
      ..color = const Color(0xFFFFD54F).withOpacity(0.55)
      ..style = PaintingStyle.fill;

    final outerPath = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.22)
      ..lineTo(w, h * 0.62)
      ..quadraticBezierTo(w, h * 0.88, w * 0.5, h)
      ..quadraticBezierTo(0, h * 0.88, 0, h * 0.62)
      ..lineTo(0, h * 0.22)
      ..close();

    canvas.drawPath(outerPath, outerPaint);

    // Inner shield – white
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.90)
      ..style = PaintingStyle.fill;

    final s = 0.72;
    final dx = w * (1 - s) / 2;
    final dy = h * 0.08;

    final innerPath = Path()
      ..moveTo(w * 0.5, dy)
      ..lineTo(w * s + dx, h * 0.22 + dy * 0.5)
      ..lineTo(w * s + dx, h * 0.58)
      ..quadraticBezierTo(
          w * s + dx, h * 0.80, w * 0.5, h * 0.88)
      ..quadraticBezierTo(dx, h * 0.80, dx, h * 0.58)
      ..lineTo(dx, h * 0.22 + dy * 0.5)
      ..close();

    canvas.drawPath(innerPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
