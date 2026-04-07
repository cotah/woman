/**
 * Result of a speech-to-text transcription.
 */
export interface TranscriptionResult {
  text: string;
  confidence: number;
  language: string;
  words?: Array<{
    word: string;
    start: number;
    end: number;
    confidence: number;
  }>;
}

/**
 * Result of AI-based distress classification on a transcript.
 */
export interface DistressClassificationResult {
  isDistress: boolean;
  confidence: number;
  riskLevel: 'none' | 'low' | 'medium' | 'high' | 'critical';
  signals: DistressSignal[];
  summary: string;
}

export interface DistressSignal {
  type: string;
  description: string;
  confidence: number;
  excerpt?: string;
}

/**
 * Interface for speech-to-text providers (Deepgram, Whisper, etc.)
 */
export interface SpeechToTextProvider {
  readonly name: string;

  /**
   * Transcribe an audio buffer or S3 key.
   */
  transcribe(
    audioBuffer: Buffer,
    options?: {
      mimeType?: string;
      language?: string;
      model?: string;
    },
  ): Promise<TranscriptionResult>;
}

/**
 * Interface for AI-based audio/text analysis providers.
 */
export interface AudioClassifierProvider {
  readonly name: string;

  /**
   * Classify a transcript for distress indicators.
   */
  classifyDistress(
    text: string,
    context?: {
      incidentId?: string;
      previousTranscripts?: string[];
    },
  ): Promise<DistressClassificationResult>;
}

export const SPEECH_TO_TEXT_PROVIDER = Symbol('SPEECH_TO_TEXT_PROVIDER');
export const AUDIO_CLASSIFIER_PROVIDER = Symbol('AUDIO_CLASSIFIER_PROVIDER');
