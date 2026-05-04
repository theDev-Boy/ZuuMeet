import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class FloatingLikesWidget extends StatefulWidget {
  final Stream<void> triggerStream;
  const FloatingLikesWidget({super.key, required this.triggerStream});

  @override
  State<FloatingLikesWidget> createState() => _FloatingLikesWidgetState();
}

class _FloatingLikesWidgetState extends State<FloatingLikesWidget> with TickerProviderStateMixin {
  final List<_HeartData> _hearts = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    widget.triggerStream.listen((_) => _addHeart());
  }

  void _addHeart() {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    final data = _HeartData(
      controller: controller,
      pathIndex: _random.nextInt(3),
      color: [Colors.pink, Colors.red, Colors.orange, AppColors.primary][_random.nextInt(4)],
      size: 20 + _random.nextDouble() * 20,
    );

    setState(() {
      _hearts.add(data);
    });

    controller.forward().then((_) {
      setState(() {
        _hearts.remove(data);
        controller.dispose();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _hearts.map((heart) {
        return AnimatedBuilder(
          animation: heart.controller,
          builder: (context, child) {
            final double progress = heart.controller.value;
            final double curveValue = sin(progress * pi * 2);
            
            // Calculate movement
            final double bottom = 50 + (progress * 300);
            final double right = 20 + (curveValue * 30 * (heart.pathIndex + 1));
            final double opacity = 1.0 - progress;

            return Positioned(
              bottom: bottom,
              right: right,
              child: Opacity(
                opacity: opacity,
                child: Icon(
                  Icons.favorite_rounded,
                  color: heart.color,
                  size: heart.size,
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

class _HeartData {
  final AnimationController controller;
  final int pathIndex;
  final Color color;
  final double size;

  _HeartData({
    required this.controller,
    required this.pathIndex,
    required this.color,
    required this.size,
  });
}
