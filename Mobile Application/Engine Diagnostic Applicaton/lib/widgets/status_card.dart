import 'package:flutter/material.dart';
import '../models/engine_result.dart';
import '../theme/app_theme.dart';

class StatusCard extends StatelessWidget {
  final EngineResult? result;

  const StatusCard({super.key, this.result});

  Color get _statusColor {
    if (result == null) return AppColors.textMuted;
    switch (result!.status) {
      case EngineStatus.unknown:
        return AppColors.textMuted;
      case EngineStatus.good:
        return AppColors.good;
      case EngineStatus.warning:
        return AppColors.warning;
      case EngineStatus.faulty:
        return AppColors.faulty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null;
    final hasFaults = hasResult && result!.faults.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Engine Statues',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              if (hasResult)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    result!.statusLabel,
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Status line
          Text(
            hasResult ? result!.statusLabel : 'Unknown',
            style: TextStyle(
              color: _statusColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Fault list
          if (hasFaults) ...[
            const SizedBox(height: 8),
            ...result!.faults.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.faulty,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${f.name}  ${(f.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: AppColors.faulty,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
