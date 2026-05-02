import 'dart:io';
import 'dart:typed_data';

/// Minimum size for a valid PCM recording (~0.5 s @ 16 kHz mono 16-bit).
/// Anything smaller is rejected as a corrupt/empty recording.
const int kMinPcmFileBytes = 16000;

/// Standard WAV header size (RIFF + fmt + data chunks).
const int kWavHeaderBytes = 44;

/// Reads a PCM 16-bit linear-encoded recording from disk and returns the
/// raw little-endian Int16 samples.
///
/// The `record` package's [AudioEncoder.pcm16bits] typically writes raw PCM
/// without any container, but a few Android OEMs may emit a WAV-wrapped
/// file. This reader handles both transparently:
///
///   - If the first 4 bytes are `RIFF` (0x52 0x49 0x46 0x46), skip the
///     standard 44-byte WAV header.
///   - Otherwise, treat all bytes as raw little-endian Int16 samples.
///
/// Throws [ArgumentError] if:
///   - the file does not exist
///   - the file is smaller than [kMinPcmFileBytes]
///   - the PCM byte count after header skip is not 2-byte aligned
///
/// We use [ByteData.getInt16] in a loop instead of
/// `bytes.buffer.asInt16List(...)` because [File.readAsBytes] does not
/// guarantee a 2-byte aligned underlying buffer, and `asInt16List` would
/// throw on misaligned input.
Future<Int16List> readPcm16k(File file) async {
  if (!await file.exists()) {
    throw ArgumentError('PCM file does not exist: ${file.path}');
  }

  final bytes = await file.readAsBytes();
  if (bytes.length < kMinPcmFileBytes) {
    throw ArgumentError(
      'PCM file too small (${bytes.length} bytes, need >= $kMinPcmFileBytes). '
      'Recording is probably empty.',
    );
  }

  // Detect WAV header (magic "RIFF" at offset 0).
  int offset = 0;
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46) {
    // F
    offset = kWavHeaderBytes;
  }

  final pcmByteCount = bytes.length - offset;
  if (pcmByteCount.isOdd) {
    throw ArgumentError(
      'PCM byte count $pcmByteCount is not 2-byte aligned',
    );
  }

  final samples = Int16List(pcmByteCount ~/ 2);
  final bd = ByteData.sublistView(bytes, offset);
  for (int i = 0; i < samples.length; i++) {
    samples[i] = bd.getInt16(i * 2, Endian.little);
  }
  return samples;
}
