/**
 * Shared mock factory for the AuditReadoutDTO / FindingDTO shapes (SPEC §S.0).
 * Field names mirror the Apex DTO EXACTLY (energyWhLow/Central/High, waterMl*,
 * co2eG*, estimatedSavings*, volumeAssumption{sessionsPerPeriod...}, assumptions).
 * Every consumer + test binds these shapes; do not drift the keys.
 */

// --- VolumeInput (C6): 50 sessions/day x 6 turns x 1 call x 365 days = 109,500 ---
export function mockVolumeAssumption(overrides) {
    return Object.assign(
        {
            sessionsPerPeriod: 50,
            turnsPerSession: 6,
            callsPerTurn: 1,
            periodsPerYear: 365,
            scenarioLabel: '50 sessions/day × 6 turns'
        },
        overrides || {}
    );
}

// --- assumptions map surfaced by the methodology panel (F10 / W4) ---
export function mockAssumptions(overrides) {
    return Object.assign(
        {
            methodologyVersion: '1.0',
            energyPerPromptWhLow: 0.24,
            energyPerPromptWhCentral: 0.27,
            energyPerPromptWhHigh: 0.3,
            gridIntensityGco2ePerWhLow: 0.125,
            gridIntensityGco2ePerWhCentral: 0.3,
            gridIntensityGco2ePerWhHigh: 0.475,
            waterMlPerWhLow: 0.8,
            waterMlPerWhCentral: 1.08,
            waterMlPerWhHigh: 1.4,
            referencePromptTokens: 500,
            charsPerToken: 4.0,
            telemetryBacked: false,
            co2eBandNote:
                'CO₂e band width is dominated by grid carbon intensity, which varies widely by region and time of day.'
        },
        overrides || {}
    );
}

let _seq = 0;
function nextId(prefix) {
    _seq += 1;
    // 18-char-ish synthetic id; only shape matters in Jest.
    return (prefix + '000000000000000').slice(0, 15) + String(_seq).padStart(3, '0');
}

/**
 * Build one FindingDTO. `signal` should be a canonical C2 value.
 */
export function mockFinding(overrides) {
    const base = {
        id: nextId('a00'),
        signal: 'LLM_WHERE_DETERMINISTIC',
        severity: 'High',
        confidence: 'Medium',
        artifactType: 'Action',
        targetArtifact: {
            apiName: 'Ohm_Fixture_ClassifyPriority',
            label: 'Classify Lead Priority',
            toolingId: '0Ab000000000001',
            parentAgentApiName: 'Ohm_Fixture_LeadBot',
            parentTopicApiName: 'Ohm_Fixture_LeadTriage'
        },
        evidence: 'Action uses an LLM to classify into High/Medium/Low — deterministic rules suffice.',
        metricValue: 2,
        metricUnit: 'calls-per-turn',
        energyWhLow: 26280.0,
        energyWhCentral: 29565.0,
        energyWhHigh: 32850.0,
        waterMlLow: 21024.0,
        waterMlCentral: 31930.2,
        waterMlHigh: 45990.0,
        co2eGLow: 3285.0,
        co2eGCentral: 8869.5,
        co2eGHigh: 15603.75,
        estimatedAnnualCalls: 109500,
        perInferenceWh: 0.27,
        estimatedSavingsLow: 26280.0,
        estimatedSavingsCentral: 29565.0,
        estimatedSavingsHigh: 32850.0,
        fixType: 'Replace_With_Flow',
        recommendedTarget: 'A record-triggered Flow with a decision element',
        recommendationText:
            'Replace this LLM classification with a deterministic Flow decision on lead score bands.',
        agentNarrative: null,
        generatedBy: 'Deterministic',
        effort: 'Low',
        recStatus: 'Proposed',
        remediationTaskId: null
    };
    return Object.assign(base, overrides || {});
}

/**
 * Four findings, one per canonical C2 signal; exactly one carries an agentNarrative
 * (the hybrid seam made visible on the card).
 */
export function mockFindings() {
    return [
        mockFinding({
            signal: 'LLM_WHERE_DETERMINISTIC',
            severity: 'High',
            confidence: 'Medium',
            fixType: 'Replace_With_Flow'
        }),
        mockFinding({
            signal: 'MODEL_RIGHTSIZING',
            severity: 'Medium',
            confidence: 'Medium',
            artifactType: 'Action',
            metricValue: 2,
            metricUnit: 'model-multiplier',
            fixType: 'Downsize_Model',
            recommendedTarget: 'sfdc_ai__DefaultSmall',
            recommendationText: 'The task is trivial; a SMALL model covers it at half the rate-card cost.',
            agentNarrative:
                'This step leans on a heavyweight model for what is essentially a lookup. A smaller model would keep the answer quality while easing the energy draw.',
            generatedBy: 'Agentforce',
            effort: 'Low'
        }),
        mockFinding({
            signal: 'INSTRUCTION_BLOAT',
            severity: 'High',
            confidence: 'High',
            artifactType: 'Topic',
            metricValue: 800,
            metricUnit: 'tokens',
            evidence: 'Scope ≈ 1,300 tokens vs a 500-token soft budget; 800 tokens of excess.',
            fixType: 'Trim_Instructions',
            recommendedTarget: 'Ohm_Fixture_LeadTriage scope',
            recommendationText: 'Trim the scope back under the 500-token soft budget.',
            effort: 'Medium'
        }),
        mockFinding({
            signal: 'REDUNDANT_CALLS',
            severity: 'High',
            confidence: 'Low',
            artifactType: 'Agent',
            metricValue: 2,
            metricUnit: 'calls-per-turn',
            evidence: 'ClassifyPriority is invoked 3× per turn (2 redundant).',
            fixType: 'Consolidate_Calls',
            recommendedTarget: 'Single classification call per turn',
            recommendationText: 'Consolidate the repeated classification calls into one per turn.',
            effort: 'Low'
        })
    ];
}

/**
 * Full AuditReadoutDTO in the Complete state (SPEC §S.0). >= 4 findings.
 */
export function mockAuditReadoutComplete(overrides) {
    const findings = mockFindings();
    const base = {
        reportId: nextId('a01'),
        runStatus: 'Complete',
        stageMessage: 'Audit complete.',
        percentComplete: 100,
        agentsDiscovered: 2,
        topicsDiscovered: 4,
        actionsDiscovered: 7,
        promptTemplatesDiscovered: 1,
        efficiencyGrade: 'D',
        efficiencyScore: 62,
        methodologyVersion: '1.0',
        orgEnergyWhLow: 78840.0,
        orgEnergyWhCentral: 88695.0,
        orgEnergyWhHigh: 98550.0,
        orgWaterMlLow: 63072.0,
        orgWaterMlCentral: 95790.6,
        orgWaterMlHigh: 137970.0,
        orgCo2eGLow: 9855.0,
        orgCo2eGCentral: 26608.5,
        orgCo2eGHigh: 46811.25,
        orgEnergySavingsWhLow: 52560.0,
        orgEnergySavingsWhCentral: 59130.0,
        orgEnergySavingsWhHigh: 65700.0,
        telemetryBacked: false,
        volumeAssumption: mockVolumeAssumption(),
        assumptions: mockAssumptions(),
        findings,
        discoveryErrors: null
    };
    return Object.assign(base, overrides || {});
}

/**
 * AuditReadoutDTO mid-run (Discovering/Analyzing) — no findings yet.
 */
export function mockAuditReadoutRunning(overrides) {
    const base = {
        reportId: nextId('a01'),
        runStatus: 'Discovering',
        stageMessage: 'Walking the agent inventory…',
        percentComplete: 20,
        agentsDiscovered: 0,
        topicsDiscovered: 0,
        actionsDiscovered: 0,
        promptTemplatesDiscovered: 0,
        efficiencyGrade: null,
        efficiencyScore: null,
        methodologyVersion: '1.0',
        orgEnergyWhLow: null,
        orgEnergyWhCentral: null,
        orgEnergyWhHigh: null,
        orgWaterMlLow: null,
        orgWaterMlCentral: null,
        orgWaterMlHigh: null,
        orgCo2eGLow: null,
        orgCo2eGCentral: null,
        orgCo2eGHigh: null,
        orgEnergySavingsWhLow: null,
        orgEnergySavingsWhCentral: null,
        orgEnergySavingsWhHigh: null,
        telemetryBacked: false,
        volumeAssumption: mockVolumeAssumption(),
        assumptions: mockAssumptions(),
        findings: [],
        discoveryErrors: null
    };
    return Object.assign(base, overrides || {});
}
