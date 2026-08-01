// lib/models/star_model.dart

class StarModel {
  final String id;
  final String category;
  final double dx;
  final double dy;

  const StarModel({
    required this.id,
    required this.category,
    required this.dx,
    required this.dy,
  });

  StarModel copyWith({
    String? id,
    String? category,
    double? dx,
    double? dy,
  }) {
    return StarModel(
      id: id ?? this.id,
      category: category ?? this.category,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'dx': dx,
        'dy': dy,
      };

  factory StarModel.fromMap(Map<String, dynamic> map) => StarModel(
        id: map['id'] as String,
        category: map['category'] as String,
        dx: (map['dx'] as num).toDouble(),
        dy: (map['dy'] as num).toDouble(),
      );
}
