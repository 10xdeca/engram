/// Controls how many quiz items are included in a session.
enum SessionMode {
  /// Quick refresher — 5 items max (~5 minutes).
  quick(5),

  /// Full session — default cap of 20 items.
  full(20),

  /// All due items — no artificial cap.
  allDue(null);

  const SessionMode(this.maxItems);

  /// Maximum number of items, or `null` for unlimited.
  final int? maxItems;
}
