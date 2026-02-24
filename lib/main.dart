import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/providers/graph_store_provider.dart';
import 'src/providers/settings_provider.dart';
import 'src/services/notification_service.dart';
import 'src/storage/drift/engram_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final appDir = await getApplicationDocumentsDirectory();
  final dataDir = '${appDir.path}/engram';

  // Always initialize Firebase — auth + Firestore are core dependencies now
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  assert(() {
    final opts = DefaultFirebaseOptions.currentPlatform;
    if (opts.apiKey.contains('YOUR') || opts.apiKey.isEmpty) {
      throw StateError(
        'Firebase not configured. Run `flutterfire configure` first.',
      );
    }
    return true;
  }());

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Open the local Drift/SQLite database (used for unauthenticated/offline
  // graph storage, replacing the old JSON file approach).
  final db = EngramDatabase();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dataDirProvider.overrideWithValue(dataDir),
        engramDatabaseProvider.overrideWithValue(db),
      ],
      child: const EngramApp(),
    ),
  );
}
