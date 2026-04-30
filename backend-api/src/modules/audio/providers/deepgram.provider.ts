import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  SpeechToTextProvider,
  TranscriptionResult,
} from './audio-analysis-provider.interface';

/**
 * Local view of a Deepgram word object — declares only the
 * fields we consume from the API response. Deepgram is not
 * installed as an SDK; this provider calls the HTTP API
 * directly via fetch().
 */
interface DeepgramWord {
  word: string;
  start: number;
  end: number;
  confidence: number;
}

@Injectable()
export class DeepgramProvider implements SpeechToTextProvider {
  readonly name = 'deepgram';
  private readonly logger = new Logger(DeepgramProvider.name);
  private readonly apiKey: string;
  private readonly baseUrl = 'https://api.deepgram.com/v1';

  constructor(private readonly config: ConfigService) {
    this.apiKey = this.config.get<string>('DEEPGRAM_API_KEY', '');

    if (!this.apiKey) {
      this.logger.warn(
        'Deepgram API key not configured; STT provider will operate in stub mode',
      );
    }
  }

  async transcribe(
    audioBuffer: Buffer,
    options?: {
      mimeType?: string;
      language?: string;
      model?: string;
    },
  ): Promise<TranscriptionResult> {
    if (!this.apiKey) {
      this.logger.debug('[STUB] Deepgram transcription requested; returning empty result');
      return {
        text: '',
        confidence: 0,
        language: options?.language || 'en',
        words: [],
      };
    }

    const mimeType = options?.mimeType || 'audio/webm';
    const model = options?.model || 'nova-2';
    const language = options?.language || 'en';

    try {
      const url = new URL('/v1/listen', this.baseUrl);
      url.searchParams.set('model', model);
      url.searchParams.set('language', language);
      url.searchParams.set('punctuate', 'true');
      url.searchParams.set('diarize', 'true');
      url.searchParams.set('smart_format', 'true');
      url.searchParams.set('utterances', 'true');

      const response = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          Authorization: `Token ${this.apiKey}`,
          'Content-Type': mimeType,
        },
        body: new Uint8Array(audioBuffer),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        throw new Error(
          `Deepgram API error: ${response.status} ${response.statusText} - ${errorBody}`,
        );
      }

      const data = await response.json();
      const channel = data.results?.channels?.[0];
      const alternative = channel?.alternatives?.[0];

      if (!alternative) {
        return { text: '', confidence: 0, language, words: [] };
      }

      const words = (alternative.words || []).map((w: DeepgramWord) => ({
        word: w.word,
        start: w.start,
        end: w.end,
        confidence: w.confidence,
      }));

      this.logger.log(
        `Transcription completed: ${alternative.transcript.length} chars, confidence ${alternative.confidence}`,
      );

      return {
        text: alternative.transcript,
        confidence: alternative.confidence,
        language: data.results?.channels?.[0]?.detected_language || language,
        words,
      };
    } catch (error) {
      this.logger.error(
        `Deepgram transcription failed: ${error.message}`,
        error.stack,
      );
      throw error;
    }
  }
}
