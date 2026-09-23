import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/astra_theme.dart';

/// A production-grade frosted glass container with physics blur, cosmic gradient borders, and rounded corners.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double blurSigma;
  final VoidCallback? onTap;
  final BoxBorder? customBorder;
  final List<BoxShadow>? shadows;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(20.0),
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 18.0,
    this.onTap,
    this.customBorder,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBackground = backgroundColor ?? AstraTheme.glassFill;
    final effectiveBorderColor = borderColor ?? AstraTheme.borderSubtle;

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AstraTheme.primary.withValues(alpha: 0.06),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: effectiveBackground,
              borderRadius: BorderRadius.circular(borderRadius),
              border: customBorder ??
                  Border.all(
                    color: effectiveBorderColor,
                    width: 1.2,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}
