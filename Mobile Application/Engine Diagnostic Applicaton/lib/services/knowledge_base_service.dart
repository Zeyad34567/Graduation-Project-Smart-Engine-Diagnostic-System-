import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/fault_knowledge.dart';

/// Loads assets/engine_knowledge_base.json once and caches it in memory.
/// Lookup is by exact fault name (must match the RF model's class_names).
class KnowledgeBaseService {
  KnowledgeBaseService._();
  static final KnowledgeBaseService instance = KnowledgeBaseService._();

  Map<String, FaultKnowledge>? _cache;
  Future<Map<String, FaultKnowledge>>? _loading;

  Future<Map<String, FaultKnowledge>> _load() {
    if (_cache != null) return Future.value(_cache!);
    return _loading ??= () async {
      final raw =
          await rootBundle.loadString('assets/engine_knowledge_base.json');
      final Map<String, dynamic> jsonMap =
          jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, FaultKnowledge>{};
      jsonMap.forEach((key, value) {
        map[key] = FaultKnowledge.fromJson(value as Map<String, dynamic>);
      });
      _cache = map;
      return map;
    }();
  }

  /// Returns the knowledge entry for [faultName], or null if not found
  /// (e.g. the class name doesn't exist in the knowledge base file).
  Future<FaultKnowledge?> get(String faultName) async {
    final map = await _load();
    return map[faultName];
  }
}
