import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Audio pipeline parameters for the Wespeaker ResNet34-LM voiceprint model.
///
/// These match (within 1-2%) the librosa defaults that Wespeaker training
/// uses for log-mel filterbank features:
///
///   librosa.feature.melspectrogram(
///     y=audio, sr=16000, n_fft=512, hop_length=160,
///     win_length=400, window='hamming', n_mels=80,
///     fmin=0.0, fmax=8000.0, power=2.0,
///   )
///
/// Differences from the librosa equivalent we accept here:
///   - win_length: librosa uses 400 (25 ms) zero-padded to 512. fftea's STFT
///     applies the window over the full chunkSize, so we use Window.hamming(512).
///     Slight (~1%) difference in feature distribution.
///   - htk vs slaney mel scale: we use the HTK formula (2595 * log10(1 + f/700))
///     which matches Wespeaker's default Kaldi-style features.
const int kSampleRate = 16000;
const int kNFft = 512;
const int kFrameStride = 160; // 10 ms hop
const int kNMel = 80;
const double kMelLowHz = 0.0;
const double kMelHighHz = 8000.0; // Nyquist
const double kPreEmphasis = 0.97;
const double kLogEpsilon = 1e-6;
const int kMinPcmSamples = kSampleRate; // 1 second minimum

/// Precomputed mel filterbank + STFT pipeline.
///
/// Construct once and reuse across calls — the filterbank matrix and the
/// STFT's twiddle factors are expensive to build.
class MelFilterbank {
  /// 80 triangular mel filters, each Float64List of length nBins (257).
  final List<Float64List> _filters;
  final STFT _stft;

  MelFilterbank()
      : _stft = STFT(kNFft, Window.hamming(kNFft)),
        _filters = _buildFilters();

  static double _hzToMel(double hz) =>
      2595.0 * (math.log(1 + hz / 700) / math.ln10);

  static double _melToHz(double mel) =>
      700.0 * (math.pow(10, mel / 2595) - 1);

  static List<Float64List> _buildFilters() {
    final nBins = kNFft ~/ 2 + 1; // 257
    final melLow = _hzToMel(kMelLowHz);
    final melHigh = _hzToMel(kMelHighHz);

    // 82 mel points: 80 filter centers + 2 boundaries.
    final melPoints = List<double>.generate(
      kNMel + 2,
      (i) => melLow + (melHigh - melLow) * i / (kNMel + 1),
    );
    final hzPoints = melPoints.map(_melToHz).toList();

    // Continuous bin position (kept fractional, not rounded).
    // Same formula as librosa: (n_fft + 1) * hz / sr is for one-sided
    // spectrum without the "+1" — librosa uses sr/2 and nBins. We use the
    // bin index = hz * n_fft / sr (matches Kaldi/Wespeaker convention).
    final binPoints =
        hzPoints.map((hz) => hz * kNFft / kSampleRate).toList();

    final filters = List<Float64List>.generate(kNMel, (m) {
      final filter = Float64List(nBins);
      final left = binPoints[m];
      final center = binPoints[m + 1];
      final right = binPoints[m + 2];

      for (int k = 0; k < nBins; k++) {
        if (k <= left || k >= right) continue;
        if (k <= center) {
          filter[k] = (k - left) / (center - left);
        } else {
          filter[k] = (right - k) / (right - center);
        }
      }
      return filter;
    });
    return filters;
  }

  /// Extracts the log-mel filterbank from PCM 16 kHz mono audio.
  ///
  /// Returns a Float32List shape [80, T] in row-major layout: index
  /// `m * T + t` holds the value for mel bin `m` at time frame `t`.
  ///
  /// Throws [ArgumentError] if the audio is shorter than [kMinPcmSamples]
  /// (1 second @ 16 kHz).
  Float32List extract(Int16List pcm16k) {
    if (pcm16k.length < kMinPcmSamples) {
      throw ArgumentError(
        'PCM must be at least $kMinPcmSamples samples '
        '(${kMinPcmSamples ~/ kSampleRate}s @ ${kSampleRate}Hz). '
        'Got ${pcm16k.length}.',
      );
    }

    // 1. Int16 → Float64 normalized to [-1, 1).
    final samples = Float64List(pcm16k.length);
    for (int i = 0; i < pcm16k.length; i++) {
      samples[i] = pcm16k[i] / 32768.0;
    }

    // 2. Pre-emphasis: y[n] = x[n] - 0.97 * x[n-1].
    // Iterate in reverse so we read the unmodified previous sample.
    for (int i = samples.length - 1; i > 0; i--) {
      samples[i] = samples[i] - kPreEmphasis * samples[i - 1];
    }

    // 3. STFT → power spectrum per frame.
    final powerFrames = <Float64List>[];
    _stft.run(samples, (Float64x2List freq) {
      final mags = freq.discardConjugates().magnitudes();
      // 4. Square magnitudes for power spectrum (librosa power=2.0).
      for (int i = 0; i < mags.length; i++) {
        mags[i] = mags[i] * mags[i];
      }
      powerFrames.add(mags);
    }, kFrameStride);

    if (powerFrames.isEmpty) {
      throw StateError(
        'STFT produced 0 frames for ${pcm16k.length} samples. This indicates '
        'a mismatch between input length and FFT chunk size.',
      );
    }

    final t = powerFrames.length;

    // 5. Mel filterbank multiplication: filters [80, 257] × power [257, T].
    // Inner loop is the hot path (4M ops for ~2 s audio). Local variables
    // help the VM optimize.
    final melFrames = List<Float64List>.generate(t, (_) => Float64List(kNMel));
    for (int frame = 0; frame < t; frame++) {
      final power = powerFrames[frame];
      final melFrame = melFrames[frame];
      for (int m = 0; m < kNMel; m++) {
        final filter = _filters[m];
        double acc = 0;
        for (int k = 0; k < filter.length; k++) {
          acc += power[k] * filter[k];
        }
        melFrame[m] = acc;
      }
    }

    // 6. Log: log(mel + epsilon).
    for (int frame = 0; frame < t; frame++) {
      final melFrame = melFrames[frame];
      for (int m = 0; m < kNMel; m++) {
        melFrame[m] = math.log(melFrame[m] + kLogEpsilon);
      }
    }

    // 7. Flatten to [80, T] row-major (mel-bin first, then time). This is
    // the layout Wespeaker's TFLite (NWC) input expects after onnx2tf
    // transposition.
    final out = Float32List(kNMel * t);
    for (int m = 0; m < kNMel; m++) {
      for (int frame = 0; frame < t; frame++) {
        out[m * t + frame] = melFrames[frame][m];
      }
    }
    return out;
  }

  /// Estimates the number of STFT frames produced for [nSamples] of input.
  /// Useful when callers need to size the TFLite input tensor before invoke.
  int framesForInputLength(int nSamples) {
    if (nSamples < kNFft) return 0;
    return ((nSamples - kNFft) ~/ kFrameStride) + 1;
  }
}
