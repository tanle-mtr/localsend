import 'dart:math' show pi;

import 'package:flutter/material.dart';

class RotatingWidget extends StatefulWidget {
  final Duration duration;
  final bool spinning;
  final bool reverse;
  final Widget child;

  const RotatingWidget({
    required this.duration,
    this.spinning = true,
    this.reverse = false,
    required this.child,
    super.key,
  });

  @override
  State<RotatingWidget> createState() => RotatingWidgetState();
}

class RotatingWidgetState extends State<RotatingWidget> with SingleTickerProviderStateMixin {
  static const _maxRadians = 2 * pi;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _syncSpinning();
  }

  @override
  void didUpdateWidget(covariant RotatingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.spinning != widget.spinning) {
      _syncSpinning();
    }
  }

  void _syncSpinning() {
    if (widget.spinning) {
      _controller.repeat();
    } else {
      // Fully stop the ticker; the old loop kept waking up 30 times a second
      // even when nothing was spinning.
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        // Passed as `child` so the subtree is built once, not on every frame.
        child: widget.child,
        builder: (context, child) {
          final angle = (widget.reverse ? -1 : 1) * _controller.value * _maxRadians;
          return Transform.rotate(angle: angle, child: child);
        },
      ),
    );
  }
}
