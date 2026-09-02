{
  "methodologyVersion": "1.0",
  "footprint": {
    "energyPerPromptWh":        { "low": 0.24, "central": 0.27, "high": 0.30 },
    "gridIntensityGco2ePerWh":  { "low": 0.125, "central": 0.30, "high": 0.475 },
    "waterMlPerWh":             { "low": 0.8,  "central": 1.08, "high": 1.4 },
    "referencePromptTokens": 500, "typicalOutputTokens": 250, "outputWeight": 1.0, "charsPerToken": 4.0
  },
  "modelMultipliers": {
    "SMALL":  { "tier": "SMALL",  "rank": 1, "rateCardMultiplier": 0.5 },
    "MEDIUM": { "tier": "MEDIUM", "rank": 2, "rateCardMultiplier": 1.0 },
    "LARGE":  { "tier": "LARGE",  "rank": 3, "rateCardMultiplier": 2.0 },
    "_baseline": "MEDIUM"
  },
  "thresholds": {
    "topicScopeSoftTokens": 500, "topicScopeHardTokens": 1000,
    "agentSoftTokens": 400, "agentHardTokens": 800,
    "actionSoftTokens": 150, "actionHardTokens": 300,
    "modelOvershootMin": 1, "redundantExtraCallsMin": 1, "sequentialChainMin": 3
  },
  "volumeScenario": { "sessionsPerDay": 50, "turnsPerSession": 6, "callsPerTurn": 1, "daysPerYear": 365 },
  "signalWeights": {
    "LLM_WHERE_DETERMINISTIC": 1.0, "MODEL_RIGHTSIZING": 0.7,
    "INSTRUCTION_BLOAT": 0.5, "REDUNDANT_CALLS": 0.8
  },
  "gradeCutoffs": { "A": 90, "B": 80, "C": 70, "D": 60 }
}
