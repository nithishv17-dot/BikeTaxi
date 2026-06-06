import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

class AppPalette {
  // Premium Design System Tokens
  static const Color primary = Color(0xFF2563EB);
  static const Color secondary = Color(0xFF10B981);
  static const Color accent = Color(0xFFF59E0B);
  static const Color background = Color(0xFFF8FAFC);
  static const Color textPrimary = Color(0xFF0F172A);

  // Backward compatibility mappings for smooth migration
  static const Color navy900 = Color(0xFF0B132A);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color teal600 = Color(0xFF2563EB); // Maps to primary
  static const Color teal500 = Color(0xFF2563EB); // Maps to primary
  static const Color sky500 = Color(0xFF10B981);  // Maps to secondary
  static const Color amber500 = Color(0xFFF59E0B); // Maps to accent
  static const Color mint50 = Color(0xFFEFF6FF);  // soft blue tint
  static const Color cloud50 = Color(0xFFF8FAFC); // background
  static const Color ice50 = Color(0xFFF8FAFC);   // background
}

class PremiumBackdrop extends StatefulWidget {
  final Widget child;
  final Color accentColor;
  final Color secondaryColor;

  const PremiumBackdrop({
    super.key,
    required this.child,
    this.accentColor = AppPalette.primary,
    this.secondaryColor = AppPalette.secondary,
  });

  @override
  State<PremiumBackdrop> createState() => _PremiumBackdropState();
}

class _PremiumBackdropState extends State<PremiumBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildGlowBlob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * pi;
        final topDrift = sin(t) * 40;
        final sideDrift = cos(t) * 32;
        final bottomDrift = sin(t + 0.6) * 36;

        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppPalette.mint50,
                      AppPalette.cloud50,
                      Colors.white,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -120 + topDrift,
              right: -60 + sideDrift,
              child: _buildGlowBlob(widget.accentColor.withOpacity(0.22), 260),
            ),
            Positioned(
              top: 180 - sideDrift,
              left: -130,
              child: _buildGlowBlob(
                widget.secondaryColor.withOpacity(0.18),
                300,
              ),
            ),
            Positioned(
              bottom: -140 + bottomDrift,
              right: 40,
              child: _buildGlowBlob(
                const Color(0xFF22D3EE).withOpacity(0.14),
                280,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.34),
                      Colors.transparent,
                      Colors.white.withOpacity(0.55),
                    ],
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}

class ReflectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final Color tintColor;

  const ReflectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.onTap,
    this.tintColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final core = Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tintColor.withOpacity(0.88),
                  Colors.white.withOpacity(0.72),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.7)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -26,
          left: -12,
          right: -12,
          height: 88,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -0.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.36),
                      Colors.white.withOpacity(0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );

    final wrapped = onTap == null
        ? core
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              child: core,
            ),
          );

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: wrapped,
      ),
    );
  }
}

class ReflectiveBanner extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  const ReflectiveBanner({
    super.key,
    required this.child,
    this.colors = const [AppPalette.primary, AppPalette.secondary],
    this.borderRadius = const BorderRadius.all(Radius.circular(30)),
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.34),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            right: -22,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -46,
            left: -18,
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: -16,
            left: -8,
            right: 36,
            height: 64,
            child: Transform.rotate(
              angle: -0.24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.24),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class RevealMotion extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  const RevealMotion({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.beginOffset = const Offset(0, 0.08),
  });

  @override
  State<RevealMotion> createState() => _RevealMotionState();
}

class _RevealMotionState extends State<RevealMotion> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() {
        _isVisible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1 : 0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        offset: _isVisible ? Offset.zero : widget.beginOffset,
        child: widget.child,
      ),
    );
  }
}
