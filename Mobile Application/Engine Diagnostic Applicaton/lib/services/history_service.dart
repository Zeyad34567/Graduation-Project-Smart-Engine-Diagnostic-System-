import '../models/engine_result.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._();
  factory HistoryService() => _instance;
  HistoryService._();

  final List<EngineResult> _history = [];

  List<EngineResult> get all => List.unmodifiable(_history.reversed.toList());

  void add(EngineResult result) => _history.add(result);

  void clear() => _history.clear();
}
