/// Tracks per-category watch queue state on the device.
class CategoryState {
  List<String> unwatchedQueue;
  List<String> watched;
  int cycle;
  int knownTotal;

  CategoryState({
    required this.unwatchedQueue,
    required this.watched,
    this.cycle = 1,
    this.knownTotal = 0,
  });

  factory CategoryState.fromJson(Map<String, dynamic> json) {
    return CategoryState(
      unwatchedQueue: (json['unwatched_queue'] as List).cast<String>(),
      watched: (json['watched'] as List).cast<String>(),
      cycle: json['cycle'] as int? ?? 1,
      knownTotal: json['known_total'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'unwatched_queue': unwatchedQueue,
        'watched': watched,
        'cycle': cycle,
        'known_total': knownTotal,
      };

  /// Creates a fresh empty state.
  factory CategoryState.empty() => CategoryState(
        unwatchedQueue: [],
        watched: [],
        cycle: 1,
        knownTotal: 0,
      );
}

/// Complete local state for the device, covering both modes.
class LocalState {
  /// mode -> category -> CategoryState
  final Map<String, Map<String, CategoryState>> modeStates;

  LocalState({required this.modeStates});

  /// Get state for a specific mode and category, creating if absent.
  CategoryState getState(String mode, String category) {
    modeStates.putIfAbsent(mode, () => {});
    modeStates[mode]!.putIfAbsent(category, () => CategoryState.empty());
    return modeStates[mode]![category]!;
  }

  factory LocalState.empty() => LocalState(modeStates: {});

  factory LocalState.fromJson(Map<String, dynamic> json) {
    final states = <String, Map<String, CategoryState>>{};
    for (final mode in ['period', 'pregnancy']) {
      if (json.containsKey(mode)) {
        final modeMap = json[mode] as Map<String, dynamic>;
        states[mode] = {};
        for (final cat in modeMap.keys) {
          states[mode]![cat] =
              CategoryState.fromJson(modeMap[cat] as Map<String, dynamic>);
        }
      }
    }
    return LocalState(modeStates: states);
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    for (final mode in modeStates.keys) {
      result[mode] = modeStates[mode]!
          .map((cat, state) => MapEntry(cat, state.toJson()));
    }
    return result;
  }
}
