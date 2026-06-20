# Engine Fault Detection Random Forest v1

## Notebook Overview


This notebook trains the 12-class engine fault classification Random Forest model and exports `random_forest_v1.json`.



Both notebooks were authored and run on **Kaggle Notebooks** They can also be run locally or on Google Colab with paths adjusted.

| Notebook | Python Version (per kernel metadata) |
|---|---|
| `Engine_Fault_Detection_Random_Forest_v1.ipynb` | Python 3.12.13 |
| `OOD_Gate_Random_Forest_v1.ipynb` | Python 3.10.0 |

> Both are compatible with any modern **Python 3.10–3.12** environment with the packages below installed.




| Package | Used For | Suggested Install |
|---|---|---|
| `numpy` | Numerical array operations, feature vectors | `pip install numpy` |
| `librosa` | Audio loading + MFCC/spectral feature extraction (the reference implementation the Dart code mirrors) | `pip install librosa` |
| `scikit-learn` (`sklearn`) | `RandomForestClassifier`, `StandardScaler`, `LabelEncoder`, `Pipeline`, `StratifiedShuffleSplit`, metrics (`recall_score`, `f1_score`, etc.) | `pip install scikit-learn` |
| `opencv-python` (`cv2`) | Image-related preprocessing (e.g., spectrogram/array resizing utilities) | `pip install opencv-python` |
| `matplotlib` | Plotting (training curves, confusion matrices, spectrograms) | `pip install matplotlib` |
| `seaborn` | Statistical plotting (heatmaps for confusion matrices, etc.) | `pip install seaborn` |
| `joblib` | `Parallel`/`delayed` for multi-process feature extraction across the dataset | `pip install joblib` |
| `tqdm` | Progress bars (`tqdm.auto`) during dataset processing | `pip install tqdm` |
| `pickle` | Saving the `LabelEncoder` objects (Python standard library — no install needed) | Built-in |
| `json` | Reading/writing model & config JSON (Python standard library) | Built-in |
| `pathlib`, `os`, `time`, `warnings`, `collections` | Standard library utilities | Built-in |

### 3.2 Suggested `requirements.txt` for the Notebooks

```text
numpy
librosa
scikit-learn
opencv-python
matplotlib
seaborn
joblib
tqdm
```

Install with:
```bash
pip install -r requirements.txt
```

### 3.3 Additional System Dependencies for `librosa`

`librosa` relies on `soundfile`/`audioread` under the hood for decoding audio files, which may require:
- **`libsndfile`** (usually auto-installed as a dependency of `soundfile` via pip wheels on most platforms)
- **`ffmpeg`** installed on the system PATH as a fallback decoder for formats `soundfile` can't handle directly (recommended for robustness, especially for `.mp3`/compressed formats)

On Kaggle/Colab these are pre-installed in the base image. For local use:
```bash
# Debian/Ubuntu
sudo apt-get install ffmpeg libsndfile1

# macOS (Homebrew)
brew install ffmpeg libsndfile
```

### 3.4 Dataset Requirements

The notebooks expect a Kaggle dataset mounted at:
```
/kaggle/input/datasets/zeyadzsm/engine-sounds/
├── Data/Data_Fixed/            (fault-labeled engine sound clips)
├── Data_AA/Data_Fixed/         (normal/augmented engine sound clips)
├── M_DATA/M_DATA/              (additional metadata/clips)
└── OOD_AA/OOD_AA/              (out-of-distribution sounds: Birds, Cats, Dogs, Door, Footsteps, Rain, Silence, Sirens, Thunder, Traffic, Wind)
```

To run the notebooks outside Kaggle, this dataset (`zeyadzsm/engine-sounds` on Kaggle) must be downloaded and the `BASE_FAULT`, `BASE_NORM`, `BASE_MDATA`, `BASE_OOD` path variables in each notebook updated to match the local directory structure.

### 3.5 Hardware Notes

- Training uses `RandomForestClassifier(n_estimators=300, n_jobs=-1, ...)` — benefits from **multiple CPU cores** (no GPU required).
- `oob_score=True` and `verbose=1` are enabled, so console output will show out-of-bag scoring progress.
- No deep learning framework (TensorFlow/PyTorch) is used anywhere in the pipeline — this is a classical ML (scikit-learn) project end-to-end.


1. Training a `Pipeline(StandardScaler → RandomForestClassifier)`.
2. Serializing the fitted pipeline into a flat JSON structure (`rf_to_json()` function) containing per-tree `children_left/right`, `feature`, `threshold`, `value` arrays plus the scaler's `mean`/`scale`, so it can be loaded and executed **without scikit-learn or Python at inference time** — directly in Dart.
3. Saving a companion `config.json` (or `ood_gate_config.json`) with thresholds and metadata, and a `class_names.json` mapping.
4. Pickling the `LabelEncoder` (`.pkl`) for reference within the Python environment (not used by the Flutter app).

You only need to re-run these notebooks if you intend to **retrain the models** with new data; the production JSON artifacts are already present in `app6/assets/`.

---

## 4. Summary Checklist

### To run the Flutter app (`app6/`):
- [ ] Flutter SDK ≥ 3.12.2 (includes Dart)
- [ ] Android Studio + Android SDK (Platform 36, Build Tools, NDK)
- [ ] JDK 17
- [ ] Android device/emulator running Android 7.0+ (API 24+) with microphone
- [ ] Run `flutter pub get` (internet required to fetch `pub.dev` packages)
- [ ] Edit `android/local.properties` to point to your local Flutter SDK and Android SDK paths

### To retrain models (optional, Python notebooks):
- [ ] Python 3.10–3.12
- [ ] `numpy`, `librosa`, `scikit-learn`, `opencv-python`, `matplotlib`, `seaborn`, `joblib`, `tqdm`
- [ ] `ffmpeg` + `libsndfile` system libraries (for audio decoding support)
- [ ] Access to the `zeyadzsm/engine-sounds` Kaggle dataset (or equivalent local copy)
- [ ] Multi-core CPU recommended (no GPU needed)

---

## 5. Key Design Notes (Why Dependencies Are Minimal at Runtime)

- **No ML runtime (TFLite/ONNX/PyTorch Mobile) is needed in the shipped app** — both Random Forest models are hand-decoded from JSON and evaluated with plain Dart arithmetic (`lib/services/inference_service.dart`), tree-by-tree, vote-averaging across estimators.
- **No native audio DSP library is needed either** — the entire MFCC/spectral/mel feature pipeline (418-dimensional feature vector matching the Python `librosa`-based training pipeline) is reimplemented from scratch in Dart (`lib/services/audio_features.dart`), including manual FFT, mel filterbank, MFCC, delta/delta-delta, spectral centroid/bandwidth/rolloff/flatness/contrast, ZCR, RMS, tempo estimation, and harmonic ratio — all to byte-for-byte mirror the Python notebook's feature extraction so the exported model weights remain valid.
- **`ffmpeg_kit_flutter_new`** is the one heavyweight native dependency in the app, used solely to normalize/transcode arbitrary input audio files before they're handed to the pure-Dart feature extractor.