class EngramConfig {
  const EngramConfig({
    this.outlineApiUrl = '',
    this.outlineApiKey = '',
    this.anthropicApiKey = '',
  });

  final String outlineApiUrl;
  final String outlineApiKey;
  final String anthropicApiKey;

  bool get isOutlineConfigured =>
      outlineApiUrl.isNotEmpty && outlineApiKey.isNotEmpty;

  bool get isAnthropicConfigured => anthropicApiKey.isNotEmpty;

  bool get isFullyConfigured => isOutlineConfigured && isAnthropicConfigured;

  EngramConfig copyWith({
    String? outlineApiUrl,
    String? outlineApiKey,
    String? anthropicApiKey,
  }) {
    return EngramConfig(
      outlineApiUrl: outlineApiUrl ?? this.outlineApiUrl,
      outlineApiKey: outlineApiKey ?? this.outlineApiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
    );
  }
}

class ConfigError implements Exception {
  ConfigError(this.message);

  final String message;

  @override
  String toString() => 'ConfigError: $message';
}
