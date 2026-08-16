// lib/models/space_model.dart

/// A collaborative 'Space' (group). Users create or join spaces via a 6-digit
/// uppercase alphanumeric room code; membership is tracked by UID so individual
/// tasks stay private unless shared inside a group.
class SpaceModel {
  final String id;
  final String name;
  final String roomCode; // 6-character uppercase alphanumeric string
  final String createdBy; // UID of the creator
  final List<String> members; // List of member UIDs
  final DateTime createdAt;

  const SpaceModel({
    required this.id,
    required this.name,
    required this.roomCode,
    required this.createdBy,
    required this.members,
    required this.createdAt,
  });

  SpaceModel copyWith({
    String? id,
    String? name,
    String? roomCode,
    String? createdBy,
    List<String>? members,
    DateTime? createdAt,
  }) {
    return SpaceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      roomCode: roomCode ?? this.roomCode,
      createdBy: createdBy ?? this.createdBy,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'roomCode': roomCode,
      'createdBy': createdBy,
      'members': members,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// [id] comes from the Firestore document path (never stored in the doc
  /// body), but is still honored from the map when present for parity with the
  /// other serialized models.
  factory SpaceModel.fromMap(Map<String, dynamic> map, {String? id}) {
    return SpaceModel(
      id: id ?? (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      roomCode: (map['roomCode'] as String?) ?? '',
      createdBy: (map['createdBy'] as String?) ?? '',
      members: (map['members'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      createdAt: _parseDate(map['createdAt']),
    );
  }

  /// Stores `createdAt` as an ISO-8601 string (consistent with PlannerModel)
  /// so documents round-trip safely through the offline cache without needing
  /// Firestore `Timestamp` conversion.
  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }
}
