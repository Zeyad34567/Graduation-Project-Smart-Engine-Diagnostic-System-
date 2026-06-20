import 'package:engine_fault_ai/services/inference_service.dart';

enum EngineStatus { good, warning, faulty, unknown }

class FaultDetail {
  final String name;
  final double confidence;
  const FaultDetail({required this.name, required this.confidence});
}

class WindowResult {
  final double startSec;
  final double endSec;
  final String label;
  final double confidence;
  const WindowResult({
    required this.startSec,
    required this.endSec,
    required this.label,
    required this.confidence,
  });
}

class EngineResult {
  final EngineStatus      status;
  final List<FaultDetail> faults;
  final DateTime          timestamp;
  final Duration          recordingDuration;
  final List<WindowResult> windows;
  final double            detectedInPercent;

  // ── Rejection diagnostics (populated even on accepted results) ─────────────

  /// Every window that was dropped, with full reason + scores.
  final List<WindowRejection> rejections;

  /// Which rejection reason dominated (null if no windows were rejected).
  final RejectionReason? dominantRejection;

  /// Highest OOD probability seen across all rejected-by-OOD windows.
  /// e.g. 0.87 → "87% non-engine probability"
  final double? oodScore;

  /// The OOD threshold that was applied.
  final double? oodThreshold;

  /// Label the fault classifier would have chosen on the worst low-confidence window.
  final String? faultLabelAtRejection;

  /// Confidence the fault classifier gave that label.
  final double? faultConfidenceAtRejection;

  /// The fault confidence threshold that was applied.
  final double? faultThreshold;

  /// Ready-to-display rejection explanation for the UI.
  /// Null when the result was accepted (status != unknown).
  final String? rejectionMessage;

  const EngineResult({
    required this.status,
    required this.faults,
    required this.timestamp,
    required this.recordingDuration,
    required this.windows,
    required this.detectedInPercent,
    this.rejections          = const [],
    this.dominantRejection,
    this.oodScore,
    this.oodThreshold,
    this.faultLabelAtRejection,
    this.faultConfidenceAtRejection,
    this.faultThreshold,
    this.rejectionMessage,
  });

  // ── Convenience getters for the UI ────────────────────────────────────────

  bool get wasRejected => status == EngineStatus.unknown;

  bool get rejectedByOod =>
      dominantRejection == RejectionReason.oodGate;

  bool get rejectedByLowConfidence =>
      dominantRejection == RejectionReason.lowConfidence;

  /// Short badge/status-line text, e.g. "Healthy", "Warning", "Fault Detected".
  String get statusLabel {
    switch (status) {
      case EngineStatus.good:
        return 'Healthy';
      case EngineStatus.warning:
        return 'Warning';
      case EngineStatus.faulty:
        return 'Fault Detected';
      case EngineStatus.unknown:
        return 'Unknown';
    }
  }

  /// The headline fault/engine-state name for the result screen, e.g.
  /// "Normal Healthy Engine", "Chain Noise", or "Unknown" if rejected.
  String get primaryFaultName {
    if (faults.isNotEmpty) return faults.first.name;
    return wasRejected ? 'Unknown' : 'No Data';
  }

  /// Confidence (0–1) associated with [primaryFaultName]. 0 if none available.
  double get primaryConfidence {
    if (faults.isNotEmpty) return faults.first.confidence;
    return 0.0;
  }

  /// e.g. "OOD gate (87% non-engine)" or "Low confidence (42% — Chain Noise)"
  String get rejectionLabel {
    if (!wasRejected) return '';
    switch (dominantRejection) {
      case RejectionReason.oodGate:
        final pct = oodScore != null
            ? ' (${(oodScore! * 100).toStringAsFixed(0)}% non-engine)'
            : '';
        return 'OOD gate$pct';
      case RejectionReason.lowConfidence:
        final pct   = faultConfidenceAtRejection != null
            ? ' (${(faultConfidenceAtRejection! * 100).toStringAsFixed(0)}%'
            : '';
        final label = faultLabelAtRejection != null
            ? ' — ${faultLabelAtRejection!}'
            : '';
        return 'Low confidence$pct$label)';
      case null:
        return 'Unknown';
    }
  }
}