import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/elevenlabs_client.dart';
import '../services/extraction_service.dart';
import '../services/narration_service.dart';
import '../services/outline_client.dart';
import '../services/recommendation_service.dart';
import 'settings_provider.dart';

final outlineClientProvider = Provider<OutlineClient>((ref) {
  final config = ref.watch(settingsProvider);
  return OutlineClient(
    apiUrl: config.outlineApiUrl,
    apiKey: config.outlineApiKey,
  );
});

final extractionServiceProvider = Provider<ExtractionService>((ref) {
  final config = ref.watch(settingsProvider);
  return ExtractionService(apiKey: config.anthropicApiKey);
});

final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  final config = ref.watch(settingsProvider);
  return RecommendationService(
    outlineClient: ref.watch(outlineClientProvider),
    apiKey: config.anthropicApiKey,
  );
});

final elevenLabsClientProvider = Provider<ElevenLabsClient>((ref) {
  final config = ref.watch(settingsProvider);
  return ElevenLabsClient(apiKey: config.elevenLabsApiKey);
});

final narrationServiceProvider = Provider<NarrationService>((ref) {
  final config = ref.watch(settingsProvider);
  return NarrationService(apiKey: config.anthropicApiKey);
});
