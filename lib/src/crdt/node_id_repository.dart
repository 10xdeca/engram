import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists a unique device node ID for CRDT operations.
///
/// Each device gets a stable UUID v4 that identifies it in the HLC
/// (Hybrid Logical Clock) system. The ID is generated on first access
/// and persisted in [SharedPreferences] so it survives app restarts.
class NodeIdRepository {
  NodeIdRepository(this._prefs);

  final SharedPreferences _prefs;

  static const prefsKey = 'crdt_node_id';

  String? _cached;

  /// Returns the device's stable node ID, generating one if needed.
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
