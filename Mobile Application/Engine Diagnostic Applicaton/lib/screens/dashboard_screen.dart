import 'package:path_provider/path_provider.dart';
import 'dart:io';                                      // ← ADD     // ← ADD
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/engine_result.dart';
import '../services/audio_file_service.dart';
import '../services/inference_service.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/map_background.dart';
import '../widgets/power_button.dart';
import '../widgets/status_card.dart';
import 'result_screen.dart';

enum _DashState { idle, analyzing, result }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _DashState _dashState = _DashState.idle;
  EngineResult? _currentResult;
  final _inference = InferenceService();
  final _history = HistoryService();
  final _audioService = AudioFileService();

  String _statusText = 'Tap to Upload Audio';

  PowerButtonState get _btnState {
    switch (_dashState) {
      case _DashState.idle:
        return PowerButtonState.idle;
      case _DashState.analyzing:
        return PowerButtonState.analyzing;
      case _DashState.result:
        if (_currentResult == null) return PowerButtonState.idle;
        return _currentResult!.status == EngineStatus.good
            ? PowerButtonState.good
            : PowerButtonState.faulty;
    }
  }

  Future<void> _onPickFile() async {
  if (_dashState == _DashState.analyzing) return;

  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'ogg'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return;

  final file = picked.files.first;
  print('>>> FILE NAME: ${file.name}');
  print('>>> FILE PATH: ${file.path}');
  print('>>> FILE SIZE: ${file.size}');
  print('>>> FILE BYTES NULL: ${file.bytes == null}');

  final bytes = file.bytes;
  if (bytes == null) {
    print('>>> BYTES ARE NULL — this is the problem');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not read file bytes.')),
    );
    return;
  }

  print('>>> BYTES LENGTH: ${bytes.length}');

  setState(() {
    _dashState = _DashState.analyzing;
    _statusText = 'Analyzing…';
    _currentResult = null;
  });

  try {
    print('>>> WRITING TEMP FILE...');
    final dir = await getTemporaryDirectory();
    final tempPath = '${dir.path}/${file.name}';
    await File(tempPath).writeAsBytes(bytes);
    print('>>> TEMP FILE WRITTEN: $tempPath');

    print('>>> LOADING MODEL...');
    if (!_inference.isModelLoaded) await _inference.loadModel();
    print('>>> MODEL LOADED');

    print('>>> READING AUDIO...');
    final rawAudio = await _audioService.readAudioFile(tempPath, maxSeconds: 60);
    print('>>> AUDIO READ, SAMPLES: ${rawAudio.length}');

    try { await File(tempPath).delete(); } catch (_) {}

    print('>>> RUNNING INFERENCE...');
    final result = await _inference.analyzeAudio(rawAudio);
    print('>>> INFERENCE DONE');

    _history.add(result);

    if (!mounted) return;
    setState(() {
      _currentResult = result;
      _dashState = _DashState.result;
      _statusText = 'Tap to Upload Audio';
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    ).then((_) {
      if (mounted) {
        setState(() {
          _dashState = _DashState.idle;
          _currentResult = null;
          _statusText = 'Tap to Upload Audio';
        });
      }
    });
  } catch (e, stack) {
    print('>>> CRASH: $e');
    print('>>> STACK: $stack');
    if (!mounted) return;
    setState(() {
      _dashState = _DashState.idle;
      _statusText = 'Tap to Upload Audio';
      _currentResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}

  Color get _ambientColor {
    switch (_dashState) {
      case _DashState.idle:
      case _DashState.analyzing:
        return AppColors.amber;
      case _DashState.result:
        return _currentResult?.status == EngineStatus.good
            ? AppColors.good
            : AppColors.faulty;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          const MapBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                const SizedBox(height: 16),
                // ── Recording instructions ──
                _RecordingInstructions(),
                const SizedBox(height: 12),
                StatusCard(result: _currentResult),
                const Spacer(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomWave(
              ambientColor: _ambientColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PowerButton(state: _btnState, onTap: _onPickFile),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _statusText,
                      key: ValueKey(_statusText),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recording Instructions Banner ─────────────────────────────────
class _RecordingInstructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _Tip(icon: Icons.mic_external_on_rounded,
              text: 'Record closer to the engine'),
          _Tip(icon: Icons.speed_rounded,
              text: 'Keep engine running at idle speed'),
          _Tip(icon: Icons.wind_power_rounded,
              text: 'Avoid wind and background noise'),
          _Tip(icon: Icons.timer_rounded,
              text: 'Maximum recording length: 60 seconds'),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Wave ───────────────────────────────────────────────────
class _BottomWave extends StatelessWidget {
  final Widget child;
  final Color ambientColor;
  const _BottomWave({required this.child, required this.ambientColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ambientColor.withOpacity(0.85), ambientColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
        boxShadow: [
          BoxShadow(
            color: ambientColor.withOpacity(0.35),
            blurRadius: 30,
            spreadRadius: 4,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 32),
        child: child,
      ),
    );
  }
}
