import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../models/engine_result.dart';
import '../services/audio_features.dart';

// ── Rejection reason surfaced to the UI ──────────────────────────────────────
enum RejectionReason {
  oodGate,         // OOD RF gate fired  → not an engine sound
  lowConfidence,   // Fault classifier confidence below threshold
}

/// Carries the per-window rejection detail so the UI can explain it.
class WindowRejection {
  final double startSec;
  final double endSec;
  final RejectionReason reason;

  /// OOD gate: probability that the window is out-of-distribution (0–1).
  /// Null when rejected by low confidence instead.
  final double? oodScore;

  /// OOD gate threshold that was applied.
  final double? oodThreshold;

  /// Fault classifier top-1 label (even when confidence was too low).
  final String? faultLabel;

  /// Fault classifier top-1 probability (even when below threshold).
  final double? faultConfidence;

  /// Fault classifier threshold that was applied.
  final double? faultThreshold;

  /// All fault probabilities, for debugging / detailed UI.
  final List<double>? allFaultProbs;

  const WindowRejection({
    required this.startSec,
    required this.endSec,
    required this.reason,
    this.oodScore,
    this.oodThreshold,
    this.faultLabel,
    this.faultConfidence,
    this.faultThreshold,
    this.allFaultProbs,
  });

  /// Human-readable summary — shown in the UI or logged.
  String get summary {
    switch (reason) {
      case RejectionReason.oodGate:
        final score = oodScore != null ? (oodScore! * 100).toStringAsFixed(1) : '?';
        final th    = oodThreshold != null ? (oodThreshold! * 100).toStringAsFixed(0) : '?';
        return 'OOD gate rejected '
            '(non-engine probability $score% ≥ threshold $th%) '
            '— audio does not sound like an engine. '
            'Record closer to the engine with less background noise.';

      case RejectionReason.lowConfidence:
        final conf = faultConfidence != null
            ? (faultConfidence! * 100).toStringAsFixed(1)
            : '?';
        final th = faultThreshold != null
            ? (faultThreshold! * 100).toStringAsFixed(0)
            : '?';
        return 'Fault classifier confidence too low '
            '(best guess: "$faultLabel" at $conf% < threshold $th%). '
            'Try a longer or cleaner recording.';
    }
  }
}

// ── Internal RF helpers (unchanged) ─────────────────────────────────────────

class _DecisionTree {
  final Int32List childrenLeft;
  final Int32List childrenRight;
  final Int32List feature;
  final Float64List threshold;
  final List<Float64List> value;

  _DecisionTree({
    required this.childrenLeft,
    required this.childrenRight,
    required this.feature,
    required this.threshold,
    required this.value,
  });

  static _DecisionTree fromJson(Map<String, dynamic> json) {
    final cl   = Int32List.fromList((json['children_left'] as List).cast<int>());
    final cr   = Int32List.fromList((json['children_right'] as List).cast<int>());
    final feat = Int32List.fromList((json['feature'] as List).cast<int>());
    final thr  = Float64List.fromList(
      (json['threshold'] as List).map((v) => (v as num).toDouble()).toList(),
    );
    final rawValue = json['value'] as List;
    final value = List<Float64List>.generate(rawValue.length, (i) {
      final inner = (rawValue[i] as List)[0] as List;
      return Float64List.fromList(
        inner.map((v) => (v as num).toDouble()).toList(),
      );
    });
    return _DecisionTree(
      childrenLeft: cl,
      childrenRight: cr,
      feature: feat,
      threshold: thr,
      value: value,
    );
  }

  int predictClass(Float64List x) {
    int node = 0;
    while (childrenLeft[node] != -1) {
      node = x[feature[node]] <= threshold[node]
          ? childrenLeft[node]
          : childrenRight[node];
    }
    final leaf = value[node];
    int bestIdx = 0;
    double bestVal = leaf[0];
    for (int i = 1; i < leaf.length; i++) {
      if (leaf[i] > bestVal) {
        bestVal = leaf[i];
        bestIdx = i;
      }
    }
    return bestIdx;
  }
}

class _RandomForestModel {
  final List<_DecisionTree> trees;
  final Float64List scalerMean;
  final Float64List scalerScale;
  final int nClasses;
  final List<String> classNames;

  _RandomForestModel({
    required this.trees,
    required this.scalerMean,
    required this.scalerScale,
    required this.nClasses,
    required this.classNames,
  });

  static _RandomForestModel fromJson(Map<String, dynamic> json) {
    final nClasses     = json['n_classes'] as int;
    final rawClassNames = json['class_names'] as List?;
    final classNames   = rawClassNames == null
        ? List<String>.generate(nClasses, (i) => '$i')
        : rawClassNames.map((v) => v.toString()).toList();
    final scaler = json['scaler'] as Map<String, dynamic>;
    final mean   = Float64List.fromList(
      (scaler['mean'] as List).map((v) => (v as num).toDouble()).toList(),
    );
    final scale  = Float64List.fromList(
      (scaler['scale'] as List).map((v) => (v as num).toDouble()).toList(),
    );
    final rawTrees = json['trees'] as List;
    final trees    = rawTrees
        .map((t) => _DecisionTree.fromJson(t as Map<String, dynamic>))
        .toList();
    return _RandomForestModel(
      trees: trees,
      scalerMean: mean,
      scalerScale: scale,
      nClasses: nClasses,
      classNames: classNames,
    );
  }

  List<double> predictProba(Float64List rawFeatures) {
    final scaled = Float64List(rawFeatures.length);
    for (int i = 0; i < rawFeatures.length; i++) {
      scaled[i] = (rawFeatures[i] - scalerMean[i]) / scalerScale[i];
    }
    final votes = List<double>.filled(nClasses, 0.0);
    for (final tree in trees) {
      votes[tree.predictClass(scaled)] += 1.0;
    }
    final n = trees.length.toDouble();
    for (int c = 0; c < nClasses; c++) {
      votes[c] /= n;
    }
    return votes;
  }
}

// ── Main service ─────────────────────────────────────────────────────────────

class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal();

  _RandomForestModel? _faultModel;
  _RandomForestModel? _oodModel;

  static const int _nFeatures       = 418;
  static const int _normalClassIndex = 5;

  /// DEBUG ONLY — when true, every analyzed window's raw 418-feature
  /// vector is written to a JSON file in the app's temp directory and its
  /// path printed to logcat, so it can be pulled (adb pull / file manager)
  /// and diffed feature-by-feature against the real Python
  /// extract_all_features() output for the SAME wav file. This is the only
  /// way to get a verified (not just "looks better") parity guarantee.
  /// SET TO false BEFORE SHIPPING / RELEASE BUILD.
  static bool debugDumpFeatures = true;

  double _confidenceThreshold = 0.60;   // loaded from config.json
  double _oodThreshold        = 0.50;   // loaded from ood_gate_config.json

  static const int    _sampleRate   = 22050;
  static const double _windowSec    = 5.0;
  static       int get _targetSamples => (_windowSec * _sampleRate).round();
  static const double _stepSec      = 2.5;

  bool get isModelLoaded => _faultModel != null && _oodModel != null;

  Future<void> loadModel() async {
    if (isModelLoaded) return;

    final faultJson     = await rootBundle.loadString('assets/random_forest_v1.json');
    final oodJson       = await rootBundle.loadString('assets/ood_gate_rf_v1.json');
    final configJson    = await rootBundle.loadString('assets/config.json');
    final oodConfigJson = await rootBundle.loadString('assets/ood_gate_config.json');

    final config    = jsonDecode(configJson)    as Map<String, dynamic>;
    final oodConfig = jsonDecode(oodConfigJson) as Map<String, dynamic>;
    final faultMap  = jsonDecode(faultJson)     as Map<String, dynamic>;
    final oodMap    = jsonDecode(oodJson)        as Map<String, dynamic>;

    _confidenceThreshold = (config['confidence_threshold'] as num).toDouble();
    _oodThreshold        = (oodConfig['ood_threshold']     as num).toDouble();

    print('>>> FAULT  model v${faultMap['model_version']}  '
          'features=${faultMap['n_features']}  '
          'classes=${faultMap['class_names']}');
    print('>>> OOD    model v${oodMap['model_version']}  '
          'features=${oodMap['n_features']}');
    print('>>> Thresholds — fault confidence: $_confidenceThreshold  '
          'OOD gate: $_oodThreshold');

    _faultModel = _RandomForestModel.fromJson(faultMap);
    _oodModel   = _RandomForestModel.fromJson(oodMap);
  }

  // ── Main entry point ───────────────────────────────────────────────────────

  Future<EngineResult> analyzeAudio(Float32List fullAudio) async {
    if (!isModelLoaded) throw Exception('Models not loaded');

    final int windowSamples = _targetSamples;
    final int stepSamples   = (_stepSec * _sampleRate).round();
    final int totalSamples  = fullAudio.length;

    final List<WindowResult>    windowResults   = [];
    final List<WindowRejection> windowRejections = [];  // ← NEW: track rejections

    final List<int> starts = [];
    if (totalSamples <= windowSamples) {
      starts.add(0);
    } else {
      int s = 0;
      while (s + windowSamples <= totalSamples) {
        starts.add(s);
        s += stepSamples;
      }
    }

    print('>>> WINDOWS: ${starts.length}  '
          'OOD threshold: $_oodThreshold  '
          'Fault threshold: $_confidenceThreshold');

    for (final start in starts) {
      final end        = (start + windowSamples).clamp(0, totalSamples);
      final rawWindow  = Float32List(windowSamples);
      rawWindow.setRange(0, end - start, fullAudio, start);

      final windowAudio = AudioFeatures.preprocess(rawWindow);
      final features    = AudioFeatures.extractFeatures(windowAudio);
      final featF64     = Float64List.fromList(features);

      // ── DEBUG: dump raw 418-feature vector for Python-vs-Dart parity
      // checking. Toggle off for release builds (see debugDumpFeatures).
      if (debugDumpFeatures) {
        await _dumpFeatureVector(featF64, start, end);
      }

      final double startSec = start / _sampleRate;
      final double endSec   = end   / _sampleRate;

      // ── Gate 1: OOD RF ────────────────────────────────────────────────────
      final oodProbs  = _oodModel!.predictProba(featF64);
      final oodScore  = oodProbs[1];   // P(out-of-distribution)

      print('>>> [${startSec.toStringAsFixed(1)}s–${endSec.toStringAsFixed(1)}s] '
            'OOD score: ${(oodScore * 100).toStringAsFixed(1)}%  '
            'threshold: ${(_oodThreshold * 100).toStringAsFixed(0)}%  '
            '${oodScore >= _oodThreshold ? "→ REJECTED by OOD gate" : "→ passes OOD"}');

      if (oodScore >= _oodThreshold) {
        windowRejections.add(WindowRejection(
          startSec:     startSec,
          endSec:       endSec,
          reason:       RejectionReason.oodGate,
          oodScore:     oodScore,
          oodThreshold: _oodThreshold,
        ));
        continue;
      }

      // ── Gate 2: Fault classifier confidence ───────────────────────────────
      final probs  = _faultModel!.predictProba(featF64);
      int    maxIdx = 0;
      double maxVal = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxVal) { maxVal = probs[i]; maxIdx = i; }
      }
      final label = _faultModel!.classNames[maxIdx];

      print('>>> [${startSec.toStringAsFixed(1)}s–${endSec.toStringAsFixed(1)}s] '
            'Fault: "$label" ${(maxVal * 100).toStringAsFixed(1)}%  '
            'threshold: ${(_confidenceThreshold * 100).toStringAsFixed(0)}%  '
            '${maxVal < _confidenceThreshold ? "→ REJECTED by confidence" : "→ ACCEPTED"}');

      if (maxVal < _confidenceThreshold) {
        windowRejections.add(WindowRejection(
          startSec:        startSec,
          endSec:          endSec,
          reason:          RejectionReason.lowConfidence,
          faultLabel:      label,
          faultConfidence: maxVal,
          faultThreshold:  _confidenceThreshold,
          allFaultProbs:   List<double>.from(probs),
        ));
        continue;
      }

      windowResults.add(WindowResult(
        startSec:   startSec,
        endSec:     endSec,
        label:      label,
        confidence: maxVal,
      ));
    }

    // ── Summary log ───────────────────────────────────────────────────────
    final oodRejected  = windowRejections.where((r) => r.reason == RejectionReason.oodGate).length;
    final confRejected = windowRejections.where((r) => r.reason == RejectionReason.lowConfidence).length;
    print('>>> ACCEPTED: ${windowResults.length}  '
          'OOD-rejected: $oodRejected  '
          'Confidence-rejected: $confRejected');

    if (windowRejections.isNotEmpty) {
      for (final r in windowRejections) {
        print('>>>   ${r.summary}');
      }
    }

    return _aggregate(
      windowResults,
      windowRejections,
      Duration(seconds: totalSamples ~/ _sampleRate),
    );
  }

  // ── Aggregation ───────────────────────────────────────────────────────────

  EngineResult _aggregate(
    List<WindowResult>    windows,
    List<WindowRejection> rejections,
    Duration              duration,
  ) {
    // ── Work out the dominant rejection reason to guide the UI message ────
    final oodCount  = rejections.where((r) => r.reason == RejectionReason.oodGate).length;
    final confCount = rejections.where((r) => r.reason == RejectionReason.lowConfidence).length;

    // Representative scores for the UI (worst-case / most informative window)
    double? worstOodScore;
    String? worstFaultLabel;
    double? worstFaultConf;
    RejectionReason? dominantReason;

    if (rejections.isNotEmpty) {
      // Pick dominant rejection reason
      dominantReason = oodCount >= confCount
          ? RejectionReason.oodGate
          : RejectionReason.lowConfidence;

      // Highest OOD score (most "non-engine-like" window)
      final oodRejs = rejections.where((r) => r.reason == RejectionReason.oodGate);
      if (oodRejs.isNotEmpty) {
        worstOodScore = oodRejs.map((r) => r.oodScore ?? 0.0).reduce((a, b) => a > b ? a : b);
      }

      // Lowest-confidence fault window (most uncertain)
      final confRejs = rejections.where((r) => r.reason == RejectionReason.lowConfidence);
      if (confRejs.isNotEmpty) {
        final worst = confRejs.reduce(
          (a, b) => (a.faultConfidence ?? 1.0) < (b.faultConfidence ?? 1.0) ? a : b,
        );
        worstFaultLabel = worst.faultLabel;
        worstFaultConf  = worst.faultConfidence;
      }
    }

    if (windows.isEmpty) {
      return EngineResult(
        status:           EngineStatus.unknown,
        faults:           const [],
        timestamp:        DateTime.now(),
        recordingDuration: duration,
        windows:          const [],
        detectedInPercent: 0,
        // ── NEW rejection fields ──────────────────────────────────────────
        rejections:        rejections,
        dominantRejection: dominantReason,
        oodScore:          worstOodScore,
        oodThreshold:      _oodThreshold,
        faultLabelAtRejection:      worstFaultLabel,
        faultConfidenceAtRejection: worstFaultConf,
        faultThreshold:    _confidenceThreshold,
        rejectionMessage:  _buildRejectionMessage(
          dominantReason, oodRejected: oodCount, confRejected: confCount,
          oodScore: worstOodScore, oodThreshold: _oodThreshold,
          faultLabel: worstFaultLabel, faultConf: worstFaultConf,
          faultThreshold: _confidenceThreshold,
        ),
      );
    }

    // ── Normal aggregation (unchanged logic) ──────────────────────────────
    final Map<String, List<double>> byLabel = {};
    for (final w in windows) {
      byLabel.putIfAbsent(w.label, () => []).add(w.confidence);
    }

    String? bestFaultLabel;
    double  bestFaultAvg = 0.0;
    String? normalLabel;
    double  normalAvg   = 0.0;
    final   normalName  = _faultModel!.classNames[_normalClassIndex];

    byLabel.forEach((label, confs) {
      final avg = confs.reduce((a, b) => a + b) / confs.length;
      if (label == normalName) {
        normalLabel = label;
        normalAvg   = avg;
      } else if (avg > bestFaultAvg) {
        bestFaultAvg   = avg;
        bestFaultLabel = label;
      }
    });

    final String finalLabel = bestFaultLabel ?? normalLabel ?? normalName;
    final double finalConf  = bestFaultLabel != null ? bestFaultAvg : normalAvg;
    final int    matchCount = windows.where((w) => w.label == finalLabel).length;
    final double pct        = (matchCount / windows.length) * 100.0;
    final bool   isNormal   = finalLabel == normalName;

    // Three-tier status: good (normal), warning (low-confidence fault),
    // faulty (high-confidence fault) — mirrors the >=0.8 cutoff already
    // used per-window in ResultScreen's _WindowTile color coding.
    final EngineStatus engineStatus = isNormal
        ? EngineStatus.good
        : (finalConf >= 0.8 ? EngineStatus.faulty : EngineStatus.warning);

    return EngineResult(
      status:           engineStatus,
      faults:           [FaultDetail(name: finalLabel, confidence: finalConf)],
      timestamp:        DateTime.now(),
      recordingDuration: duration,
      windows:          windows,
      detectedInPercent: pct,
      rejections:        rejections,
      dominantRejection: dominantReason,
      oodScore:          worstOodScore,
      oodThreshold:      _oodThreshold,
      faultLabelAtRejection:      worstFaultLabel,
      faultConfidenceAtRejection: worstFaultConf,
      faultThreshold:    _confidenceThreshold,
      rejectionMessage:  null,   // result was accepted; no rejection message needed
    );
  }

  // ── Human-readable rejection message for the UI ───────────────────────────

  String? _buildRejectionMessage(
    RejectionReason? reason, {
    required int    oodRejected,
    required int    confRejected,
    required double? oodScore,
    required double  oodThreshold,
    required String? faultLabel,
    required double? faultConf,
    required double  faultThreshold,
  }) {
    if (reason == null) return null;

    final total = oodRejected + confRejected;

    switch (reason) {
      case RejectionReason.oodGate:
        final score = oodScore != null
            ? '${(oodScore * 100).toStringAsFixed(0)}%'
            : 'high';
        return 'Recording rejected by OOD gate '
            '($oodRejected/$total windows, non-engine probability $score ≥ '
            '${(oodThreshold * 100).toStringAsFixed(0)}%).\n'
            'This does not sound like an engine. '
            'Record closer to the engine with the phone pointing at the engine block, '
            'and reduce background noise.';

      case RejectionReason.lowConfidence:
        final label = faultLabel ?? 'unknown';
        final conf  = faultConf != null
            ? '${(faultConf * 100).toStringAsFixed(0)}%'
            : 'low';
        return 'Recording passed OOD gate but fault classifier confidence was too low '
            '($confRejected/$total windows, best guess: "$label" at $conf < '
            '${(faultThreshold * 100).toStringAsFixed(0)}%).\n'
            'Try a longer, cleaner recording closer to the engine.';
    }
  }

  /// DEBUG: writes the raw 418-feature vector for one window to a JSON file
  /// in the app's temp directory, for offline diffing against the real
  /// Python extract_all_features() output on the same audio file.
  Future<void> _dumpFeatureVector(
      Float64List features, int startSample, int endSample) async {
    try {
      final dir = await getTemporaryDirectory();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/dart_features_${ts}_${startSample}_$endSample.json');
      final jsonStr = jsonEncode({
        'start_sample': startSample,
        'end_sample': endSample,
        'n_features': features.length,
        'features': features.toList(),
      });
      await file.writeAsString(jsonStr);
      print('>>> FEATURE DUMP WRITTEN: ${file.path}');
    } catch (e) {
      print('>>> FEATURE DUMP FAILED: $e');
    }
  }

  void dispose() {
    _faultModel = null;
    _oodModel   = null;
  }
}