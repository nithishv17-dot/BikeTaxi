import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four-layer obsidian slide-to-accept driver offer card with an oversized
/// protruding avatar thumb, expanding orange trail, and spring release physics.
class ObsidianSlideOfferCard extends StatefulWidget {
  final String driverName;
  final String formattedFare;
  final String rating;
  final String eta;
  final bool isDisabled;
  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  const ObsidianSlideOfferCard({
    super.key,
    required this.driverName,
    required this.formattedFare,
    required this.rating,
    required this.eta,
    required this.isDisabled,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<ObsidianSlideOfferCard> createState() => _ObsidianSlideOfferCardState();
}

class _ObsidianSlideOfferCardState extends State<ObsidianSlideOfferCard>
    with TickerProviderStateMixin {
  static const double _avatarSize = 88.0;
  static const Color _cardSurface = Color(0xFF141519);
  static const Color _thumbFill = Color(0xFF1B1D24);
  static const Color _warmAmber = Color(0xFFF4A261);
  static const Color _accentOrange = Color(0xFFFF7A00);
  static const Color _dismissBtnFill = Color(0xFF26221E);

  late final AnimationController _chevronController;
  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;

  double _dragX = 0.0;
  bool _isAccepted = false;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _chevronController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(" ").where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return "C";
    return parts.map((w) => w[0]).take(2).join().toUpperCase();
  }

  Future<void> _animateDragTo({
    required double target,
    required Duration duration,
    required Curve curve,
  }) async {
    _snapController.stop();
    _snapController.duration = duration;

    final tween = Tween<double>(begin: _dragX, end: target);
    final curved = CurvedAnimation(parent: _snapController, curve: curve);
    final nextAnim = tween.animate(curved);

    void listener() {
      if (!mounted) return;
      setState(() {
        _dragX = nextAnim.value;
      });
    }

    _snapAnimation?.removeListener(listener);
    _snapAnimation = nextAnim;
    nextAnim.addListener(listener);

    try {
      await _snapController.forward(from: 0.0);
    } finally {
      nextAnim.removeListener(listener);
    }
  }

  Future<void> _handleDragEnd(double maxDrag) async {
    if (widget.isDisabled || _isAccepted) return;

    if (_dragX >= 0.80 * maxDrag) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isAccepted = true;
      });
      await _animateDragTo(
        target: maxDrag,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      try {
        await widget.onAccept();
      } catch (_) {
        if (mounted) {
          setState(() {
            _isAccepted = false;
          });
          await _animateDragTo(
            target: 0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
          );
        }
      }
    } else {
      await _animateDragTo(
        target: 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
      );
      if (mounted) {
        setState(() {
          _dragX = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String initials = _initialsFor(widget.driverName);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double cardWidth = constraints.maxWidth;
          final double maxDrag = (cardWidth - _avatarSize).clamp(1.0, cardWidth);
          final double p = (_dragX / maxDrag).clamp(0.0, 1.0);
          final double metadataOpacity = math.max(0.15, 1.0 - (p * 1.4));
          final double trailWidth =
              (_dragX + (_avatarSize / 2.0)).clamp(0.0, cardWidth);

          return SizedBox(
            height: 76,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Layer 1 (Base Card): #141519 surface, 1px warm amber border,
                // 16px radius, right-aligned white fare, top-right 28x28 dismiss X.
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _warmAmber.withValues(alpha: 0.35),
                        width: 1.0,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: _isAccepted ? 14 : 40,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Text(
                              "₹ ${widget.formattedFare}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        if (!_isAccepted)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Material(
                                color: _dismissBtnFill,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap:
                                      widget.isDisabled ? null : widget.onDecline,
                                  child: const Center(
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: _warmAmber,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Layer 2 (Driver Metadata Row): animated orange >>> chevrons,
                // bold driver name, rating, ETA, "Slide right to accept",
                // dynamically faded with drag progress.
                Positioned(
                  left: _avatarSize + 10,
                  right: _isAccepted ? 96 : 122,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: metadataOpacity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.driverName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedBuilder(
                                animation: _chevronController,
                                builder: (context, _) {
                                  final t = _chevronController.value;
                                  return Transform.translate(
                                    offset: Offset((t * 6.0) - 3.0, 0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(3, (i) {
                                        final phase = (t - i * 0.22) % 1.0;
                                        final chevronAlpha = (0.35 +
                                                0.65 *
                                                    (1.0 -
                                                            (phase - 0.5).abs() *
                                                                2.0)
                                                        .clamp(0.0, 1.0))
                                            .clamp(0.30, 1.0);
                                        return Icon(
                                          Icons.chevron_right_rounded,
                                          size: 15,
                                          color: _warmAmber.withValues(
                                            alpha: chevronAlpha,
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: _warmAmber,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                widget.rating,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "•  ${widget.eta}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _dragX >= 0.80 * maxDrag
                                ? "Release to accept"
                                : "Slide avatar right to accept",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _warmAmber.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Layer 3 (Expanding Orange Trail): anchored at left: 0,
                // width dragX + 44, warm orange gradient.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: trailWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _accentOrange.withValues(alpha: 0.15),
                              _warmAmber.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Layer 4 (Draggable 88x88 Avatar Thumb): positioned at
                // left: dragX, top: -6, #1B1D24 fill, 2.0px #F4A261 border,
                // 26px bold #F4A261 initials, outer glow shadow.
                Positioned(
                  left: _dragX,
                  top: -6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (widget.isDisabled || _isAccepted)
                        ? null
                        : (_) {
                            _snapController.stop();
                          },
                    onHorizontalDragUpdate: (widget.isDisabled || _isAccepted)
                        ? null
                        : (details) {
                            setState(() {
                              _dragX =
                                  (_dragX + details.delta.dx).clamp(0.0, maxDrag);
                            });
                          },
                    onHorizontalDragEnd: (widget.isDisabled || _isAccepted)
                        ? null
                        : (_) => _handleDragEnd(maxDrag),
                    onHorizontalDragCancel: (widget.isDisabled || _isAccepted)
                        ? null
                        : () => _handleDragEnd(maxDrag),
                    child: Container(
                      width: _avatarSize,
                      height: _avatarSize,
                      decoration: BoxDecoration(
                        color: _thumbFill,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _warmAmber,
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accentOrange.withValues(alpha: 0.30),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: (_isAccepted && widget.isDisabled)
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  color: _warmAmber,
                                ),
                              )
                            : Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: _warmAmber,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

