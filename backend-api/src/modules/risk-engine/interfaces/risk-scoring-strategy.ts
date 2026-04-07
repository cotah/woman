import { RiskLevel } from '../../incidents/entities/incident.entity';

/**
 * Signal sent to the risk engine for evaluation.
 */
export interface RiskSignal {
  /** Signal type identifier matching a rule_id in the rules config */
  type: string;
  /** Arbitrary payload data associated with the signal */
  payload: Record<string, any>;
}

/**
 * Current state of an incident relevant to risk scoring.
 */
export interface IncidentRiskState {
  incidentId: string;
  currentScore: number;
  currentLevel: RiskLevel;
  isCoercion: boolean;
  isTestMode: boolean;
  triggerType: string;
  eventCount: number;
}

/**
 * Result of evaluating a single risk rule.
 */
export interface RiskRuleResult {
  ruleId: string;
  ruleName: string;
  scoreDelta: number;
  reason: string;
  matched: boolean;
}

/**
 * Complete result of a risk assessment.
 */
export interface RiskAssessmentResult {
  previousScore: number;
  newScore: number;
  previousLevel: RiskLevel;
  newLevel: RiskLevel;
  scoreDelta: number;
  ruleResults: RiskRuleResult[];
  reasons: string[];
}

/**
 * Strategy interface for risk scoring.
 *
 * Phase 1: Rule-based deterministic engine.
 * Phase 2: ML-based engine implementing the same interface for seamless replacement.
 */
export interface RiskScoringStrategy {
  /**
   * Evaluate a signal against the current incident state and return a risk assessment.
   */
  evaluate(signal: RiskSignal, state: IncidentRiskState): Promise<RiskAssessmentResult>;

  /**
   * Return the human-readable name of this strategy (e.g., 'rule-based', 'ml-v1').
   */
  getName(): string;
}

export const RISK_SCORING_STRATEGY = 'RISK_SCORING_STRATEGY';
