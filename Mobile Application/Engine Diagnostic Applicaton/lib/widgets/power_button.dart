import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum PowerButtonState { idle, analyzing, good, faulty }

class PowerButton extends StatefulWidget {
  final PowerButtonState state;
  final VoidCallback? onTap;

  const PowerButton({super.key, required this.state, this.onTap});

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with TickerProviderStateMixin {
  late AnimationController _spinCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.92, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _updateAnimations();
  }

  @override
  void didUpdateWidget(PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _updateAnimations();
  }

  void _updateAnimations() {
    if (widget.state == PowerButtonState.analyzing) {
      _spinCtrl.repeat();
    } else {
      _spinCtrl.stop();
      _spinCtrl.reset();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _ringColor {
    switch (widget.state) {
      case PowerButtonState.idle:
        return AppColors.amber;
      case PowerButtonState.analyzing:
        return AppColors.amber;
      case PowerButtonState.good:
        return AppColors.good;
      case PowerButtonState.faulty:
        return AppColors.faulty;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _pulseAnim,
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow rings
              _RingLayer(
                  size: 160, color: _ringColor.withOpacity(0.15), thickness: 4),
              _RingLayer(
                  size: 140, color: _ringColor.withOpacity(0.25), thickness: 4),

              // Spinning arc (analyzing state only)
              if (widget.state == PowerButtonState.analyzing)
                AnimatedBuilder(
                  animation: _spinCtrl,
                  builder: (_, __) => Transform.rotate(
                    angle: _spinCtrl.value * 2 * pi,
                    child: CustomPaint(
                      size: const Size(120, 120),
                      painter: _ArcPainter(color: AppColors.amber),
                    ),
                  ),
                ),

              // Static ring in non-analyzing states
              if (widget.state != PowerButtonState.analyzing)
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _ArcPainter(color: _ringColor, sweep: 2 * pi),
                ),

              // Center circle button
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: _ringColor.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  color: _ringColor,
                  size: 38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingLayer extends StatelessWidget {
  final double size;
  final Color color;
  final double thickness;

  const _RingLayer(
      {required this.size, required this.color, required this.thickness});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: thickness),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  final double sweep;

  const _ArcPainter({required this.color, this.sweep = pi * 1.4});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.color != color || old.sweep != sweep;
}
