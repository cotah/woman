import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AudioClassifierProvider,
  DistressClassificationResult,
} from './audio-analysis-provider.interface';

@Injectable()
export class AiClassifierProvider implements AudioClassifierProvider {
  readonly name = 'openai-classifier';
  private readonly logger = new Logger(AiClassifierProvider.name);
  private readonly apiKey: string;
  private readonly model: string;

  constructor(private readonly config: ConfigService) {
    this.apiKey = this.config.get<string>('OPENAI_API_KEY', '');
    this.model = this.config.get<string>('OPENAI_CLASSIFIER_MODEL', 'gpt-4o-mini');

    if (!this.apiKey) {
      this.logger.warn(
        'OpenAI API key not configured; classifier will operate in stub mode',
      );
    }
  }

  async classifyDistress(
    text: string,
    context?: {
      incidentId?: string;
      previousTranscripts?: string[];
    },
  ): Promise<DistressClassificationResult> {
    if (!this.apiKey) {
      this.logger.debug('[STUB] Distress classification requested; returning safe result');
      return {
        isDistress: false,
        confidence: 0,
        riskLevel: 'none',
        signals: [],
        summary: 'Classification unavailable (stub mode)',
      };
    }

    if (!text || text.trim().length === 0) {
      return {
        isDistress: false,
        confidence: 1,
        riskLevel: 'none',
        signals: [],
        summary: 'No speech content to analyze.',
      };
    }

    try {
      const systemPrompt = `You are an emergency safety analysis system. Analyze the following transcript from a potential emergency situation. Identify any distress signals, threats, coercion indicators, or signs of danger.

Respond ONLY with valid JSON in this exact format:
{
  "isDistress": boolean,
  "confidence": number (0-1),
  "riskLevel": "none" | "low" | "medium" | "high" | "critical",
  "signals": [
    {
      "type": "verbal_threat" | "coercion" | "distress_keyword" | "fear_indicator" | "violence_indicator" | "help_request" | "emotional_distress",
      "description": "brief description",
      "confidence": number (0-1),
      "excerpt": "relevant quote from transcript"
    }
  ],
  "summary": "one-sentence summary of the analysis"
}

Be conservative - only flag genuine distress indicators. Do not over-interpret normal conversation.`;

      const previousContext =
        context?.previousTranscripts?.length
          ? `\n\nPrevious transcript segments:\n${context.previousTranscripts.join('\n---\n')}`
          : '';

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: this.model,
          messages: [
            { role: 'system', content: systemPrompt },
            {
              role: 'user',
              content: `Analyze the following transcript for distress signals:${previousContext}\n\nCurrent transcript:\n"${text}"`,
            },
          ],
          temperature: 0.1,
          max_tokens: 1000,
          response_format: { type: 'json_object' },
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        throw new Error(
          `OpenAI API error: ${response.status} ${response.statusText} - ${errorBody}`,
        );
      }

      const data = await response.json();
      const content = data.choices?.[0]?.message?.content;

      if (!content) {
        throw new Error('Empty response from OpenAI');
      }

      const parsed = JSON.parse(content) as DistressClassificationResult;

      this.logger.log(
        `Distress classification: isDistress=${parsed.isDistress}, risk=${parsed.riskLevel}, signals=${parsed.signals.length}`,
      );

      return parsed;
    } catch (error) {
      this.logger.error(
        `Distress classification failed: ${error.message}`,
        error.stack,
      );

      // On failure, return a safe default rather than crashing
      return {
        isDistress: false,
        confidence: 0,
        riskLevel: 'none',
        signals: [],
        summary: `Classification failed: ${error.message}`,
      };
    }
  }
}
