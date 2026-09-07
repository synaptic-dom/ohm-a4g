export function reviewFixture() {
    const inputIssue = {
        code: 'REPEATED_CONTEXT', origin: 'Reviewer',
        evidence: [{ artifactId: 'topic:triage', quote: 'Always explain the full routing policy.' }],
        explanation: 'The full routing policy is requested in every response.',
        recommendation: 'Keep the routing policy in the instructions and request only the result.',
        preserve: 'Keep the escalation and approval requirements.',
        validation: 'Replay escalation and ordinary routing cases before publishing.'
    };
    const categories = [
        { id: 'INPUT', label: 'Input efficiency', rating: 'B', status: 'reviewed', coverageStatus: 'Complete', assessment: 'Repeated context can be consolidated.', issues: [inputIssue] },
        { id: 'OUTPUT', label: 'Output efficiency', rating: 'A', status: 'reviewed', coverageStatus: 'Complete', assessment: 'The answer is constrained to the required fields.', issues: [] },
        { id: 'MODEL', label: 'Model fit', rating: 'UNRATED', status: 'unknown', coverageStatus: 'Unknown', coverageNote: 'No model evaluation evidence is available.', assessment: 'Binding alone does not establish model fit.', issues: [] },
        { id: 'CALLS', label: 'Call efficiency', rating: 'UNRATED', status: 'unknown', coverageStatus: 'Unknown', assessment: 'The source does not establish runtime call frequency.', issues: [] }
    ];
    return {
        schemaVersion: 1, status: 'Reviewed', reviewer: 'Salesforce Prompt Builder',
        reviewerTemplate: 'Ohm_Efficiency_Review', reviewerVersion: 'v1', rubricVersion: '1.0',
        reviewedAt: '2026-09-07T18:00:00Z',
        coverage: { artifactCount: 1, assessedArtifactCount: 1 },
        categories: categories.map((category) => ({ ...category, assessedArtifactCount: category.status === 'reviewed' ? 1 : 0, totalArtifactCount: 1 })),
        artifacts: [{
            artifactId: 'topic:triage', artifactType: 'Topic', apiName: 'Lead_Triage', label: 'Lead triage instructions',
            sourceHash: 'a'.repeat(64), sourceVersion: 'Lead_Concierge.v4', sourcePath: 'aiAuthoringBundles/Lead_Concierge/Lead_Concierge.agent',
            characterCount: 100, estimatedTokens: 25, boundModel: null, modelBindingKnown: false, categories
        }],
        limitations: ['No runtime telemetry was used.']
    };
}

export function reviewSummaryFixture() {
    const review = reviewFixture();
    return { ...review, summaryOnly: true, artifacts: [], categories: review.categories.map((category) => ({ ...category, issues: [] })) };
}
