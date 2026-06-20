import 'dart:math';
import 'dart:typed_data';

/// Produces the 3-channel spectrogram input for the TFLite model AND
/// a flat 418-feature vector for the Random Forest models.
///
/// ── RF feature vector layout (418 total) — matches training notebook exactly ─
///  [0  –159]  MFCC mean, std, max, min        (40×4 = 160)
///  [160–239]  MFCC Δ  mean, std               (40×2 = 80)
///  [240–319]  MFCC ΔΔ mean, std               (40×2 = 80)
///  [320–323]  spectral_centroid  mean,std,max,min  (4)
///  [324–325]  spectral_bandwidth mean,std          (2)
///  [326–327]  spectral_rolloff   mean,std          (2)
///  [328–329]  spectral_flatness  mean,std          (2)
///  [330–343]  spectral_contrast  mean(7)+std(7)    (14)
///  [344–345]  ZCR mean,std                         (2)
///  [346–348]  RMS mean,std,max                     (3)
///  [349]      tempo BPM                            (1)
///  [350–413]  mel sub-band stats:
///               pcen_sub mean(16)+std(16) +
///               mel_db_sub mean(16)+std(16)        (64)
///  [414–417]  harmonic ratio: log_ratio, even_energy, odd_energy, f0_mean (4)
/// ────────────────────────────────────────────────────────────────────────────
///
/// ── CHANGES vs original (to match librosa / training notebook) ──────────────
///  FIX-1  STFT centering: audio is ZERO-padded by n_fft//2 on each side
///         before the STFT, matching librosa's default center=True behaviour.
///         NOTE: librosa's default pad_mode changed from 'reflect' (≤0.8) to
///         'constant' i.e. zero-padding (0.9+, including 0.10/0.11). Since the
///         training notebooks never pass pad_mode explicitly, they used
///         zero-padding. This adds 4 extra frames (216 vs 212) and aligns
///         frame timestamps.
///
///  FIX-2  Mel filterbank input: uses POWER spectrogram (magnitude²) instead
///         of magnitude, matching librosa.feature.melspectrogram default.
///
///  FIX-3  logMel for MFCC: 10·log₁₀(power_mel + 1e-10) instead of
///         ln(mag_mel + 1e-6), matching librosa.power_to_db(ref=1.0).
///
///  FIX-4  Spectral contrast: quantile changed from 0.20 → 0.02 to match
///         librosa's default (quantile=0.02).  Contrast value changed to
///         10·log₁₀(peak+ε) − 10·log₁₀(valley+ε) (power_to_db style).
///
///  FIX-5  Tempo: onset-strength envelope (mean positive diff of power_to_db
///         mel across mel bins) replaces raw STFT-flux, matching librosa's
///         librosa.onset.onset_strength.  Autocorrelation and
///         tempo_frequencies formula are otherwise unchanged.
/// ─────────────────────────────────────────────────────────────────────────────
class AudioFeatures {
  static const int sampleRate    = 22050;
  static const int targetSamples = 110250; // 5 s × 22050 Hz
  static const int melBins       = 128;
  static const int nMfcc         = 40;
  static const int nContrast     = 7;

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC ENTRY POINTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Peak-normalises the full clip to [-1,1] WITHOUT trimming/padding.
  static Float32List normalizeAmplitude(Float32List raw) {
    double peak = 0.0;
    for (final v in raw) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final scale = peak > 1e-8 ? 1.0 / peak : 1.0;
    final out = Float32List(raw.length);
    for (int i = 0; i < raw.length; i++) out[i] = raw[i] * scale;
    return out;
  }

  /// Pads or trims raw audio to exactly 5 s at 22050 Hz, peak-normalised to [-1,1].
  static Float32List preprocess(Float32List raw) {
    double peak = 0.0;
    for (final v in raw) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final scale = peak > 1e-8 ? 1.0 / peak : 1.0;
    final out = Float32List(targetSamples);
    final n = min(raw.length, targetSamples);
    for (int i = 0; i < n; i++) out[i] = raw[i] * scale;
    return out;
  }

  // ── Spectrogram channels (TFLite path — kept for compatibility) ───────────

  static Float32List channelPcenMel(Float32List audio) {
    final mag = _stftMagnitude(audio, nFft: 2048, hop: 512);
    final mel = _melFilterbank(mag, nFft: 2048, melBins: melBins);
    return _flatten(_pcen(mel));
  }

  static Float32List channelFineTime(Float32List audio) {
    final mag = _stftMagnitude(audio, nFft: 512, hop: 128);
    final mel = _melFilterbank(mag, nFft: 512, melBins: melBins);
    return _flatten(_logCompress(mel));
  }

  static Float32List channelFineFreq(Float32List audio) {
    final mag = _stftMagnitude(audio, nFft: 4096, hop: 1024);
    final mel = _melFilterbank(mag, nFft: 4096, melBins: melBins);
    return _flatten(_logCompress(mel));
  }

  static List<List<List<double>>> allChannels(Float32List audio) {
    final ch0 = _pcen(_melFilterbank(
        _stftMagnitude(audio, nFft: 2048, hop: 512), nFft: 2048, melBins: melBins));
    final ch1 = _logCompress(_melFilterbank(
        _stftMagnitude(audio, nFft: 512, hop: 128), nFft: 512, melBins: melBins));
    final ch2 = _logCompress(_melFilterbank(
        _stftMagnitude(audio, nFft: 4096, hop: 1024), nFft: 4096, melBins: melBins));
    return [ch0, ch1, ch2];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 418-FEATURE VECTOR FOR RANDOM FOREST
  // Layout must match training notebook extract_all_features() EXACTLY.
  // ══════════════════════════════════════════════════════════════════════════

  static Float64List extractFeatures(Float32List audio) {
    const int nFft = 2048;
    const int hop  = 512;

    // FIX-1: zero-pad audio by n_fft//2 on each side (librosa center=True, pad_mode='constant').
    final paddedAudio = _zeroPad(audio, nFft ~/ 2);

    // ── Shared STFT on padded audio ───────────────────────────────────────
    // FIX-2: use POWER spectrogram (magnitude²) for mel-based features.
    final powFrames  = _stftPower(paddedAudio, nFft: nFft, hop: hop);
    final magFrames  = _stftMagnitudeFromPower(powFrames);  // √power for spectral features
    final numFrames  = powFrames.length;
    final numFftBins = nFft ~/ 2 + 1;

    // ── Mel filterbank on POWER spectrogram ───────────────────────────────
    final melMatrix = _melFilterbankRaw(powFrames, nFft: nFft, melBins: melBins);

    // ── MFCCs ─────────────────────────────────────────────────────────────
    // FIX-3: use 10·log₁₀ (power_to_db, ref=1) instead of ln.
    final logMelF     = _powerToDbFrames(melMatrix, numFrames);  // [T][128]
    final mfccFrames  = _dctII(logMelF, nMfcc);                  // [T][40]
    // FIX-5: librosa.feature.delta(mfcc, order=2) fits a quadratic
    // Savitzky-Golay filter directly on mfccFrames — it is NOT the
    // first-order delta applied twice.
    final deltaFrames = _delta(mfccFrames, order: 1);
    final delta2Frames= _delta(mfccFrames, order: 2);

    final feat = Float64List(418);
    int ptr = 0;

    // ── [0–159] MFCC mean, std, max, min  (160) ───────────────────────────
    final mfccStats = _colStats4(mfccFrames, nMfcc);
    _copyInto(feat, ptr, mfccStats); ptr += mfccStats.length;

    // ── [160–239] Δ mean, std  (80) ───────────────────────────────────────
    final dStats = _colMeanStd(deltaFrames, nMfcc);
    _copyInto(feat, ptr, dStats); ptr += dStats.length;

    // ── [240–319] ΔΔ mean, std  (80) ──────────────────────────────────────
    final d2Stats = _colMeanStd(delta2Frames, nMfcc);
    _copyInto(feat, ptr, d2Stats); ptr += d2Stats.length;

    // ── Spectral features (use magnitude frames) ──────────────────────────
    final centroid  = _spectralCentroid(magFrames, nFft, numFrames);
    final bandwidth = _spectralBandwidth(magFrames, centroid, nFft, numFrames);
    final rolloff   = _spectralRolloff(magFrames, numFftBins, numFrames);
    final flatness  = _spectralFlatness(magFrames, numFrames);
    final contrast  = _spectralContrast(magFrames, nFft, numFrames);  // FIX-4 inside
    final zcr       = _zeroCrossingRate(audio, hop, numFrames);  // edge-padded internally, frame_length=2048
    final rms       = _rmsEnergy(paddedAudio, hop, numFrames);   // zero-padded (paddedAudio), frame_length=2048

    // ── [320–323] centroid mean, std, max, min ────────────────────────────
    feat[ptr++] = _mean(centroid); feat[ptr++] = _std(centroid);
    feat[ptr++] = _max(centroid);  feat[ptr++] = _min(centroid);

    // ── [324–325] bandwidth mean, std ─────────────────────────────────────
    feat[ptr++] = _mean(bandwidth); feat[ptr++] = _std(bandwidth);

    // ── [326–327] rolloff mean, std ───────────────────────────────────────
    feat[ptr++] = _mean(rolloff); feat[ptr++] = _std(rolloff);

    // ── [328–329] flatness mean, std ──────────────────────────────────────
    feat[ptr++] = _mean(flatness); feat[ptr++] = _std(flatness);

    // ── [330–343] contrast mean(7) + std(7) ──────────────────────────────
    for (int b = 0; b < nContrast; b++) feat[ptr++] = _rowMean(contrast[b]);
    for (int b = 0; b < nContrast; b++) feat[ptr++] = _rowStd(contrast[b]);

    // ── [344–345] ZCR mean, std ───────────────────────────────────────────
    feat[ptr++] = _mean(zcr); feat[ptr++] = _std(zcr);

    // ── [346–348] RMS mean, std, max ──────────────────────────────────────
    feat[ptr++] = _mean(rms); feat[ptr++] = _std(rms); feat[ptr++] = _max(rms);

    // ── [349] tempo BPM ───────────────────────────────────────────────────
    // FIX-5: onset-strength on power mel, not STFT-flux.
    feat[ptr++] = _tempoBpm(melMatrix, numFrames);

    // ── [350–413] mel sub-band stats (64) ────────────────────────────────
    final melStats = _melSubbandStats(melMatrix, numFrames);
    _copyInto(feat, ptr, melStats); ptr += 64;

    // ── [414–417] harmonic ratio (4) ──────────────────────────────────────
    final harm = _harmonicRatio(magFrames, nFft);
    feat[ptr++] = harm[0]; feat[ptr++] = harm[1];
    feat[ptr++] = harm[2]; feat[ptr++] = harm[3];

    assert(ptr == 418, 'Feature count mismatch: $ptr');
    return feat;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIX-1: ZERO PADDING (librosa center=True, pad_mode='constant' — the
  // actual default since librosa 0.9+; the training notebooks never override
  // pad_mode, so this is what produced the 418-d training features).
  // ══════════════════════════════════════════════════════════════════════════

  /// Zero-pads [padLen] samples of silence at each end — mirrors librosa's
  /// actual default STFT padding (pad_mode='constant') for center=True.
  static Float32List _zeroPad(Float32List audio, int padLen) {
    final n   = audio.length;
    final out = Float32List(n + 2 * padLen); // zero-initialised by default
    for (int i = 0; i < n; i++) out[padLen + i] = audio[i];
    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MFCC helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// FIX-3: 10·log₁₀(power_mel + ε) — matches librosa.power_to_db(ref=1.0).
  static List<List<double>> _powerToDbFrames(
      List<List<double>> melMatrix, int numFrames) {
    const double eps = 1e-10;
    final nBins = melMatrix.length;
    final out = List.generate(numFrames, (_) => List<double>.filled(nBins, 0.0));
    for (int m = 0; m < nBins; m++) {
      for (int t = 0; t < numFrames; t++) {
        out[t][m] = 10.0 * (log(melMatrix[m][t] + eps) / ln10);
      }
    }
    return out;
  }

  /// Orthonormal DCT-II — matches scipy.fftpack.dct(type=2, norm='ortho').
  static List<List<double>> _dctII(List<List<double>> frames, int nCoeffs) {
    final T = frames.length;
    if (T == 0) return [];
    final N = frames[0].length;
    final out = List.generate(T, (_) => List<double>.filled(nCoeffs, 0.0));
    final factor = pi / N;
    for (int t = 0; t < T; t++) {
      for (int k = 0; k < nCoeffs; k++) {
        double sum = 0.0;
        for (int n = 0; n < N; n++) {
          sum += frames[t][n] * cos(factor * k * (n + 0.5));
        }
        final norm = (k == 0) ? sqrt(1.0 / N) : sqrt(2.0 / N);
        out[t][k] = sum * norm;
      }
    }
    return out;
  }

  /// Finite-difference delta, width=9 (matches librosa.feature.delta).
  /// Matches librosa.feature.delta(data, width=9, order=order, mode='interp'),
  /// i.e. scipy.signal.savgol_filter(data, 9, polyorder=order, deriv=order).
  /// For BOTH order=1 (linear fit slope) and order=2 (quadratic fit 2nd
  /// derivative), the fitted derivative is CONSTANT across its 9-point
  /// window — so at the edges (where savgol's mode='interp' always uses a
  /// fixed boundary window rather than padding), every edge frame within
  /// the half-window shares exactly one value: the one computed from the
  /// boundary window's fixed center.
  static List<List<double>> _delta(List<List<double>> frames, {int order = 1}) {
    final T = frames.length;
    if (T == 0) return [];
    final K = frames[0].length;
    const int W = 4; // half-width, window = 9

    // Closed-form 9-point Savitzky-Golay weights, index i = -4..4:
    //   order 1 (slope):        w_i = i / 60
    //   order 2 (2nd deriv):    w_i = (3*i^2 - 20) / 462
    final weights = List<double>.generate(9, (idx) {
      final i = idx - 4;
      return order == 1 ? (i / 60.0) : ((3.0 * i * i - 20.0) / 462.0);
    });

    List<double> computeAt(int center) {
      final row = List<double>.filled(K, 0.0);
      for (int k = 0; k < K; k++) {
        double sum = 0.0;
        for (int idx = 0; idx < 9; idx++) {
          sum += weights[idx] * frames[center - 4 + idx][k];
        }
        row[k] = sum;
      }
      return row;
    }

    final out = List.generate(T, (_) => List<double>.filled(K, 0.0));

    if (T < 9) {
      // Degenerate short-window fallback (shouldn't occur for 5s windows).
      for (int t = 0; t < T; t++) {
        for (int k = 0; k < K; k++) {
          double num = 0.0;
          for (int w = 1; w <= W; w++) {
            final tFwd = (t + w).clamp(0, T - 1);
            final tBwd = (t - w).clamp(0, T - 1);
            num += w * (frames[tFwd][k] - frames[tBwd][k]);
          }
          out[t][k] = num / 60.0;
        }
      }
      return out;
    }

    final leftVal  = computeAt(4);
    final rightVal = computeAt(T - 5);
    for (int t = 0; t < 4; t++)      out[t] = List<double>.from(leftVal);
    for (int t = T - 4; t < T; t++)  out[t] = List<double>.from(rightVal);
    for (int t = 4; t <= T - 5; t++) out[t] = computeAt(t);

    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPECTRAL FEATURES
  // ══════════════════════════════════════════════════════════════════════════

  /// FIX-4: quantile=0.02 (was 0.20) and power_to_db contrast formula.
  static List<List<double>> _spectralContrast(
      List<List<double>> magFrames, int nFft, int numFrames) {
    // Band edges: fmin=200, 6 octave bands → [0,200], [200,400], [400,800],
    //             [800,1600], [1600,3200], [3200,6400], [6400, sr/2]
    // Matches librosa default: fmin=200, n_bands=6.
    final bandEdges = [200.0, 400.0, 800.0, 1600.0, 3200.0, 6400.0, sampleRate / 2.0];
    const double quantile = 0.02;  // FIX-4: was 0.20
    final contrast = List.generate(nContrast, (_) => List<double>.filled(numFrames, 0.0));
    for (int t = 0; t < numFrames; t++) {
      final frame = magFrames[t];
      double prevHz = 0.0;
      for (int b = 0; b < nContrast; b++) {
        final lowBin  = (prevHz * nFft / sampleRate).round().clamp(0, frame.length - 1);
        final highBin = (bandEdges[b] * nFft / sampleRate).round().clamp(0, frame.length - 1);
        prevHz = bandEdges[b];
        if (highBin <= lowBin) { contrast[b][t] = 0.0; continue; }
        final band = List<double>.from(frame.sublist(lowBin, highBin + 1))..sort();
        final nPct   = max(1, (band.length * quantile).round());  // FIX-4
        double valleySum = 0.0;
        for (int i = 0; i < nPct; i++) valleySum += band[i];
        final valley = valleySum / nPct;
        double peakSum = 0.0;
        for (int i = band.length - nPct; i < band.length; i++) peakSum += band[i];
        final peak = peakSum / nPct;
        // FIX-4: power_to_db style (10·log₁₀), using MAGNITUDE directly
        // (NOT squared) — librosa's spectral_contrast feeds raw magnitude
        // peak/valley into power_to_db without squaring first (power=1
        // spectrogram). Squaring here would double every value vs training.
        contrast[b][t] =
            10.0 * (log(peak + 1e-10) / ln10) -
            10.0 * (log(valley + 1e-10) / ln10);
      }
    }
    return contrast;
  }

  static List<double> _spectralCentroid(
      List<List<double>> magFrames, int nFft, int numFrames) {
    final out = List<double>.filled(numFrames, 0.0);
    final freqBins = nFft ~/ 2 + 1;
    for (int t = 0; t < numFrames; t++) {
      final frame = magFrames[t];
      double ws = 0.0, tm = 0.0;
      for (int k = 0; k < freqBins; k++) {
        final freq = k * sampleRate / nFft;
        ws += freq * frame[k];
        tm += frame[k];
      }
      out[t] = tm > 1e-8 ? ws / tm : 0.0;
    }
    return out;
  }

  static List<double> _spectralBandwidth(List<List<double>> magFrames,
      List<double> centroid, int nFft, int numFrames) {
    final out = List<double>.filled(numFrames, 0.0);
    final freqBins = nFft ~/ 2 + 1;
    for (int t = 0; t < numFrames; t++) {
      final frame = magFrames[t];
      double ws = 0.0, tm = 0.0;
      for (int k = 0; k < freqBins; k++) {
        final freq = k * sampleRate / nFft;
        ws += pow(freq - centroid[t], 2) * frame[k];
        tm += frame[k];
      }
      out[t] = tm > 1e-8 ? sqrt(ws / tm) : 0.0;
    }
    return out;
  }

  static List<double> _spectralRolloff(List<List<double>> magFrames,
      int numFftBins, int numFrames,
      {double rolloffPercent = 0.85}) {
    final out = List<double>.filled(numFrames, 0.0);
    for (int t = 0; t < numFrames; t++) {
      final frame = magFrames[t];
      final total = frame.fold(0.0, (s, v) => s + v);
      final threshold = total * rolloffPercent;
      double cumSum = 0.0;
      for (int k = 0; k < numFftBins; k++) {
        cumSum += frame[k];
        if (cumSum >= threshold) {
          out[t] = k * sampleRate / (2.0 * (numFftBins - 1));
          break;
        }
      }
    }
    return out;
  }

  static List<double> _spectralFlatness(
      List<List<double>> magFrames, int numFrames) {
    final out = List<double>.filled(numFrames, 0.0);
    for (int t = 0; t < numFrames; t++) {
      final frame = magFrames[t];
      final n = frame.length;
      double logSum = 0.0, arithSum = 0.0;
      for (int k = 0; k < n; k++) {
        logSum   += log(frame[k] + 1e-10);
        arithSum += frame[k];
      }
      final geoMean   = exp(logSum / n);
      final arithMean = arithSum / n;
      out[t] = arithMean > 1e-8 ? geoMean / arithMean : 0.0;
    }
    return out;
  }

  /// Matches librosa.feature.zero_crossing_rate defaults: frame_length=2048,
  /// center=True with EDGE padding (librosa's specific default for this
  /// function — different from the zero-padding used elsewhere).
  static List<double> _zeroCrossingRate(
      Float32List audio, int hop, int numFrames, {int frameLen = 2048}) {
    final padLen = frameLen ~/ 2;
    final n = audio.length;
    final padded = Float32List(n + 2 * padLen);
    for (int i = 0; i < padLen; i++) {
      padded[i] = audio.isNotEmpty ? audio[0] : 0.0;               // edge-pad left
    }
    for (int i = 0; i < n; i++) padded[padLen + i] = audio[i];
    for (int i = 0; i < padLen; i++) {
      padded[padLen + n + i] = audio.isNotEmpty ? audio[n - 1] : 0.0; // edge-pad right
    }

    final out = List<double>.filled(numFrames, 0.0);
    for (int t = 0; t < numFrames; t++) {
      final start = t * hop;
      final end   = (start + frameLen).clamp(0, padded.length);
      if (end <= start + 1) continue;
      int crossings = 0;
      for (int i = start + 1; i < end; i++) {
        if ((padded[i] >= 0) != (padded[i - 1] >= 0)) crossings++;
      }
      out[t] = crossings / (end - start);
    }
    return out;
  }

  /// Matches librosa.feature.rms defaults: frame_length=2048, center=True,
  /// pad_mode='constant' (zero). [audio] must already be the zero-padded
  /// signal (paddedAudio) so frames align with the STFT-derived frame grid.
  static List<double> _rmsEnergy(Float32List audio, int hop, int numFrames,
      {int frameLen = 2048}) {
    final out = List<double>.filled(numFrames, 0.0);
    for (int t = 0; t < numFrames; t++) {
      final start = t * hop;
      final end   = (start + frameLen).clamp(0, audio.length);
      if (end <= start) continue;
      double sumSq = 0.0;
      for (int i = start; i < end; i++) sumSq += audio[i] * audio[i];
      out[t] = sqrt(sumSq / (end - start));
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIX-5: TEMPO via onset-strength envelope on power_to_db mel.
  // Replicates librosa.onset.onset_strength + autocorrelate + tempo_frequencies.
  // ══════════════════════════════════════════════════════════════════════════

  /// [melMatrix] is the power mel filterbank [melBins][numFrames].
  static double _tempoBpm(List<List<double>> melMatrix, int numFrames) {
    if (numFrames < 2) return 120.0;

    // 1. power_to_db(mel, ref=1.0) → [melBins][numFrames]
    const double eps = 1e-10;
    final nBins = melMatrix.length;
    final melDb = List.generate(nBins, (m) {
      return List<double>.generate(numFrames,
          (t) => 10.0 * (log(melMatrix[m][t] + eps) / ln10));
    });

    // 2. Onset strength = mean of positive column-wise diffs across mel bins.
    //    librosa pads a 0 at the beginning (frame 0 = 0).
    final onset = List<double>.filled(numFrames, 0.0);
    for (int t = 1; t < numFrames; t++) {
      double sumPos = 0.0;
      for (int m = 0; m < nBins; m++) {
        final d = melDb[m][t] - melDb[m][t - 1];
        if (d > 0) sumPos += d;
      }
      onset[t] = sumPos / nBins;
    }

    // 3. Full autocorrelation truncated to max_size=500.
    //    ac[lag] = Σ onset[i] * onset[i+lag]
    const int maxSize = 500;
    final acLen = min(numFrames, maxSize);
    final ac = List<double>.filled(acLen, 0.0);
    for (int lag = 0; lag < acLen; lag++) {
      double s = 0.0;
      for (int i = 0; i + lag < numFrames; i++) s += onset[i] * onset[i + lag];
      ac[lag] = s;
    }

    // 4. tempo_frequencies: BPM[lag] = 60 * sr / (hop * lag).
    //    Find argmax of ac[1:] and convert to BPM.
    int bestLag = 1;
    double bestVal = double.negativeInfinity;
    for (int lag = 1; lag < acLen; lag++) {
      if (ac[lag] > bestVal) { bestVal = ac[lag]; bestLag = lag; }
    }
    return 60.0 * sampleRate / (512 * bestLag);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MEL SUB-BAND STATS — matches training's extract_mel_stats (64 values)
  //
  // Training:
  //   pcen  = librosa.pcen(mel * 2^31, ...)
  //   pcen_subbands  = pcen.reshape(16, 8, T).mean(axis=1)   → [16][T]
  //   mel_db = librosa.power_to_db(mel, ref=np.max)           → [128][T]
  //   mel_subbands   = mel_db.reshape(16, 8, T).mean(axis=1)  → [16][T]
  //   features = mean(pcen_sub,axis=1) + std(pcen_sub,axis=1)
  //            + mean(mel_sub,axis=1)  + std(mel_sub,axis=1)   = 64
  // ══════════════════════════════════════════════════════════════════════════

  static List<double> _melSubbandStats(
      List<List<double>> melMatrix, int numFrames) {
    const int nSub      = 16;
    const int binsPerSub = 8; // 128 / 16

    // ── PCEN  ────────────────────────────────────────────────────────────
    // Training scales mel by 2^31 before pcen.
    // librosa.pcen formula:
    //   M[t]   = b*S[t] + (1-b)*M[t-1]                      (smoothing)
    //   out[t] = (S[t] / (eps + M[t])^gain + bias)^power - bias^power
    // NOTE: gain (0.98) and power (0.5) are TWO DIFFERENT exponents used in
    // two different places — this was previously collapsed into one (bug).
    // b solves  b^2 + (1-b)/T - 2 = 0  →  b = (sqrt(1+4T²)-1) / (2T²)
    // where T = time_constant * sr / hop_length.
    const double pcenGain    = 0.98;   // AGC normalization exponent
    const double pcenBias    = 2.0;
    const double pcenPower   = 0.5;    // outer compression exponent
    const double pcenEps     = 1e-6;
    const double melScale    = 2147483648.0; // 2^31

    // b = (sqrt(1+4T²)-1) / (2T²), T = time_constant*sr/hop = 0.4*22050/512
    const double _tFrames = 0.4 * sampleRate / 512.0;
    final double pcenB = (sqrt(1 + 4 * _tFrames * _tFrames) - 1) /
                          (2 * _tFrames * _tFrames);

    final pcenOut = List.generate(melBins, (_) => List<double>.filled(numFrames, 0.0));
    for (int m = 0; m < melBins; m++) {
      double ema = melMatrix[m].isNotEmpty ? melMatrix[m][0] * melScale : 0.0;
      for (int t = 0; t < numFrames; t++) {
        final scaled = melMatrix[m][t] * melScale;
        ema = (1.0 - pcenB) * ema + pcenB * scaled;
        final agc     = pow(ema + pcenEps, -pcenGain);   // FIX: was -pcenPower
        final pcenVal = pow(scaled * agc + pcenBias, pcenPower) -
                        pow(pcenBias, pcenPower);
        pcenOut[m][t] = pcenVal.toDouble();
      }
    }

    // ── mel_db = 10 * log10(mel / max(mel))  (ref=np.max) ────────────────
    double globalMax = 1e-10;
    for (final row in melMatrix) {
      for (final v in row) if (v > globalMax) globalMax = v;
    }
    final melDb = List.generate(melBins, (m) {
      return List<double>.generate(numFrames,
          (t) => 10.0 * (log(melMatrix[m][t] / globalMax + 1e-10) / ln10));
    });

    // ── Sub-band average: [128][T] → [16][T] ─────────────────────────────
    List<List<double>> subAvg(List<List<double>> src) {
      final sub = List.generate(nSub, (_) => List<double>.filled(numFrames, 0.0));
      for (int s = 0; s < nSub; s++) {
        for (int b = 0; b < binsPerSub; b++) {
          final m = s * binsPerSub + b;
          for (int t = 0; t < numFrames; t++) sub[s][t] += src[m][t];
        }
        for (int t = 0; t < numFrames; t++) sub[s][t] /= binsPerSub;
      }
      return sub;
    }

    final pcenSub  = subAvg(pcenOut);
    final melDbSub = subAvg(melDb);

    final out = <double>[];
    for (int s = 0; s < nSub; s++) out.add(_rowMean(pcenSub[s]));
    for (int s = 0; s < nSub; s++) out.add(_rowStd(pcenSub[s]));
    for (int s = 0; s < nSub; s++) out.add(_rowMean(melDbSub[s]));
    for (int s = 0; s < nSub; s++) out.add(_rowStd(melDbSub[s]));
    return out; // 64
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HARMONIC RATIO — matches training's extract_harmonic_ratio (4 values)
  // ══════════════════════════════════════════════════════════════════════════

  static List<double> _harmonicRatio(
      List<List<double>> magFrames, int nFft) {
    final numBins = nFft ~/ 2 + 1;

    // Mean magnitude per frequency bin across all frames
    final meanMag = List<double>.filled(numBins, 0.0);
    if (magFrames.isNotEmpty) {
      for (final frame in magFrames) {
        for (int k = 0; k < numBins; k++) meanMag[k] += frame[k];
      }
      for (int k = 0; k < numBins; k++) meanMag[k] /= magFrames.length;
    }

    // Find f0 in [50, 3000] Hz
    // Matches Python's (freqs >= 50) & (freqs <= 3000) boolean mask exactly:
    // smallest bin with freq>=50 is ceil(50*nFft/sr); largest with freq<=3000
    // is floor(3000*nFft/sr) — NOT round(), which can be off by one bin.
    final binMin = (50.0   * nFft / sampleRate).ceil().clamp(1, numBins - 1);
    final binMax = (3000.0 * nFft / sampleRate).floor().clamp(1, numBins - 1);
    int f0Bin = binMin;
    double f0Mag = 0.0;
    for (int k = binMin; k <= binMax; k++) {
      if (meanMag[k] > f0Mag) { f0Mag = meanMag[k]; f0Bin = k; }
    }
    final f0Hz = f0Bin * sampleRate / nFft.toDouble();

    // Sum even/odd harmonic energies (harmonics 1–8, ±2 bin band)
    double evenEnergy = 0.0, oddEnergy = 0.0;
    for (int harmonic = 1; harmonic <= 8; harmonic++) {
      final hBin = (f0Hz * harmonic * nFft / sampleRate).round();
      final lo   = max(0, hBin - 2);
      final hi   = min(numBins - 1, hBin + 2);
      double energy = 0.0;
      int count = 0;
      for (int k = lo; k <= hi; k++) { energy += meanMag[k]; count++; }
      if (count > 0) energy /= count;
      if (harmonic % 2 == 0) { evenEnergy += energy; } else { oddEnergy += energy; }
    }

    const double eps = 1e-8;
    final logRatio = log(evenEnergy + eps) - log(oddEnergy + eps);
    return [logRatio, evenEnergy, oddEnergy, f0Hz];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STATISTICS HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// mean, std, max, min for each column — returns flat list of length 4K.
  static List<double> _colStats4(List<List<double>> frames, int K) {
    final T    = frames.length;
    final mean = List<double>.filled(K, 0.0);
    final std  = List<double>.filled(K, 0.0);
    final maxV = List<double>.filled(K, double.negativeInfinity);
    final minV = List<double>.filled(K, double.infinity);
    if (T == 0) return [...mean, ...std, ...List.filled(K, 0.0), ...List.filled(K, 0.0)];
    for (int t = 0; t < T; t++) {
      for (int k = 0; k < K; k++) {
        final v = frames[t][k];
        mean[k] += v;
        if (v > maxV[k]) maxV[k] = v;
        if (v < minV[k]) minV[k] = v;
      }
    }
    for (int k = 0; k < K; k++) mean[k] /= T;
    for (int t = 0; t < T; t++) {
      for (int k = 0; k < K; k++) {
        final d = frames[t][k] - mean[k];
        std[k] += d * d;
      }
    }
    for (int k = 0; k < K; k++) std[k] = sqrt(std[k] / T);
    return [...mean, ...std, ...maxV, ...minV];
  }

  /// mean + std for each column — returns flat list of length 2K.
  static List<double> _colMeanStd(List<List<double>> frames, int K) {
    final T    = frames.length;
    final mean = List<double>.filled(K, 0.0);
    final std  = List<double>.filled(K, 0.0);
    if (T == 0) return [...mean, ...std];
    for (int t = 0; t < T; t++) {
      for (int k = 0; k < K; k++) mean[k] += frames[t][k];
    }
    for (int k = 0; k < K; k++) mean[k] /= T;
    for (int t = 0; t < T; t++) {
      for (int k = 0; k < K; k++) {
        final d = frames[t][k] - mean[k];
        std[k] += d * d;
      }
    }
    for (int k = 0; k < K; k++) std[k] = sqrt(std[k] / T);
    return [...mean, ...std];
  }

  static double _rowMean(List<double> row) {
    if (row.isEmpty) return 0.0;
    return row.fold(0.0, (s, v) => s + v) / row.length;
  }

  static double _rowStd(List<double> row) {
    if (row.isEmpty) return 0.0;
    final m = _rowMean(row);
    return sqrt(row.fold(0.0, (s, v) => s + (v - m) * (v - m)) / row.length);
  }

  static double _mean(List<double> v) => _rowMean(v);
  static double _std(List<double> v)  => _rowStd(v);

  static double _min(List<double> v) {
    if (v.isEmpty) return 0.0;
    return v.reduce(min);
  }

  static double _max(List<double> v) {
    if (v.isEmpty) return 0.0;
    return v.reduce(max);
  }

  static void _copyInto(Float64List dest, int offset, List<double> src) {
    for (int i = 0; i < src.length; i++) dest[offset + i] = src[i];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STFT helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns POWER spectrogram frames [T][nFft/2+1] — magnitude² per bin.
  /// FIX-2: used for mel-based features (MFCC, mel stats, PCEN, tempo).
  static List<List<double>> _stftPower(
    Float32List audio, {
    required int nFft,
    required int hop,
  }) {
    final window    = _hannWindow(nFft);
    final numFrames = max(1, ((audio.length - nFft) / hop).floor() + 1);
    final result    = <List<double>>[];

    if (numFrames <= 0) {
      final real = Float64List(nFft);
      final imag = Float64List(nFft);
      for (int j = 0; j < audio.length && j < nFft; j++) {
        real[j] = audio[j] * window[j];
      }
      _fft(real, imag);
      result.add(_powerBins(real, imag, nFft));
      return result;
    }

    for (int f = 0; f < numFrames; f++) {
      final start = f * hop;
      final real  = Float64List(nFft);
      final imag  = Float64List(nFft);
      for (int j = 0; j < nFft; j++) {
        final idx    = start + j;
        final sample = idx < audio.length ? audio[idx] : 0.0;
        real[j] = sample * window[j];
      }
      _fft(real, imag);
      result.add(_powerBins(real, imag, nFft));
    }
    return result;
  }

  /// Returns MAGNITUDE spectrogram frames [T][nFft/2+1].
  /// Used by TFLite channel path and spectral features.
  static List<List<double>> _stftMagnitude(
    Float32List audio, {
    required int nFft,
    required int hop,
  }) {
    final window    = _hannWindow(nFft);
    final numFrames = max(1, ((audio.length - nFft) / hop).floor() + 1);
    final result    = <List<double>>[];

    if (numFrames <= 0) {
      final real = Float64List(nFft);
      final imag = Float64List(nFft);
      for (int j = 0; j < audio.length && j < nFft; j++) {
        real[j] = audio[j] * window[j];
      }
      _fft(real, imag);
      result.add(_magnitudes(real, imag, nFft));
      return result;
    }

    for (int f = 0; f < numFrames; f++) {
      final start = f * hop;
      final real  = Float64List(nFft);
      final imag  = Float64List(nFft);
      for (int j = 0; j < nFft; j++) {
        final idx    = start + j;
        final sample = idx < audio.length ? audio[idx] : 0.0;
        real[j] = sample * window[j];
      }
      _fft(real, imag);
      result.add(_magnitudes(real, imag, nFft));
    }
    return result;
  }

  /// Derives magnitude frames from power frames — avoids re-running FFT.
  static List<List<double>> _stftMagnitudeFromPower(List<List<double>> powFrames) {
    return powFrames.map((frame) => frame.map(sqrt).toList()).toList();
  }

  static List<double> _magnitudes(
      Float64List real, Float64List imag, int nFft) {
    final bins = nFft ~/ 2 + 1;
    final mags = List<double>.filled(bins, 0.0);
    for (int k = 0; k < bins; k++) {
      mags[k] = sqrt(real[k] * real[k] + imag[k] * imag[k]);
    }
    return mags;
  }

  /// FIX-2: power bins = magnitude².
  static List<double> _powerBins(
      Float64List real, Float64List imag, int nFft) {
    final bins = nFft ~/ 2 + 1;
    final pows = List<double>.filled(bins, 0.0);
    for (int k = 0; k < bins; k++) {
      pows[k] = real[k] * real[k] + imag[k] * imag[k];
    }
    return pows;
  }

  /// Periodic Hann window — matches librosa's STFT default
  /// (scipy.signal.get_window('hann', n_fft, fftbins=True)), which uses
  /// denominator N, NOT the symmetric/numpy.hanning denominator N-1.
  static Float64List _hannWindow(int n) {
    final w = Float64List(n);
    for (int i = 0; i < n; i++) {
      w[i] = 0.5 - 0.5 * cos(2 * pi * i / n);
    }
    return w;
  }

  static void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    if (n <= 1) return;

    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while ((j & bit) != 0) {
        j &= ~bit;
        bit >>= 1;
      }
      j |= bit;
      if (i < j) {
        final tr = real[i]; real[i] = real[j]; real[j] = tr;
        final ti = imag[i]; imag[i] = imag[j]; imag[j] = ti;
      }
    }

    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2 * pi / len;
      final wr  = cos(ang);
      final wi  = sin(ang);
      for (int i = 0; i < n; i += len) {
        double curWr = 1.0, curWi = 0.0;
        for (int k = 0; k < len ~/ 2; k++) {
          final uRe = real[i + k];
          final uIm = imag[i + k];
          final vRe = real[i + k + len ~/ 2] * curWr - imag[i + k + len ~/ 2] * curWi;
          final vIm = real[i + k + len ~/ 2] * curWi + imag[i + k + len ~/ 2] * curWr;
          real[i + k]            = uRe + vRe;
          imag[i + k]            = uIm + vIm;
          real[i + k + len ~/ 2] = uRe - vRe;
          imag[i + k + len ~/ 2] = uIm - vIm;
          final nextWr = curWr * wr - curWi * wi;
          final nextWi = curWr * wi + curWi * wr;
          curWr = nextWr;
          curWi = nextWi;
        }
      }
    }
  }

  // Slaney mel scale (librosa's default, htk=False) — NOT the HTK
  // 2595·log10(1+hz/700) formula. Linear below 1kHz, log above.
  static const double _melFMin     = 0.0;
  static const double _melFSp      = 200.0 / 3.0; // 66.6667 mel/Hz below 1kHz
  static const double _melMinLogHz = 1000.0;
  static final double _melMinLogMel = (_melMinLogHz - _melFMin) / _melFSp; // 15.0
  static final double _melLogstep   = log(6.4) / 27.0;

  static double _hzToMel(double hz) {
    double mel = (hz - _melFMin) / _melFSp;
    if (hz >= _melMinLogHz) {
      mel = _melMinLogMel + log(hz / _melMinLogHz) / _melLogstep;
    }
    return mel;
  }

  static double _melToHz(double mel) {
    double hz = _melFMin + _melFSp * mel;
    if (mel >= _melMinLogMel) {
      hz = _melMinLogHz * exp(_melLogstep * (mel - _melMinLogMel));
    }
    return hz;
  }

  /// Generic mel filterbank — accepts either power or magnitude STFT frames.
  /// Slaney area normalisation (enorm = 2/(rightHz − leftHz)) is preserved.
  static List<List<double>> _melFilterbank(
    List<List<double>> stftFrames, {
    required int nFft,
    required int melBins,
  }) {
    return _melFilterbankRaw(stftFrames, nFft: nFft, melBins: melBins);
  }

  static List<List<double>> _melFilterbankRaw(
    List<List<double>> stftFrames, {
    required int nFft,
    required int melBins,
  }) {
    final numFrames  = stftFrames.length;
    final numFftBins = nFft ~/ 2 + 1;
    const double fMin = 0.0;
    final double fMax = sampleRate / 2.0;
    final melMin = _hzToMel(fMin);
    final melMax = _hzToMel(fMax);
    final melPoints = List<double>.generate(
        melBins + 2, (i) => melMin + (melMax - melMin) * i / (melBins + 1));
    final hzPoints  = melPoints.map(_melToHz).toList();

    // Actual (continuous) frequency of every FFT bin — NOT rounded.
    final fftFreqs = List<double>.generate(
        numFftBins, (k) => k * sampleRate / nFft.toDouble());

    // Precompute per-filter weights over every FFT bin using continuous
    // Hz-distance ramps (matches librosa.filters.mel exactly), instead of
    // snapping triangle vertices to integer bin indices first.
    final weights = List.generate(melBins, (_) => List<double>.filled(numFftBins, 0.0));
    for (int m = 0; m < melBins; m++) {
      final double leftHz   = hzPoints[m];
      final double centerHz = hzPoints[m + 1];
      final double rightHz  = hzPoints[m + 2];
      final double enorm    = (rightHz - leftHz) > 1e-8 ? 2.0 / (rightHz - leftHz) : 0.0;

      for (int k = 0; k < numFftBins; k++) {
        final double freq = fftFreqs[k];
        final double lower = (freq - leftHz) / (centerHz - leftHz);
        final double upper = (rightHz - freq) / (rightHz - centerHz);
        final double w = max(0.0, min(lower, upper));
        weights[m][k] = w.isFinite ? w * enorm : 0.0;
      }
    }

    final mel = List.generate(melBins, (_) => List<double>.filled(numFrames, 0.0));
    for (int m = 0; m < melBins; m++) {
      final wRow = weights[m];
      for (int t = 0; t < numFrames; t++) {
        final frame = stftFrames[t];
        double sum = 0.0;
        for (int k = 0; k < numFftBins; k++) {
          final w = wRow[k];
          if (w != 0.0) sum += frame[k] * w;
        }
        mel[m][t] = sum;
      }
    }
    return mel;
  }

  static List<List<double>> _pcen(List<List<double>> mel) {
    const double alpha   = 0.98;
    const double delta   = 2.0;
    const double r       = 0.5;
    const double epsilon = 1e-6;
    final bins = mel.length;
    final time = bins > 0 ? mel[0].length : 0;
    final output = List.generate(bins, (_) => List<double>.filled(time, 0.0));
    for (int m = 0; m < bins; m++) {
      double ema = mel[m].isNotEmpty ? mel[m][0] : 0.0;
      for (int t = 0; t < time; t++) {
        ema = alpha * ema + (1 - alpha) * mel[m][t];
        final gain    = pow(ema + epsilon, -r);
        final pcenVal = pow(mel[m][t] * gain + delta, r) - pow(delta, r);
        output[m][t]  = pcenVal.toDouble();
      }
    }
    return output;
  }

  static List<List<double>> _logCompress(List<List<double>> mel) {
    const double epsilon = 1e-6;
    return mel.map((row) => row.map((v) => log(v + epsilon)).toList()).toList();
  }

  static Float32List _flatten(List<List<double>> matrix) {
    if (matrix.isEmpty) return Float32List(0);
    final rows = matrix.length;
    final cols = matrix[0].length;
    final flat = Float32List(rows * cols);
    int idx = 0;
    for (final row in matrix) {
      for (final v in row) flat[idx++] = v;
    }
    return flat;
  }
}