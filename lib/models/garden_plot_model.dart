// lib/models/garden_plot_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class GardenPlotModel {
  final String id;
  final int gridIndex;
  final String seedType;
  final DateTime plantedAt;

  const GardenPlotModel({
    required this.id,
    required this.gridIndex,
    required this.seedType,
    required this.plantedAt,
  });

  GardenPlotModel copyWith({
    String? id,
    int? gridIndex,
    String? seedType,
    DateTime? plantedAt,
  }) {
    return GardenPlotModel(
      id: id ?? this.id,
      gridIndex: gridIndex ?? this.gridIndex,
      seedType: seedType ?? this.seedType,
      plantedAt: plantedAt ?? this.plantedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'gridIndex': gridIndex,
        'seedType': seedType,
        'plantedAt': Timestamp.fromDate(plantedAt),
      };

  factory GardenPlotModel.fromMap(Map<String, dynamic> map) => GardenPlotModel(
        id: map['id'] as String,
        gridIndex: (map['gridIndex'] as num).toInt(),
        seedType: map['seedType'] as String,
        plantedAt: _parseTimestamp(map['plantedAt']),
      );

  static DateTime _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
