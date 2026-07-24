// lib/models/category_model.dart

class CategoryModel {
  final String id;
  final String name;
  final int colorValue;

  CategoryModel({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'colorValue': colorValue,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unnamed',
      colorValue: map['colorValue'] ?? 0xFF9E9E9E, // Defaults to grey
    );
  }
}