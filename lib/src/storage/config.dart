class EngramConfig {
  const EngramConfig({
    this.outlineApiUrl = '',
    this.outlineApiKey = '',
    this.anthropicApiKey = '',
    this.elevenLabsApiKey = '',
  });

  final String outlineApiUrl;
  final String outlineApiKey;
  final String anthropicApiKey;
  final String elevenLabsApiKey;

  bool get isOutlineConfigured =>
      outlineApiUrl.isNotEmpty && outlineApiKey.isNotEmpty;

  bool get isAnthropicConfigured => anthropicApiKey.isNotEmpty;

  bool get isElevenLabsConfigured => elevenLabsApiKey.isNotEmpty;

  bool get isFullyConfigured => isOutlineConfigured && isAnthropicConfigured;

  EngramConfig copyWith({
    String? outlineApiUrl,
    String? outlineApiKey,
    String? anthropicApiKey,
    String? elevenLabsApiKey,
  }) {
    return EngramConfig(
      outlineApiUrl: outlineApiUrl ?? this.outlineApiUrl,
      outlineApiKey: outlineApiKey ?? this.outlineApiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      elevenLabsApiKey: elevenLabsApiKey ?? this.elevenLabsApiKey,
    );
  }
}

class ConfigError implements Exception {
  ConfigError(this.message);

  final String message;

  @override
  String toString() => 'ConfigError: $message';
}
