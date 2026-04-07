import { RiskEngineService } from '../../src/modules/risk-engine/risk-engine.service';
import {
  RiskSignal,
  IncidentRiskState,
} from '../../src/modules/risk-engine/interfaces/risk-scoring-strategy';
import {
  DEFAULT_RISK_RULES,
  RiskRule,
  MAX_RISK_SCORE,
} from '../../src/modules/risk-engine/risk-rules.config';
import { RiskLevel } from '../../src/modules/incidents/entities/incident.entity';

describe('RiskEngineService', () => {
  let service: RiskEngineService;
  let mockRiskAssessmentRepo: any;

  const buildState = (overrides: Partial<IncidentRiskState> = {}): IncidentRiskState => ({
    incidentId: 'incident-1',
    currentScore: 0,
    currentLevel: RiskLevel.NONE,
    isCoercion: false,
    isTestMode: false,
    triggerType: 'manual_button',
    eventCount: 0,
    ...overrides,
  });

  beforeEach(() => {
    mockRiskAssessmentRepo = {
      find: jest.fn().mockResolvedValue([]),
      findOne: jest.fn(),
      create: jest.fn((data) => data),
      save: jest.fn((data) => Promise.resolve({ id: 'assessment-1', ...data })),
    };

    service = new RiskEngineService(mockRiskAssessmentRepo);
  });

  describe('getName', () => {
    it('should return the strategy name', () => {
      expect(service.getName()).toBe('rule-based-v1');
    });
  });

  describe('manual panic trigger', () => {
    it('should add 70 points for a manual panic trigger', async () => {
      const signal: RiskSignal = { type: 'manual_panic_trigger', payload: {} };
      const state = buildState();

      const result = await service.evaluate(signal, state);

      expect(result.scoreDelta).toBe(70);
      expect(result.newScore).toBe(70);
      expect(result.ruleResults.some((r) => r.matched && r.ruleId === 'manual_panic_trigger')).toBe(true);
    });
  });

  describe('coercion PIN', () => {
    it('should push score to critical (95) on coercion_pin signal', async () => {
      const signal: RiskSignal = { type: 'coercion_pin', payload: {} };
      const state = buildState();

      const result = await service.evaluate(signal, state);

      expect(result.newScore).toBe(95);
      expect(result.newLevel).toBe(RiskLevel.CRITICAL);
    });

    it('should still reach critical even with a non-zero starting score', async () => {
      const signal: RiskSignal = { type: 'coercion_pin', payload: {} };
      const state = buildState({ currentScore: 10, currentLevel: RiskLevel.NONE });

      const result = await service.evaluate(signal, state);

      expect(result.newScore).toBe(100); // 10 + 95 = 105, clamped to 100
      expect(result.newLevel).toBe(RiskLevel.CRITICAL);
    });
  });

  describe('score clamping', () => {
    it('should not exceed MAX_RISK_SCORE (100)', async () => {
      const signal: RiskSignal = { type: 'coercion_pin', payload: {} };
      const state = buildState({ currentScore: 50 });

      const result = await service.evaluate(signal, state);

      // 50 + 95 = 145, clamped to 100
      expect(result.newScore).toBe(MAX_RISK_SCORE);
      expect(result.newScore).toBeLessThanOrEqual(100);
    });

    it('should clamp when multiple high-scoring signals accumulate', async () => {
      // First signal: manual panic (70)
      const signal1: RiskSignal = { type: 'manual_panic_trigger', payload: {} };
      const state1 = buildState();
      const result1 = await service.evaluate(signal1, state1);
      expect(result1.newScore).toBe(70);

      // Second signal: countdown_not_cancelled (20) on top of 70
      const signal2: RiskSignal = { type: 'countdown_not_cancelled', payload: {} };
      const state2 = buildState({ currentScore: 70, currentLevel: RiskLevel.ALERT });
      const result2 = await service.evaluate(signal2, state2);
      expect(result2.newScore).toBe(90);

      // Third signal: help_phrase_detected (35) on top of 90 -> clamped to 100
      const signal3: RiskSignal = { type: 'help_phrase_detected', payload: {} };
      const state3 = buildState({ currentScore: 90, currentLevel: RiskLevel.CRITICAL });
      const result3 = await service.evaluate(signal3, state3);
      expect(result3.newScore).toBe(100);
    });
  });

  describe('risk level thresholds', () => {
    it('should return NONE for score 0-19', () => {
      expect(service.scoreToLevel(0)).toBe(RiskLevel.NONE);
      expect(service.scoreToLevel(10)).toBe(RiskLevel.NONE);
      expect(service.scoreToLevel(19)).toBe(RiskLevel.NONE);
    });

    it('should return MONITORING for score 20-39', () => {
      expect(service.scoreToLevel(20)).toBe(RiskLevel.MONITORING);
      expect(service.scoreToLevel(30)).toBe(RiskLevel.MONITORING);
      expect(service.scoreToLevel(39)).toBe(RiskLevel.MONITORING);
    });

    it('should return SUSPICIOUS for score 40-69', () => {
      expect(service.scoreToLevel(40)).toBe(RiskLevel.SUSPICIOUS);
      expect(service.scoreToLevel(55)).toBe(RiskLevel.SUSPICIOUS);
      expect(service.scoreToLevel(69)).toBe(RiskLevel.SUSPICIOUS);
    });

    it('should return ALERT for score 70-89', () => {
      expect(service.scoreToLevel(70)).toBe(RiskLevel.ALERT);
      expect(service.scoreToLevel(80)).toBe(RiskLevel.ALERT);
      expect(service.scoreToLevel(89)).toBe(RiskLevel.ALERT);
    });

    it('should return CRITICAL for score 90+', () => {
      expect(service.scoreToLevel(90)).toBe(RiskLevel.CRITICAL);
      expect(service.scoreToLevel(95)).toBe(RiskLevel.CRITICAL);
      expect(service.scoreToLevel(100)).toBe(RiskLevel.CRITICAL);
    });
  });

  describe('multiple signals accumulate', () => {
    it('should accumulate scores from sequential signals', async () => {
      // manual_panic_trigger = 70
      const signal1: RiskSignal = { type: 'manual_panic_trigger', payload: {} };
      const result1 = await service.evaluate(signal1, buildState());
      expect(result1.newScore).toBe(70);
      expect(result1.newLevel).toBe(RiskLevel.ALERT);

      // countdown_not_cancelled = 20, starting from 70
      const signal2: RiskSignal = { type: 'countdown_not_cancelled', payload: {} };
      const result2 = await service.evaluate(signal2, buildState({ currentScore: 70, currentLevel: RiskLevel.ALERT }));
      expect(result2.newScore).toBe(90);
      expect(result2.newLevel).toBe(RiskLevel.CRITICAL);
    });

    it('should allow repeated_trigger to fire multiple times', async () => {
      const signal: RiskSignal = { type: 'repeated_trigger', payload: {} };
      const state1 = buildState({ currentScore: 70 });
      const result1 = await service.evaluate(signal, state1);
      expect(result1.newScore).toBe(80);

      // Same signal again from higher score
      const state2 = buildState({ currentScore: 80 });
      const result2 = await service.evaluate(signal, state2);
      expect(result2.newScore).toBe(90);
    });
  });

  describe('unknown signal type', () => {
    it('should return no change for an unknown signal type', async () => {
      const signal: RiskSignal = { type: 'nonexistent_signal', payload: {} };
      const state = buildState({ currentScore: 50, currentLevel: RiskLevel.SUSPICIOUS });

      const result = await service.evaluate(signal, state);

      expect(result.scoreDelta).toBe(0);
      expect(result.newScore).toBe(50);
      expect(result.newLevel).toBe(RiskLevel.SUSPICIOUS);
      expect(result.ruleResults).toHaveLength(0);
      expect(result.reasons).toHaveLength(0);
    });
  });

  describe('rules can be disabled', () => {
    it('should skip rules that are removed from the rule set', async () => {
      // Remove the manual_panic_trigger rule
      const filteredRules = DEFAULT_RISK_RULES.filter((r) => r.id !== 'manual_panic_trigger');
      service.setRules(filteredRules);

      const signal: RiskSignal = { type: 'manual_panic_trigger', payload: {} };
      const state = buildState();

      const result = await service.evaluate(signal, state);

      expect(result.scoreDelta).toBe(0);
      expect(result.newScore).toBe(0);
    });

    it('should return the updated rule set after setRules', () => {
      const customRules: RiskRule[] = [
        {
          id: 'custom_rule',
          name: 'Custom Rule',
          signalType: 'custom_signal',
          scoreDelta: 50,
          reason: 'Custom reason',
          oncePerIncident: false,
          liveOnly: false,
        },
      ];
      service.setRules(customRules);
      expect(service.getRules()).toHaveLength(1);
      expect(service.getRules()[0].id).toBe('custom_rule');
    });
  });

  describe('liveOnly rules in test mode', () => {
    it('should skip liveOnly rules when incident is in test mode', async () => {
      const signal: RiskSignal = { type: 'rapid_movement', payload: {} };
      const state = buildState({ isTestMode: true });

      const result = await service.evaluate(signal, state);

      expect(result.scoreDelta).toBe(0);
      expect(result.ruleResults[0].matched).toBe(false);
    });

    it('should apply liveOnly rules when incident is not in test mode', async () => {
      const signal: RiskSignal = { type: 'rapid_movement', payload: {} };
      const state = buildState({ isTestMode: false });

      const result = await service.evaluate(signal, state);

      expect(result.scoreDelta).toBe(10);
      expect(result.ruleResults[0].matched).toBe(true);
    });
  });

  describe('oncePerIncident rules', () => {
    it('should skip a oncePerIncident rule that already fired', async () => {
      mockRiskAssessmentRepo.find.mockResolvedValue([
        { ruleId: 'manual_panic_trigger' },
      ]);

      const signal: RiskSignal = { type: 'manual_panic_trigger', payload: {} };
      const state = buildState();

      const result = await service.evaluate(signal, state);

      expect(result.scoreDelta).toBe(0);
      expect(result.ruleResults[0].matched).toBe(false);
    });
  });

  describe('evaluateAndPersist', () => {
    it('should persist assessment records for matched rules', async () => {
      const signal: RiskSignal = { type: 'manual_panic_trigger', payload: { triggerType: 'manual_button' } };
      const state = buildState();

      const { result, records } = await service.evaluateAndPersist(signal, state);

      expect(result.newScore).toBe(70);
      expect(mockRiskAssessmentRepo.create).toHaveBeenCalled();
      expect(mockRiskAssessmentRepo.save).toHaveBeenCalled();
      expect(records).toHaveLength(1);
      expect(records[0].signalType).toBe('manual_panic_trigger');
    });

    it('should not persist records when no rules match', async () => {
      const signal: RiskSignal = { type: 'unknown', payload: {} };
      const state = buildState();

      const { result, records } = await service.evaluateAndPersist(signal, state);

      expect(result.scoreDelta).toBe(0);
      expect(records).toHaveLength(0);
      expect(mockRiskAssessmentRepo.create).not.toHaveBeenCalled();
    });
  });
});
