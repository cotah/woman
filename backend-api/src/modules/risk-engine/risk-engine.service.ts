import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RiskLevel } from '../incidents/entities/incident.entity';
import { RiskAssessment } from '../incidents/entities/risk-assessment.entity';
import {
  RiskScoringStrategy,
  RiskSignal,
  IncidentRiskState,
  RiskAssessmentResult,
  RiskRuleResult,
} from './interfaces/risk-scoring-strategy';
import {
  DEFAULT_RISK_RULES,
  RiskRule,
  RISK_SCORE_THRESHOLDS,
  MAX_RISK_SCORE,
} from './risk-rules.config';

@Injectable()
export class RiskEngineService implements RiskScoringStrategy {
  private readonly logger = new Logger(RiskEngineService.name);
  private rules: RiskRule[];

  constructor(
    @InjectRepository(RiskAssessment)
    private readonly riskAssessmentRepo: Repository<RiskAssessment>,
  ) {
    this.rules = [...DEFAULT_RISK_RULES];
  }

  getName(): string {
    return 'rule-based-v1';
  }

  /**
   * Evaluate a signal against the current incident state.
   * Returns a complete risk assessment result with score deltas and reasons.
   */
  async evaluate(
    signal: RiskSignal,
    state: IncidentRiskState,
  ): Promise<RiskAssessmentResult> {
    const previousScore = state.currentScore;
    const previousLevel = state.currentLevel;
    const ruleResults: RiskRuleResult[] = [];
    let totalDelta = 0;

    // Find rules that match this signal type
    const matchingRules = this.rules.filter(
      (rule) => rule.signalType === signal.type,
    );

    if (matchingRules.length === 0) {
      this.logger.debug(
        `No rules match signal type "${signal.type}" for incident ${state.incidentId}`,
      );
      return {
        previousScore,
        newScore: previousScore,
        previousLevel,
        newLevel: previousLevel,
        scoreDelta: 0,
        ruleResults: [],
        reasons: [],
      };
    }

    // Check for already-fired once-per-incident rules
    let firedRuleIds: string[] = [];
    const onceRules = matchingRules.filter((r) => r.oncePerIncident);
    if (onceRules.length > 0) {
      const existing = await this.riskAssessmentRepo.find({
        where: { incidentId: state.incidentId },
        select: ['ruleId'],
      });
      firedRuleIds = existing.map((e) => e.ruleId);
    }

    for (const rule of matchingRules) {
      // Skip live-only rules in test mode
      if (rule.liveOnly && state.isTestMode) {
        ruleResults.push({
          ruleId: rule.id,
          ruleName: rule.name,
          scoreDelta: 0,
          reason: `Skipped: rule "${rule.name}" is live-only and incident is in test mode`,
          matched: false,
        });
        continue;
      }

      // Skip once-per-incident rules that already fired
      if (rule.oncePerIncident && firedRuleIds.includes(rule.id)) {
        ruleResults.push({
          ruleId: rule.id,
          ruleName: rule.name,
          scoreDelta: 0,
          reason: `Skipped: rule "${rule.name}" already fired for this incident`,
          matched: false,
        });
        continue;
      }

      totalDelta += rule.scoreDelta;
      ruleResults.push({
        ruleId: rule.id,
        ruleName: rule.name,
        scoreDelta: rule.scoreDelta,
        reason: rule.reason,
        matched: true,
      });
    }

    const newScore = Math.min(previousScore + totalDelta, MAX_RISK_SCORE);
    const newLevel = this.scoreToLevel(newScore);
    const reasons = ruleResults
      .filter((r) => r.matched)
      .map((r) => r.reason);

    const result: RiskAssessmentResult = {
      previousScore,
      newScore,
      previousLevel,
      newLevel,
      scoreDelta: totalDelta,
      ruleResults,
      reasons,
    };

    this.logger.log(
      `Risk assessment for incident ${state.incidentId}: ` +
        `${previousScore} -> ${newScore} (${previousLevel} -> ${newLevel}), ` +
        `signal="${signal.type}", delta=${totalDelta}`,
    );

    return result;
  }

  /**
   * Evaluate a signal and persist the assessment record.
   * Returns both the assessment result and the saved entity.
   */
  async evaluateAndPersist(
    signal: RiskSignal,
    state: IncidentRiskState,
  ): Promise<{ result: RiskAssessmentResult; records: RiskAssessment[] }> {
    const result = await this.evaluate(signal, state);

    const records: RiskAssessment[] = [];
    const matchedRules = result.ruleResults.filter((r) => r.matched);

    for (const ruleResult of matchedRules) {
      const record = this.riskAssessmentRepo.create({
        incidentId: state.incidentId,
        previousScore: result.previousScore,
        newScore: result.newScore,
        previousLevel: result.previousLevel,
        newLevel: result.newLevel,
        ruleId: ruleResult.ruleId,
        ruleName: ruleResult.ruleName,
        reason: ruleResult.reason,
        signalType: signal.type,
        signalPayload: signal.payload,
      });

      const saved = await this.riskAssessmentRepo.save(record);
      records.push(saved);
    }

    return { result, records };
  }

  /**
   * Get all risk assessments for an incident, ordered chronologically.
   */
  async getAssessmentsForIncident(
    incidentId: string,
  ): Promise<RiskAssessment[]> {
    return this.riskAssessmentRepo.find({
      where: { incidentId },
      order: { timestamp: 'ASC' },
    });
  }

  /**
   * Convert a numeric score to a risk level.
   */
  scoreToLevel(score: number): RiskLevel {
    if (score >= RISK_SCORE_THRESHOLDS.critical.min) return RiskLevel.CRITICAL;
    if (score >= RISK_SCORE_THRESHOLDS.alert.min) return RiskLevel.ALERT;
    if (score >= RISK_SCORE_THRESHOLDS.suspicious.min) return RiskLevel.SUSPICIOUS;
    if (score >= RISK_SCORE_THRESHOLDS.monitoring.min) return RiskLevel.MONITORING;
    return RiskLevel.NONE;
  }

  /**
   * Replace the rule set at runtime (useful for testing or dynamic config).
   */
  setRules(rules: RiskRule[]): void {
    this.rules = [...rules];
    this.logger.log(`Risk rules replaced: ${rules.length} rules loaded`);
  }

  /**
   * Get the current rule set.
   */
  getRules(): RiskRule[] {
    return [...this.rules];
  }
}
