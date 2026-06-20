import 'package:flutter/material.dart';
import '../models/engine_result.dart';
import '../models/fault_knowledge.dart';
import '../services/knowledge_base_service.dart';
import '../theme/app_theme.dart';

class ResultScreen extends StatelessWidget {
  final EngineResult result;

  const ResultScreen({super.key, required this.result});

  Color get _statusColor {
    switch (result.status) {
      case EngineStatus.good:
        return AppColors.good;
      case EngineStatus.warning:
        return AppColors.warning;
      case EngineStatus.faulty:
        return AppColors.faulty;
      case EngineStatus.unknown:
        return AppColors.textMuted;
    }
  }

  IconData get _statusIcon {
    switch (result.status) {
      case EngineStatus.good:
        return Icons.check_circle_rounded;
      case EngineStatus.warning:
        return Icons.warning_rounded;
      case EngineStatus.faulty:
        return Icons.error_rounded;
      case EngineStatus.unknown:
        return Icons.help_rounded;
    }
  }

  String get _statusMessage {
    switch (result.status) {
      case EngineStatus.good:
        return 'Your engine sounds healthy. No faults detected.';
      case EngineStatus.warning:
        return 'Minor anomalies detected. Monitor engine closely.';
      case EngineStatus.faulty:
        return 'Fault detected. Service your engine as soon as possible.';
      case EngineStatus.unknown:
        return 'Unknown Audio. Please record closer to the engine.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Diagnosis Result',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero status card ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: _statusColor.withOpacity(0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  Icon(_statusIcon, color: _statusColor, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    result.primaryFaultName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (result.primaryConfidence > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Confidence: ${(result.primaryConfidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (result.detectedInPercent > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Detected in ${result.detectedInPercent.toStringAsFixed(0)}% of analyzed windows',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Knowledge base (description, causes, actions, costs…) ─
            if (!result.wasRejected)
              FutureBuilder<FaultKnowledge?>(
                future: KnowledgeBaseService.instance
                    .get(result.primaryFaultName),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.amber, strokeWidth: 2),
                      ),
                    );
                  }
                  final kb = snapshot.data;
                  if (kb == null) return const SizedBox.shrink();
                  return _KnowledgeSection(kb: kb);
                },
              ),

            const SizedBox(height: 24),

            // ── Recording info ────────────────────────────────────
            const _SectionTitle(title: 'Recording Info'),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.access_time_rounded,
              label: 'Duration',
              value: '${result.recordingDuration.inSeconds}s',
            ),
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: _formatDate(result.timestamp),
            ),

            // ── Per-window breakdown ──────────────────────────────
            if (result.windows.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionTitle(title: 'Window Analysis'),
              const SizedBox(height: 12),
              ...result.windows.asMap().entries.map((e) {
                final i = e.key + 1;
                final w = e.value;
                return _WindowTile(index: i, window: w);
              }),
            ],

            const SizedBox(height: 24),

            // ── CTA ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Upload New Audio',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Helpers ────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.amber, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _WindowTile extends StatelessWidget {
  final int index;
  final WindowResult window;

  const _WindowTile({required this.index, required this.window});

  Color get _color {
    if (window.label == 'Normal Healthy Engine') return AppColors.good;
    if (window.confidence >= 0.8) return AppColors.faulty;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final start = window.startSec.toStringAsFixed(1);
    final end = window.endSec.toStringAsFixed(1);
    final conf = (window.confidence * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          // Time badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.darkCardAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${start}s–${end}s',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(window.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          Text('$conf%',
              style: TextStyle(
                  color: _color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Knowledge base panel ──────────────────────────────────────────

class _KnowledgeSection extends StatelessWidget {
  final FaultKnowledge kb;
  const _KnowledgeSection({required this.kb});

  Color get _severityColor {
    switch (kb.severity.toLowerCase()) {
      case 'safe':
        return AppColors.good;
      case 'low':
        return AppColors.good;
      case 'moderate':
        return AppColors.warning;
      case 'high':
        return AppColors.warning;
      case 'critical':
        return AppColors.faulty;
      default:
        return AppColors.textMuted;
    }
  }

  String get _costRange {
    if (kb.repairCostMax <= 0) return 'No repair cost';
    final min = kb.repairCostMin.toStringAsFixed(0);
    final max = kb.repairCostMax.toStringAsFixed(0);
    return '\$$min – \$$max';
  }

  @override
  Widget build(BuildContext context) {
    final hasDetails = kb.mechanicDescription.isNotEmpty ||
        kb.rootCausesDetailed.isNotEmpty ||
        kb.repairSteps.isNotEmpty ||
        kb.requiredTools.isNotEmpty ||
        kb.soundAnalysis.isNotEmpty ||
        kb.whenItAppears.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Knowledge Base'),
        const SizedBox(height: 12),

        // Safe-to-drive banner + driving instruction
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (kb.safeToDrive ? AppColors.good : AppColors.faulty)
                .withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: (kb.safeToDrive ? AppColors.good : AppColors.faulty)
                    .withOpacity(0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                kb.safeToDrive
                    ? Icons.check_circle_outline_rounded
                    : Icons.dangerous_rounded,
                color: kb.safeToDrive ? AppColors.good : AppColors.faulty,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kb.safeToDrive ? 'Safe to drive' : 'Not safe to drive',
                      style: TextStyle(
                          color:
                              kb.safeToDrive ? AppColors.good : AppColors.faulty,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                    if (kb.drivingInstruction.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(kb.drivingInstruction,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        if (kb.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(kb.description,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        ],

        // Severity + urgency chips
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
                label: 'Severity: ${kb.severity}',
                color: _severityColor,
                icon: Icons.speed_rounded),
            if (kb.urgencyHours != null)
              _Chip(
                  label: kb.urgencyHours == 0
                      ? 'Act immediately'
                      : 'Address within ${kb.urgencyHours}h',
                  color: AppColors.faulty,
                  icon: Icons.timer_rounded),
            if (kb.repairCostMax > 0)
              _Chip(
                  label: _costRange,
                  color: AppColors.amber,
                  icon: Icons.attach_money_rounded),
          ],
        ),

        if (kb.possibleCauses.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SubHeading(title: 'Possible Causes'),
          const SizedBox(height: 8),
          ...kb.possibleCauses.map((c) => _BulletLine(text: c)),
        ],

        if (kb.recommendedActions.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SubHeading(title: 'Recommended Actions'),
          const SizedBox(height: 8),
          ...kb.recommendedActions.map((a) => _BulletLine(
              text: a, icon: Icons.check_rounded, color: AppColors.good)),
        ],

        if (kb.risksIfIgnored.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SubHeading(title: 'Risks If Ignored'),
          const SizedBox(height: 8),
          ...kb.risksIfIgnored.map((r) => _BulletLine(
              text: r,
              icon: Icons.warning_amber_rounded,
              color: AppColors.faulty)),
        ],

        if (kb.repairNotes.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SubHeading(title: 'Repair Notes'),
          const SizedBox(height: 8),
          Text(kb.repairNotes,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ],

        if (hasDetails) ...[
          const SizedBox(height: 18),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              collapsedIconColor: AppColors.amber,
              iconColor: AppColors.amber,
              title: const Text('More technical detail',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              children: [
                if (kb.mechanicDescription.isNotEmpty) ...[
                  const _SubHeading(title: "Mechanic's Take"),
                  const SizedBox(height: 8),
                  Text(kb.mechanicDescription,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5)),
                  const SizedBox(height: 14),
                ],
                if (kb.soundAnalysis.isNotEmpty) ...[
                  const _SubHeading(title: 'Sound Analysis'),
                  const SizedBox(height: 8),
                  Text(kb.soundAnalysis,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5)),
                  const SizedBox(height: 14),
                ],
                if (kb.whenItAppears.isNotEmpty) ...[
                  const _SubHeading(title: 'When It Appears'),
                  const SizedBox(height: 8),
                  Text(kb.whenItAppears,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5)),
                  const SizedBox(height: 14),
                ],
                if (kb.rootCausesDetailed.isNotEmpty) ...[
                  const _SubHeading(title: 'Root Causes (Detailed)'),
                  const SizedBox(height: 8),
                  ...kb.rootCausesDetailed.map((c) => _BulletLine(text: c)),
                  const SizedBox(height: 14),
                ],
                if (kb.repairSteps.isNotEmpty) ...[
                  const _SubHeading(title: 'Repair Steps'),
                  const SizedBox(height: 8),
                  ...kb.repairSteps.asMap().entries.map(
                        (e) => _BulletLine(
                            text: '${e.key + 1}. ${e.value}'),
                      ),
                  const SizedBox(height: 14),
                ],
                if (kb.requiredTools.isNotEmpty) ...[
                  const _SubHeading(title: 'Required Tools'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kb.requiredTools
                        .map((t) => _Chip(
                            label: t,
                            color: AppColors.textMuted,
                            icon: Icons.build_rounded))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SubHeading extends StatelessWidget {
  final String title;
  const _SubHeading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(
            color: AppColors.amberLight,
            fontSize: 13,
            fontWeight: FontWeight.w700));
  }
}

class _BulletLine extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _BulletLine({
    required this.text,
    this.icon = Icons.fiber_manual_record,
    this.color = AppColors.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Chip(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
