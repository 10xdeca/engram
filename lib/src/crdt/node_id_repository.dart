import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists a unique device node ID for CRDT operations.
///
/// Each device gets a stable UUID v4 that identifies it in the HLC
/// (Hybrid Logical Clock) system. The ID is generated on first access
/// and persisted in [SharedPreferences] so it survives app restarts.
///
/// Call [ensureInitialized] once at startup to guarantee persistence
/// before any synchronous [nodeId] reads.
class NodeIdRepository {
  NodeIdRepository(this._prefs);

  final SharedPreferences _prefs;

  static const prefsKey = 'crdt_node_id';

  String? _cached;

  /// Ensures the node ID is generated and persisted.
  ///
  /// Call this once during app startup (before any [nodeId] reads)
  /// to guarantee the ID survives a crash between generation and
  /// the next SharedPreferences flush.
  Future<void> ensureInitialized() async {
    if (_cached != null) return;

    var id = _prefs.getString(prefsKey);
    if (id == null) {
      id = const Uuid().v4();
      await _prefs.setString(prefsKey, id);
    }
    _cached = id;
  }

  /// Returns the device's stable node ID.
  ///
  /// Call [ensureInitialized] first. If called before initialization,
  /// this will still work (generates and caches synchronously) but
  /// persistence is fire-and-forget.
  String get nodeId {
    if (_cached != null) return _cached!;

    var id = _prefs.getString(prefsKey);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(prefsKey, id);
    }
    _cached = id;
    return id;
  }
}
