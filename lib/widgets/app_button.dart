import 'package:flutter/material.dart';

/// Visual style variants for [AppButton].
enum AppButtonVariant { primary, tonal, danger, ghost }

/// Consistent full-width action button used across Tarjim.
///
/// - primary: main call to action (teal fill)
/// - tonal: secondary emphasis
/// - danger: destructive/stop actions (error color outline)
/// - ghost: low-emphasis navigation actions
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );
  static const _minSize = Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const textStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: 16);

    return switch (variant) {
      AppButtonVariant.primary => FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      AppButtonVariant.tonal => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(minimumSize: _minSize, shape: _shape),
        ),
      AppButtonVariant.danger => OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            minimumSize: _minSize,
            shape: _shape,
            textStyle: textStyle,
            foregroundColor: scheme.error,
            side: BorderSide(
              color: onPressed == null
                  ? scheme.outlineVariant
                  : scheme.error.withValues(alpha: 0.6),
            ),
          ),
        ),
      AppButtonVariant.ghost => OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            minimumSize: _minSize,
            shape: _shape,
            textStyle: textStyle,
          ),
        ),
    };
  }
}
