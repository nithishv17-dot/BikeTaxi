import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AuroraBackground extends StatelessWidget {
  const AuroraBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE8FBF7),
                Color(0xFFEAF2FB),
                Color(0xFFF6FAFF),
              ],
            ),
          ),
        ),
        const Positioned(
          top: -120,
          left: -90,
          child: _GlowOrb(
            size: 260,
            color: Color(0xFF5EEAD4),
            opacity: 0.28,
          ),
        ),
        const Positioned(
          top: 120,
          right: -100,
          child: _GlowOrb(
            size: 240,
            color: Color(0xFF38BDF8),
            opacity: 0.22,
          ),
        ),
        const Positioned(
          bottom: -130,
          left: 50,
          child: _GlowOrb(
            size: 280,
            color: Color(0xFF0EA5E9),
            opacity: 0.18,
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(opacity),
          ),
        ),
      ),
    );
  }
}

class ReflectivePanel extends StatelessWidget {
  const ReflectivePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.78),
                Colors.white.withOpacity(0.65),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.72),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.08),
                blurRadius: 34,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -60,
                left: -16,
                right: -16,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.7),
                        Colors.white.withOpacity(0.02),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: padding,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.child,
    required this.delay,
    this.beginOffset = const Offset(0, 0.08),
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;
  final Duration delay;
  final Offset beginOffset;
  final Duration duration;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : widget.beginOffset,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class CaptainDutyToggle extends StatefulWidget {
  final bool value;
  final bool loading;
  final ValueChanged<bool> onChanged;

  const CaptainDutyToggle({
    super.key,
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  @override
  State<CaptainDutyToggle> createState() => _CaptainDutyToggleState();
}

class _CaptainDutyToggleState extends State<CaptainDutyToggle> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _thumbScaleAnimation;
  bool _localValue = false;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _thumbScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.08).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_animController);
  }

  @override
  void didUpdateWidget(CaptainDutyToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      setState(() {
        _localValue = widget.value;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.loading) return;
    HapticFeedback.lightImpact();
    _animController.forward(from: 0.0);
    setState(() {
      _localValue = !_localValue;
    });
    widget.onChanged(_localValue);
  }

  @override
  Widget build(BuildContext context) {
    final bool isON = _localValue;
    
    return GestureDetector(
      onTap: _handleTap,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // soft green glow behind switch when ON
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            opacity: isON ? 0.35 : 0.0,
            child: Container(
              width: 144,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFF10B981),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          
          // Main track
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 140,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: isON
                  ? const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isON ? null : const Color(0xFF2A2A2A),
              border: Border.all(
                color: isON 
                    ? const Color(0xFF34D399).withOpacity(0.4) 
                    : const Color(0xFF4B5563).withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Text Label ("ON DUTY" / "OFF DUTY")
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: isON ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isON ? 16.0 : 0.0,
                      right: isON ? 0.0 : 16.0,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.95, end: 1.0).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        isON ? "ON DUTY" : "OFF DUTY",
                        key: ValueKey<bool>(isON),
                        style: TextStyle(
                          color: isON ? Colors.white : const Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Thumb
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: isON ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ScaleTransition(
                      scale: _thumbScaleAnimation,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: widget.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF059669),
                                  ),
                                )
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  child: isON
                                      ? const Icon(
                                          Icons.check_rounded,
                                          key: ValueKey("check"),
                                          color: Color(0xFF059669),
                                          size: 22,
                                        )
                                      : const Icon(
                                          Icons.power_settings_new_rounded,
                                          key: ValueKey("power"),
                                          color: Color(0xFF9CA3AF),
                                          size: 20,
                                        ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
