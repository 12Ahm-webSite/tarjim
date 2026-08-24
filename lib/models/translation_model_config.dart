/// Configuration metadata for an on-device translation model.
class TranslationModelConfig {
  const TranslationModelConfig({
    required this.code,
    required this.name,
    required this.nativeName,
    this.isRequired = true,
  });

  /// BCP-47 language tag (e.g. 'ja', 'en', 'ar').
  final String code;

  /// English human-readable language name.
  final String name;

  /// Native language script name.
  final String nativeName;

  /// Whether this model is required for the default manga translation pipeline.
  final bool isRequired;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationModelConfig &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$name ($code)';
}
