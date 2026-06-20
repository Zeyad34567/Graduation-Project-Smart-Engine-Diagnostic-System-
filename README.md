#  Engine Fault Detection System

> An AI-powered mobile application that diagnoses car engine faults by analyzing audio recordings — entirely on-device, no internet required.

---

##  Table of Contents

- [Project Overview](#project-overview)
- [System Architecture](#system-architecture)
- [Fault Classes](#fault-classes)
- [Pipeline Flowcharts](#pipeline-flowcharts)
  - [Overall System Flow](#overall-system-flow)
  - [Feature Extraction Pipeline](#feature-extraction-pipeline)
  - [Inference Pipeline (Dual-Gate)](#inference-pipeline-dual-gate)
  - [Data Preparation Pipeline](#data-preparation-pipeline)
- [Dataset](#dataset)
- [Requirements & Dependencies](#requirements--dependencies)
  - [Python Training Environment](#python-training-environment)
  - [Flutter Mobile App](#flutter-mobile-app)
- [Project Structure](#project-structure)
- [Model Details](#model-details)
  - [Fault Classifier](#fault-classifier)
  - [OOD Gate](#ood-gate)
  - [Feature Vector (418 dimensions)](#feature-vector-418-dimensions)
- [Performance Results](#performance-results)
- [Knowledge Base](#knowledge-base)
- [App Screens](#app-screens)
- [Running the Project](#running-the-project)
  - [1. Training the Models (Python)](#1-training-the-models-python)
  - [2. Running the Flutter App](#2-running-the-flutter-app)
- [Audio Recording Guidelines](#audio-recording-guidelines)
- [Constants Reference](#constants-reference)
- [Fault Priority & Severity Reference](#fault-priority--severity-reference)

---

## Project Overview

Engine Fault Detection is a Flutter mobile application that accepts an audio recording of a car engine and returns a structured diagnosis. It identifies which of 11 possible faults is present — or confirms the engine is healthy — using two stacked Random Forest classifiers running entirely on the mobile device.

**Key capabilities:**
- Accepts WAV, MP3, M4A, AAC, and OGG audio formats
- Processes audio in overlapping 5-second windows
- Runs a binary **OOD Gate** first to reject non-engine sounds (birds, rain, traffic, etc.)
- Runs a **12-class Fault Classifier** on accepted windows
- Returns fault name, severity, safe-to-drive status, repair cost range, and step-by-step repair instructions
- Works fully offline — no server, no cloud, no data upload

---

## System Architecture

The system has four layers:

```
┌──────────────────────────────────────────────────────┐
│  LAYER 1: Audio Acquisition                          │
│  Microphone / File upload → WAV (22050 Hz, mono)     │
└───────────────────────┬──────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────┐
│  LAYER 2: Feature Extraction                         │
│  418-dimensional vector per 5-second window          │
│  (MFCCs · Spectral · Rhythm · Mel Sub-bands ·        │
│   Harmonic Ratio)                                    │
└───────────────────────┬──────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────┐
│  LAYER 3: Inference Pipeline                         │
│  OOD Gate (300 trees) → Fault Classifier (300 trees) │
└───────────────────────┬──────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────┐
│  LAYER 4: Knowledge Base Lookup                      │
│  engine_knowledge_base.json → full diagnostic report │
└──────────────────────────────────────────────────────┘
```

---

## Fault Classes

The system classifies audio into exactly **12 categories**:

| Index | Class Name | Severity | Safe to Drive | Urgency |
|-------|-----------|----------|---------------|---------|
| 0 | Alternator Bearing Noise | High | Short trips only | 48 hrs |
| 1 | Chain Noise | Medium | Limit trips | 72 hrs |
| 2 | Crankshaft Bearing Noise | **Critical** |  No | 0 hrs |
| 3 | Engine Knocking | High | Restricted | 48 hrs |
| 4 | Exhaust Leak | Medium |  Windows open | 168 hrs |
| 5 | Normal Healthy Engine | Safe |  Yes | — |
| 6 | Piston Slap | High | Short trips | 72 hrs |
| 7 | Rod Knock | **Critical** |  No | 0 hrs |
| 8 | Timing Belt Noise | High |  No | 0 hrs |
| 9 | Vacuum Leak | Low |  Yes | 336 hrs |
| 10 | Valve Tapping | Medium | Short trips | 168 hrs |
| 11 | Worn Pulley Noise | Low | Short trips | 168 hrs |

> **Index order is alphabetical** (assigned by `sklearn.LabelEncoder`). This order is fixed and must match across the trained model, `class_names.json`, and the Flutter inference code.

---

## Pipeline Flowcharts

### Overall System Flow

```
User picks audio file
        │
        ▼
FFmpegKit converts to WAV
(22050 Hz · mono · 16-bit PCM)
        │
        ▼
Split into overlapping 5s windows
(step = 2.5 s)
        │
   ┌────┴─────┐
   │ Per-window│
   └────┬─────┘
        │
        ▼
Extract 418 features
(AudioFeatures.extractFeatures)
        │
        ▼
┌───────────────────────┐
│    OOD Gate (RF)      │
│  P(OOD) ≥ 0.75?      │
└───────┬───────────────┘
   YES  │   NO
        │    │
   REJECT    ▼
        │  ┌──────────────────────────┐
        │  │  Fault Classifier (RF)   │
        │  │  confidence ≥ 0.60?      │
        │  └──────┬───────────────────┘
        │    NO   │   YES
        │         │    │
        │    REJECT    ▼
        │         │  Record WindowResult
        │         │  (label + confidence)
        ▼         ▼
     Collect all results
        │
        ▼
Aggregate: majority label
with highest avg confidence
        │
        ▼
Lookup engine_knowledge_base.json
        │
        ▼
Display ResultScreen
(fault · severity · repair steps · cost)
```

---

### Feature Extraction Pipeline

```
Raw audio (float32, [-1,1])
         │
         ▼
  Reflect-pad 1024 samples each side
  (matches librosa center=True)
         │
    ┌────┴──────────────────────────┐
    │                               │
    ▼                               ▼
 STFT (n_fft=2048,            Magnitude spectrogram
 hop=512) → Power spec        (no padding, for spectral
                               & temporal features)
    │
    ▼
Mel Filterbank (128 bins)
    │
    ├──► log-Mel (power_to_dB) ──► DCT-II ──► 40 MFCCs
    │         │                         │
    │         ▼                         ├──► Δ MFCCs
    │   Mel sub-band stats              └──► ΔΔ MFCCs
    │   (16 sub-bands × 8 bins)
    │
    └──► PCEN normalization ──► sub-band stats
         (gain=0.98, bias=2,
          power=0.5, tc=0.4s)

Magnitude spectrogram ──► Spectral Centroid
                      ──► Spectral Bandwidth
                      ──► Spectral Rolloff (85%)
                      ──► Spectral Flatness
                      ──► Spectral Contrast (7 bands)
                      ──► Zero Crossing Rate
                      ──► RMS Energy
                      ──► Tempo (onset autocorrelation)
                      ──► Harmonic Ratio (F0, even/odd)

All features concatenated → 418-dim float32 vector
```

---

### Inference Pipeline (Dual-Gate)

```
418-feature vector
        │
        ▼
StandardScaler (OOD scaler)
        │
        ▼
┌────────────────────────────────┐
│  OOD Random Forest             │
│  300 trees · 2 classes         │
│  (in-distribution vs OOD)      │
└──────────────┬─────────────────┘
               │
    P(OOD) ≥ 0.75?
       │              │
      YES             NO
       │              │
  WindowRejection     ▼
  (oodGate)    StandardScaler
               (fault scaler)
                      │
                      ▼
         ┌────────────────────────────┐
         │  Fault Random Forest       │
         │  300 trees · 12 classes    │
         └──────────────┬─────────────┘
                        │
           confidence ≥ 0.60?
                │              │
               YES             NO
                │              │
           WindowResult   WindowRejection
           (label,conf)   (lowConfidence)
```

---

### Data Preparation Pipeline

```
Raw Dataset Directories
┌──────────────────────────────────────────┐
│  engine-sounds/Data/Data_Fixed           │  ← 11 fault classes
│  engine-sounds/Data_AA/.../Normal        │  ← 1,020 normal recordings
│  engine-sounds/M_DATA/M_DATA            │  ← additional fault data
│  OOD_AA/OOD_AA/                         │  ← 11 OOD categories
└──────────────────────┬───────────────────┘
                       │
                       ▼
          collect_files() + normalize folder names
          (fix typos: "Engine kanocking" → "Engine Knocking")
                       │
                       ▼
          Encode labels (LabelEncoder, alphabetical)
                       │
                       ▼
          StratifiedShuffleSplit (80% train / 20% test)
          random_state=42
                       │
            ┌──────────┴──────────┐
            │                     │
           TRAIN                 TEST
            │              (frozen, never touched)
            ▼
          Oversample minority classes
          (duplicate to match majority count)
            │
            ▼
          extract_all_features() per file
          (418-dim vector, nan_to_num)
            │
            ▼
          Pipeline.fit(X_train, y_train)
          StandardScaler + RandomForestClassifier
            │
            ▼
          Evaluate on TEST set
            │
            ▼
          rf_to_json() → random_forest_v1.json
          (trees + scaler embedded)
            │
            ▼
          JSON parity check (Python re-impl vs sklearn)
          tolerance < 1e-6, zero class mismatches
```

---

## Dataset

The training data is sourced from Kaggle. You need three dataset directories:

| Kaggle Path | Contents | Label |
|------------|---------|-------|
| `engine-sounds/Data/Data_Fixed` | 11 engine fault classes, one subfolder per class | In-distribution (label 0) |
| `engine-sounds/Data_AA/Data_Fixed/Normal` | 1,020 real normal engine recordings | In-distribution (label 0) |
| `engine-sounds/M_DATA/M_DATA` | Additional fault recordings | In-distribution (label 0) |
| `OOD_AA/OOD_AA` | 11 environmental sound categories | OOD (label 1) |

**🔗 Dataset Link:** https://www.kaggle.com/datasets/zeyadzsm/engine-sounds

> **Important dataset rules:**
> - Do **not** use synthetic audio for the Normal Healthy Engine class — only the 1,020 real recordings.
> - The train/test split must happen **before** oversampling. Oversampling only goes into the training set.
> - The test set must remain original, unaugmented recordings.

### OOD Categories (for the OOD Gate)

The OOD Gate was trained to reject these environmental sounds:

`Birds` · `Cats` · `Dogs` · `Door` · `Footsteps` · `Rain` · `Silence` · `Sirens` · `Thunder` · `Traffic` · `Wind`

**🔗 ESC-50 Dataset (OOD sounds):** https://github.com/karolpiczak/ESC-50

---

## Requirements & Dependencies

### Python Training Environment

**Python version:** 3.8 or higher recommended

Install all dependencies:

```bash
pip install -r requirements.txt
```

**`requirements.txt`:**

```
librosa>=0.10.0
numpy>=1.24.0
scikit-learn>=1.3.0
matplotlib>=3.7.0
seaborn>=0.12.0
joblib>=1.3.0
tqdm>=4.65.0
opencv-python>=4.8.0
ipykernel>=6.25.0
jupyter>=1.0.0
```

| Library | Version | Role |
|---------|---------|------|
| `librosa` | ≥ 0.10.0 | Audio loading, STFT, MFCCs, mel filterbank |
| `numpy` | ≥ 1.24.0 | Array operations, feature math |
| `scikit-learn` | ≥ 1.3.0 | StandardScaler, RandomForestClassifier, metrics |
| `matplotlib` | ≥ 3.7.0 | Confusion matrix, plots |
| `seaborn` | ≥ 0.12.0 | Heatmap visualizations |
| `joblib` | ≥ 1.3.0 | Parallel processing during training |
| `tqdm` | ≥ 4.65.0 | Progress bars during batch feature extraction |
| `opencv-python` | ≥ 4.8.0 | Image processing (OOD gate support) |
| `json` / `pickle` | stdlib | Model serialization |

---

### Flutter Mobile App

**Flutter version:** 3.10.0 or higher  
**Dart version:** 3.0.0 or higher  
**Target platforms:** Android · iOS

**`pubspec.yaml` dependencies:**

```yaml
dependencies:
  flutter:
    sdk: flutter
  ffmpeg_kit_flutter_new: ^6.0.3    # Audio format conversion
  file_picker: ^6.1.1               # System file picker
  # All ML inference is native Dart — no TFLite needed
```

| Package | Role |
|---------|------|
| `ffmpeg_kit_flutter_new` | Converts MP3/M4A/AAC/OGG → WAV 22050 Hz mono |
| `file_picker` | Cross-platform file selection dialog |
| Native Dart | Custom Random Forest inference (no TFLite, no Python runtime) |

**Flutter assets** (add to `pubspec.yaml`):

```yaml
flutter:
  assets:
    - assets/random_forest_v1.json       # Fault classifier (300 trees + scaler)
    - assets/ood_gate_rf_v1.json         # OOD gate (300 trees + scaler)
    - assets/config.json                  # Thresholds and runtime config
    - assets/class_names.json             # Index-to-class-name mapping
    - assets/engine_knowledge_base.json   # Fault descriptions for UI
    - assets/ood_gate_config.json         # OOD gate config and metrics
```

---

## Project Structure

```
engine-fault-detection/
│
├── training/                          # Python training notebooks & scripts
│   ├── fault_classifier.ipynb         # Main classifier training notebook
│   ├── ood_gate.ipynb                 # OOD gate training notebook
│   └── requirements.txt               # Python dependencies
│
├── app5/                              # Flutter application root
│   ├── pubspec.yaml
│   ├── assets/
│   │   ├── config.json                # Thresholds and model config
│   │   ├── engine_knowledge_base.json # Fault class details (severity, repair, cost)
│   │   ├── ood_gate_config.json       # OOD gate config and metrics
│   │   ├── ood_gate_rf_v1.json        # OOD Random Forest (300 trees, JSON)
│   │   ├── random_forest_v1.json      # Fault RF (300 trees, JSON)
│   │   └── class_names.json           # Index-to-class-name mapping
│   │
│   └── lib/
│       ├── main.dart                  # App entry point
│       ├── models/
│       │   └── engine_result.dart     # EngineResult, FaultDetail, WindowResult
│       ├── screens/
│       │   ├── about_screen.dart
│       │   ├── dashboard_screen.dart  # Main interaction screen
│       │   ├── history_screen.dart
│       │   ├── onboarding_screen.dart
│       │   ├── result_screen.dart     # Diagnosis results display
│       │   ├── settings_screen.dart
│       │   └── splash_screen.dart
│       ├── services/
│       │   ├── audio_features.dart    # 418-feature DSP extraction (pure Dart)
│       │   ├── audio_file_service.dart # File I/O, FFmpegKit, WAV decoding
│       │   ├── history_service.dart   # In-memory session history
│       │   └── inference_service.dart # RF inference + OOD gate logic
│       ├── theme/
│       │   └── app_theme.dart         # Colors and ThemeData
│       └── widgets/
│           ├── app_drawer.dart
│           ├── map_background.dart
│           ├── power_button.dart
│           └── status_card.dart
│
└── README.md
```

---

## Model Details

### Fault Classifier

| Parameter | Value |
|-----------|-------|
| Model type | Random Forest |
| Trees | 300 |
| Input features | 418 |
| Output classes | 12 |
| Confidence threshold | 0.60 |
| Test accuracy | **93.28%** |
| OOB score | 99.14% |
| Min samples to split | 5 |
| Min samples per leaf | 2 |
| Max features per split | sqrt(418) ≈ 20 |
| Class weight | balanced |

### OOD Gate

| Parameter | Value |
|-----------|-------|
| Model type | Random Forest (binary) |
| Trees | 300 |
| Input features | 418 |
| Output classes | 2 (in-dist / OOD) |
| OOD threshold | 0.75 |
| Test accuracy | **99.77%** |
| OOB score | 99.82% |
| ROC AUC | 1.000 |
| OOD recall at threshold | **100.0%** |
| False rejection rate | **0.42%** |

### Feature Vector (418 dimensions)

| Index Range | Feature Group | Count |
|------------|--------------|-------|
| 0 – 159 | MFCC mean, std, max, min (40 coefficients × 4 stats) | 160 |
| 160 – 239 | MFCC delta mean, std (40 × 2) | 80 |
| 240 – 319 | MFCC delta-delta mean, std (40 × 2) | 80 |
| 320 – 323 | Spectral centroid mean, std, max, min | 4 |
| 324 – 325 | Spectral bandwidth mean, std | 2 |
| 326 – 327 | Spectral rolloff mean, std | 2 |
| 328 – 329 | Spectral flatness mean, std | 2 |
| 330 – 343 | Spectral contrast mean × 7 + std × 7 | 14 |
| 344 – 345 | Zero-crossing rate mean, std | 2 |
| 346 – 348 | RMS energy mean, std, max | 3 |
| 349 | Tempo BPM (onset autocorrelation) | 1 |
| 350 – 413 | Mel sub-band PCEN + log-dB stats (16 bands × 4) | 64 |
| 414 – 417 | Harmonic ratio: log_ratio, even_energy, odd_energy, f0_mean | 4 |
| **Total** | | **418** |

#### Audio Processing Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `SR` | 22050 Hz | Sample rate |
| `DURATION` | 5 s | Window length |
| `TARGET_LEN` | 110,250 samples | SR × DURATION |
| `N_MELS` | 128 | Mel filterbank bins |
| `HOP_LENGTH` | 512 | STFT hop size |
| `N_MFCC` | 40 | MFCC coefficients |
| `N_FFT` | 2048 | FFT window size |
| Window step | 2.5 s | 50% overlap |
| Max recording | 60 s | Maximum input length |
| `RANDOM_STATE` | 42 | Reproducibility seed |
| `TEST_SIZE` | 0.20 | 80/20 train-test split |

####  Critical Dart-vs-Python Alignment Fixes

The `AudioFeatures` Dart class implements five specific fixes to match librosa's Python behavior exactly. If you modify the feature extractor, these must be preserved:

| Fix | What It Addresses |
|-----|------------------|
| **FIX-1** | STFT centering: reflect-pad audio by `n_fft // 2` (1024 samples) before STFT — matches librosa `center=True` |
| **FIX-2** | Mel filterbank uses **power spectrogram** (magnitude²), not magnitude — matches librosa `melspectrogram` default |
| **FIX-3** | MFCC log compression uses `10 × log10(power + 1e-10)` — matches `librosa.power_to_db(ref=1.0)` |
| **FIX-4** | Spectral contrast quantile is `0.02`, not `0.20` — matches librosa default |
| **FIX-5** | Tempo uses mean of positive frame differences in power-to-dB mel — matches `librosa.onset.onset_strength` |

---

## Performance Results

### Fault Classifier

| Metric | Value |
|--------|-------|
| Test Accuracy | **93.28%** |
| OOB Score | 99.14% |

**Per-class targets (checked at evaluation):**

| Class | Metric | Target | Min Acceptable |
|-------|--------|--------|----------------|
| Normal Healthy Engine | Recall | 95% | 90% |
| Crankshaft Bearing Noise | Recall | 80% | 70% |
| Timing Belt Noise | F1-Score | 80% | 72% |
| Worn Pulley Noise | F1-Score | 80% | 72% |

### OOD Gate

| Metric | Value |
|--------|-------|
| Test Accuracy | **99.77%** |
| OOB Score | 99.82% |
| ROC AUC | **1.000** |
| OOD Recall @ threshold 0.75 | **100.0%** |
| False Rejection Rate | **0.42%** |

### Output Files from Training

| File | Content |
|------|---------|
| `random_forest_v1.json` | Serialized fault model (2–8 MB target) |
| `ood_gate_rf_v1.json` | Serialized OOD gate model |
| `class_names.json` | Index-to-class-name dictionary |
| `config.json` | Runtime thresholds and metadata |
| `confusion_matrix_rf_v1.png` | 12×12 normalized confusion matrix |
| `confidence_analysis_rf_v1.png` | Confidence histogram + accuracy/rejection curve |
| `feature_importances_rf_v1.png` | Top 30 features by RF importance |
| `ood_gate_confusion_roc.png` | OOD confusion matrix and ROC curve |
| `ood_gate_threshold_sweep.png` | OOD threshold sensitivity analysis |
| `label_encoder_rf_v1.pkl` | Saved LabelEncoder (training use only) |

---

## Knowledge Base

The file `engine_knowledge_base.json` stores structured expert knowledge for each fault class. Each entry contains:

- `fault_name` — identifier
- `description` — what is physically happening
- `severity` — Critical / High / Medium / Low / Safe
- `priority` — integer 0 (healthy) to 4 (low priority)
- `safe_to_drive` — boolean
- `driving_instruction` — immediate driver action
- `possible_causes` — root cause candidates
- `recommended_actions` — ordered immediate steps
- `risks_if_ignored` — consequences of delay
- `repair_cost_min` / `repair_cost_max` — estimated cost range (Egyptian Pounds)
- `urgency_hours` — hours before fault becomes critical (0 = stop immediately)
- `mechanic_description` — expert narrative
- `sound_analysis` — detailed acoustic description
- `repair_steps` — full ordered repair procedure

### Severity Framework

| Severity | Priority | Urgency | Safe to Drive |
|----------|----------|---------|---------------|
| Critical | 1 | 0 hours (stop now) |  No |
| High | 2 | 0 – 48 hours |  Restricted |
| Medium | 3 | 72 – 168 hours | Short trips |
| Low | 4 | Up to 336 hours |  Yes |
| Safe | 0 | None |  Yes |

---

## App Screens

| Screen | Purpose |
|--------|---------|
| `SplashScreen` | Launch animation |
| `OnboardingScreen` | Welcome screen, swipe-up to enter |
| `DashboardScreen` | Main screen — recording tips + file picker button |
| `ResultScreen` | Diagnosis hero card with per-window breakdown |
| `HistoryScreen` | Past sessions in reverse chronological order |
| `SettingsScreen` | Duration slider, toggles, model info |
| `AboutScreen` | App version and feature highlights |

### UI Color Palette

| Token | Hex | Usage |
|-------|-----|-------|
| amber | `#FFC107` | Primary brand, buttons, icons |
| darkBg | `#1A1A2E` | Background |
| darkCard | `#1E2A3A` | Card surfaces |
| good | `#4CAF50` | Healthy status |
| faulty | `#E53935` | Fault detected |
| warning | `#FF9800` | Minor anomaly |
| textSecondary | `#B0BEC5` | Descriptive text |
| textMuted | `#607D8B` | Timestamps and labels |

Font: **Poppins** throughout.

---

## Running the Project

### 1. Training the Models (Python)

**Step 1: Set up the environment**

```bash
# Clone the repository
git clone <your-repo-url>
cd engine-fault-detection/training

# Create and activate a virtual environment (recommended)
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate         # Windows

# Install dependencies
pip install -r requirements.txt
```

**Step 2: Download the datasets**

Download the engine fault dataset and OOD dataset from Kaggle and place them at the paths referenced in the notebooks:

```
datasets/
├── engine-sounds/
│   ├── Data/Data_Fixed/          ← fault classes
│   ├── Data_AA/Data_Fixed/Normal ← normal engine
│   └── M_DATA/M_DATA/            ← additional fault data
└── OOD_AA/OOD_AA/                ← environmental sounds
```

**Step 3: Train the Fault Classifier**

```bash
jupyter notebook fault_classifier.ipynb
# Run all cells top to bottom.
# Output: random_forest_v1.json, class_names.json, config.json
```

**Step 4: Train the OOD Gate**

```bash
jupyter notebook ood_gate.ipynb
# Run all cells top to bottom.
# Output: ood_gate_rf_v1.json, ood_gate_config.json
```

**Step 5: Verify JSON parity**

The notebooks include a verification step that runs automatically. Look for the output:

```
 JSON parity verified: 0 class mismatches, max prob diff < 1e-6
```

**Step 6: Copy model files to Flutter assets**

```bash
cp random_forest_v1.json  ../app5/assets/
cp ood_gate_rf_v1.json    ../app5/assets/
cp class_names.json       ../app5/assets/
cp config.json            ../app5/assets/
cp ood_gate_config.json   ../app5/assets/
```

---

### 2. Running the Flutter App

**Prerequisites:**
- Flutter SDK ≥ 3.10.0 installed: https://flutter.dev/docs/get-started/install
- Android Studio (for Android) or Xcode (for iOS)
- A physical device or emulator

**Step 1: Install Flutter dependencies**

```bash
cd app5
flutter pub get
```

**Step 2: Verify setup**

```bash
flutter doctor
```

Ensure Android SDK or iOS toolchain shows no issues.

**Step 3: Run the app**

```bash
# On a connected Android/iOS device or emulator:
flutter run

# Build a release APK for Android:
flutter build apk --release

# Build for iOS:
flutter build ios --release
```

> **Note:** FFmpegKit requires a real device or emulator with audio capabilities. Some emulators may not support audio file conversion.

---

## Audio Recording Guidelines

For best classification accuracy:

1. **Record close to the engine** — ideally 10–30 cm from the engine block
2. **Engine at idle** — avoid revving during recording
3. **Avoid background noise** — turn off radio, air conditioning fan, etc.
4. **Recording duration** — 10–20 seconds works best (multiple windows for averaging)
5. **Maximum duration** — 60 seconds
6. **Minimum sample rate** — 22,050 Hz (most phones record at 44,100 Hz — that's fine, FFmpegKit downsamples automatically)
7. **Supported formats** — WAV, MP3, M4A, AAC, OGG

---

## Constants Reference

| Constant | Value | Purpose |
|----------|-------|---------|
| `SR` | 22050 | Audio sample rate (Hz) |
| `DURATION` | 5 | Audio clip length (seconds) |
| `TARGET_LEN` | 110,250 | Samples per clip |
| `N_MELS` | 128 | Mel filterbank bins |
| `HOP_LENGTH` | 512 | STFT hop length |
| `N_MFCC` | 40 | MFCC coefficients |
| `N_FFT` | 2048 | FFT window size |
| `WINDOW_STEP` | 2.5 s | Sliding window step |
| `OOD_THRESHOLD` | 0.75 | OOD gate rejection threshold |
| `CONFIDENCE_THRESHOLD` | 0.60 | Fault classifier acceptance threshold |
| `N_ESTIMATORS` | 300 | Random Forest trees |
| `RANDOM_STATE` | 42 | Reproducibility seed |
| `TEST_SIZE` | 0.20 | Train/test split ratio |
| `PCEN_GAIN` | 0.98 | PCEN normalization gain |
| `PCEN_BIAS` | 2.0 | PCEN bias |
| `PCEN_POWER` | 0.5 | PCEN power |
| `PCEN_TIME_CONSTANT` | 0.4 s | PCEN EMA time constant |

---

## Fault Priority & Severity Reference

| Priority | Fault | Severity | Stop Immediately? | Estimated Cost (EGP) |
|----------|-------|----------|-------------------|----------------------|
| 1 | Crankshaft Bearing Noise | Critical |  Yes | 8,000 – 25,000 |
| 1 | Rod Knock | Critical |  Yes | 6,000 – 20,000 |
| 2 | Piston Slap | High | No (restrict) | 4,000 – 15,000 |
| 2 | Engine Knocking | High | No (restrict) | 500 – 5,000 |
| 2 | Alternator Bearing Noise | High | No (short trips) | 800 – 3,000 |
| 2 | Timing Belt Noise | High |  Yes (do not drive) | 1,500 – 4,000 |
| 3 | Exhaust Leak | Medium | No (windows open) | 300 – 2,000 |
| 3 | Valve Tapping | Medium | No (short trips) | 500 – 3,500 |
| 3 | Chain Noise | Medium | No (limit trips) | 1,000 – 4,000 |
| 4 | Vacuum Leak | Low | No | 200 – 1,000 |
| 4 | Worn Pulley Noise | Low | No (short trips) | 400 – 1,500 |
| 0 | Normal Healthy Engine | Safe | N/A | 0 |

---

*Engine Fault Detection System — Graduation Project*
