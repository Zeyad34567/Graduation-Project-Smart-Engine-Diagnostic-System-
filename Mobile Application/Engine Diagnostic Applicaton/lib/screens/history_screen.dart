import 'package:flutter/material.dart';
import '../models/engine_result.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _history = HistoryService();

  void _clearHistory() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('Clear History',
            style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () {
              _history.clear();
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Clear',
                style: TextStyle(color: AppColors.faulty)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _history.all;

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
        title: const Text('Scan History',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.faulty),
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: records.isEmpty
          ? const _EmptyHistory()
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: records.length,
              itemBuilder: (_, i) {
                final r = records[i];
                return _HistoryTile(
                  result: r,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ResultScreen(result: r)),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 72, color: AppColors.textMuted),
          SizedBox(height: 16),
          Text('No scans yet',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 6),
          Text('Upload engine audio from the dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final EngineResult result;
  final VoidCallback onTap;

  const _HistoryTile({required this.result, required this.onTap});

  Color get _color {
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

  @override
  Widget build(BuildContext context) {
    final pct = result.primaryConfidence * 100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                result.status == EngineStatus.good
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                color: _color,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // Date + fault name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(result.timestamp),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.primaryFaultName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  if (result.status != EngineStatus.unknown)
                    Text(
                      '${pct.toStringAsFixed(0)}% confidence',
                      style: TextStyle(color: _color, fontSize: 12),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
