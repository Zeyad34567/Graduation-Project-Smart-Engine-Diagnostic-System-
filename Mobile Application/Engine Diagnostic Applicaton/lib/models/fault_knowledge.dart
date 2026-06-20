/// Parsed entry from assets/engine_knowledge_base.json, keyed by fault name
/// (must match the RF model's class_names exactly, e.g. "Rod Knock",
/// "Normal Healthy Engine").
class FaultKnowledge {
  final String faultName;
  final String description;
  final String severity; // "Safe" | "Low" | "Moderate" | "High" | "Critical" (free text from JSON)
  final int priority;
  final bool safeToDrive;
  final String drivingInstruction;
  final List<String> possibleCauses;
  final List<String> recommendedActions;
  final List<String> risksIfIgnored;
  final num repairCostMin;
  final num repairCostMax;
  final String repairNotes;
  final int? urgencyHours; // null = no urgency window (e.g. normal/healthy)
  final String mechanicDescription;
  final List<String> rootCausesDetailed;
  final String whenItAppears;
  final String soundAnalysis;
  final List<String> repairSteps;
  final List<String> requiredTools;

  const FaultKnowledge({
    required this.faultName,
    required this.description,
    required this.severity,
    required this.priority,
    required this.safeToDrive,
    required this.drivingInstruction,
    required this.possibleCauses,
    required this.recommendedActions,
    required this.risksIfIgnored,
    required this.repairCostMin,
    required this.repairCostMax,
    required this.repairNotes,
    required this.urgencyHours,
    required this.mechanicDescription,
    required this.rootCausesDetailed,
    required this.whenItAppears,
    required this.soundAnalysis,
    required this.repairSteps,
    required this.requiredTools,
  });

  static List<String> _strList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory FaultKnowledge.fromJson(Map<String, dynamic> json) {
    return FaultKnowledge(
      faultName: json['fault_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      severity: json['severity'] as String? ?? 'Unknown',
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      safeToDrive: json['safe_to_drive'] as bool? ?? true,
      drivingInstruction: json['driving_instruction'] as String? ?? '',
      possibleCauses: _strList(json['possible_causes']),
      recommendedActions: _strList(json['recommended_actions']),
      risksIfIgnored: _strList(json['risks_if_ignored']),
      repairCostMin: (json['repair_cost_min'] as num?) ?? 0,
      repairCostMax: (json['repair_cost_max'] as num?) ?? 0,
      repairNotes: json['repair_notes'] as String? ?? '',
      urgencyHours: (json['urgency_hours'] as num?)?.toInt(),
      mechanicDescription: json['mechanic_description'] as String? ?? '',
      rootCausesDetailed: _strList(json['root_causes_detailed']),
      whenItAppears: json['when_it_appears'] as String? ?? '',
      soundAnalysis: json['sound_analysis'] as String? ?? '',
      repairSteps: _strList(json['repair_steps']),
      requiredTools: _strList(json['required_tools']),
    );
  }
}
