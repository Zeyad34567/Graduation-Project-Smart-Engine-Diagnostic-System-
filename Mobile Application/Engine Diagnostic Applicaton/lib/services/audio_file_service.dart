import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class AudioFileService {
  static const int sampleRate = 22050;
  static const int windowDurationSec = 5;
  static const int targetSamples = 110250;

  Future<Float32List> readAudioFile(String filePath, {int maxSeconds = 60}) async {
    final wavPath = await _convertToWav(filePath);
    try {
      final samples = await _readWavAsFloat32(wavPath);
      final maxSamples = maxSeconds * sampleRate;
      if (samples.length > maxSamples) {
        return Float32List.sublistView(samples, 0, maxSamples);
      }
      return samples;
    } finally {
      try {
        await File(wavPath).delete();
      } catch (_) {}
    }
  }

  Float32List extractWindow(Float32List fullAudio, int offsetSamples) {
    final window = Float32List(targetSamples);
    final available = fullAudio.length - offsetSamples;
    final copyLen = available.clamp(0, targetSamples);
    if (copyLen > 0) {
      window.setRange(0, copyLen, fullAudio, offsetSamples);
    }
    return window;
  }

  Future<String> _convertToWav(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/engine_${DateTime.now().millisecondsSinceEpoch}.wav';

    final session = await FFmpegKit.execute(
      '-y -i "$inputPath" -ar $sampleRate -ac 1 -sample_fmt s16 -f wav "$outPath"',
    );

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Audio conversion failed: $logs');
    }
    return outPath;
  }

  Future<Float32List> _readWavAsFloat32(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44) throw Exception('Invalid WAV file (too short)');

    final data = ByteData.sublistView(bytes);
    int offset = 12;
    int dataOffset = -1;
    int dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (dataOffset == -1) throw Exception('No PCM data chunk found in WAV');

    final sampleCount = dataSize ~/ 2;
    final out = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final byteIndex = dataOffset + i * 2;
      if (byteIndex + 2 > bytes.length) break;
      out[i] = data.getInt16(byteIndex, Endian.little) / 32768.0;
    }
    return out;
  }
}
