/**
 * Risk rule definition for the rule-based scoring engine.
 */
export interface RiskRule {
  /** Unique identifier for this rule */
  id: string;
  /** Human-readable name */
  name: string;
  /** Signal type this rule matches against */
  signalType: string;
  /** Points to add when this rule fires */
  scoreDelta: number;
  /** Description / reason template */
  reason: string;
  /** If true, this rule can only fire once per incident */
  oncePerIncident: boolean;
  /** If true, this rule is only active in non-test mode */
  liveOnly: boolean;
}

/**
 * Default risk rules for Phase 1 deterministic engine.
 */
export const DEFAULT_RISK_RULES: RiskRule[] = [
  {
    id: 'manual_panic_trigger',
    name: 'Manual Panic Trigger',
    signalType: 'manual_panic_trigger',
    scoreDelta: 70,
    reason: 'User manually triggered a panic alert',
    oncePerIncident: true,
    liveOnly: false,
  },
  {
    id: 'coercion_pin',
    name: 'Coercion PIN Entered',
    signalType: 'coercion_pin',
    scoreDelta: 95,
    reason: 'Coercion PIN was used - user may be under duress',
    oncePerIncident: true,
    liveOnly: false,
  },
  {
    id: 'physical_trigger',
    name: 'Physical Button Trigger',
    signalType: 'physical_trigger',
    scoreDelta: 70,
    reason: 'Physical button trigger activated',
    oncePerIncident: true,
    liveOnly: false,
  },
  {
    id: 'countdown_not_cancelled',
    name: 'Countdown Not Cancelled',
    signalType: 'countdown_not_cancelled',
    scoreDelta: 20,
    reason: 'Countdown expired without cancellation',
    oncePerIncident: true,
    liveOnly: false,
  },
  {
    id: 'rapid_movement',
    name: 'Rapid Movement Detected',
    signalType: 'rapid_movement',
    scoreDelta: 10,
    reason: 'Unusual rapid movement detected from device sensors',
    oncePerIncident: false,
    liveOnly: true,
  },
  {
    id: 'audio_distress_detected',
    name: 'Audio Distress Detected',
    signalType: 'audio_distress_detected',
    scoreDelta: 25,
    reason: 'Audio analysis detected distress signals',
    oncePerIncident: false,
    liveOnly: true,
  },
  {
    id: 'help_phrase_detected',
    name: 'Help Phrase Detected',
    signalType: 'help_phrase_detected',
    scoreDelta: 35,
    reason: 'Voice transcription detected a help/distress phrase',
    oncePerIncident: false,
    liveOnly: true,
  },
  {
    id: 'repeated_trigger',
    name: 'Repeated Trigger',
    signalType: 'repeated_trigger',
    scoreDelta: 10,
    reason: 'User triggered the alert multiple times',
    oncePerIncident: false,
    liveOnly: false,
  },
];

/**
 * Score thresholds mapping score ranges to risk levels.
 */
export const RISK_SCORE_THRESHOLDS = {
  none: { min: 0, max: 19 },
  monitoring: { min: 20, max: 39 },
  suspicious: { min: 40, max: 69 },
  alert: { min: 70, max: 89 },
  critical: { min: 90, max: Infinity },
} as const;

/**
 * Maximum possible risk score (clamped to this value).
 */
export const MAX_RISK_SCORE = 100;
