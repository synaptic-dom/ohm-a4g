const CATEGORY_DEFINITIONS = [
    { id: 'INPUT', label: 'Input efficiency', shortLabel: 'Input', environmentalMechanism: 'Less input to process can reduce inference work when required context is preserved.' },
    { id: 'OUTPUT', label: 'Output efficiency', shortLabel: 'Output', environmentalMechanism: 'Shorter sufficient outputs can reduce generation work while retaining required content.' },
    { id: 'MODEL', label: 'Model fit', shortLabel: 'Model', environmentalMechanism: 'A smaller suitable model may use less compute. Validate quality and tool behavior before switching.' },
    { id: 'CALLS', label: 'Call efficiency', shortLabel: 'Calls', environmentalMechanism: 'Avoiding unnecessary model or tool calls can reduce work when workflow behavior is preserved.' }
];

const RATING_LABELS = {
    A: 'No material issue',
    B: 'Improvement opportunity',
    C: 'Priority fix',
    UNRATED: 'Insufficient evidence'
};
const ISSUE_LABELS = {
    INPUT_UNNECESSARY_CONTEXT: 'Unnecessary context', INPUT_CONFLICT: 'Conflicting instructions',
    INPUT_REDUNDANCY: 'Repeated instructions', INPUT_HARD_BUDGET: 'Configured source review budget exceeded',
    OUTPUT_UNBOUNDED: 'Unbounded response', OUTPUT_UNNECESSARY_VERBOSITY: 'Unnecessary response detail',
    OUTPUT_FORMAT_MISMATCH: 'Response format mismatch', MODEL_OVERSIZED_CANDIDATE: 'Smaller model candidate',
    MODEL_CAPABILITY_RISK: 'Model capability risk', CALLS_DETERMINISTIC_ALTERNATIVE: 'Use code for fixed rules',
    CALLS_REPEAT_CANDIDATE: 'Potential repeated call', CALLS_MISSING_BOUND: 'Missing call limit'
};

function string(value) { return typeof value === 'string' ? value : ''; }
function list(value) { return Array.isArray(value) ? value : []; }
function object(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
function count(value) { return Number.isInteger(value) && value >= 0 ? value : null; }

function sourceLabel(artifact) {
    return string(artifact.label) || string(artifact.apiName) || string(artifact.artifactId) || 'Source artifact';
}

function categories(value, sources) {
    if (!Array.isArray(value) || value.length !== CATEGORY_DEFINITIONS.length) return null;
    const result = [];
    for (const definition of CATEGORY_DEFINITIONS) {
        const matches = value.filter((entry) => object(entry) && entry.id === definition.id);
        if (matches.length !== 1) return null;
        const entry = matches[0];
        // Unknown or contradictory status is never upgraded into a passing grade.
        const suppliedRating = string(entry.rating);
        const rating = ['B', 'C'].includes(suppliedRating) ? suppliedRating
            : suppliedRating === 'A' && entry.status === 'reviewed' && entry.coverageStatus === 'Complete'
                ? 'A' : 'UNRATED';
        const issues = list(entry.issues).filter(object).map((issue, index) => ({
            key: `${definition.id}-${index}`,
            code: string(issue.code),
            label: ISSUE_LABELS[issue.code] || 'Review observation',
            origin: issue.origin === 'Rule' ? 'Code rule' : 'Reviewer assessment',
            explanation: string(issue.explanation),
            recommendation: string(issue.recommendation),
            preserve: string(issue.preserve),
            validation: string(issue.validation),
            evidence: list(issue.evidence).filter(object).map((evidence, evidenceIndex) => {
                const source = sources.get(string(evidence.artifactId));
                return {
                    key: `${definition.id}-${index}-${evidenceIndex}`,
                    artifactId: string(evidence.artifactId),
                    artifactKey: source ? string(source.artifactKey) : '',
                    quote: source ? string(evidence.quote) : '',
                    label: source ? sourceLabel(source) : 'Source reference unavailable',
                    sourceVersion: source ? string(source.sourceVersion) : '',
                    sourceHash: source ? string(source.sourceHash) : '',
                    sourcePath: source ? string(source.sourcePath) : '',
                    missing: !source
                };
            })
        }));
        const effectiveRating = rating === 'A' && issues.length ? 'UNRATED' : rating;
        const assessed = count(entry.assessedArtifactCount);
        const total = count(entry.totalArtifactCount);
        result.push({
            ...definition,
            rating: effectiveRating,
            ratingLabel: RATING_LABELS[effectiveRating],
            accessibleLabel: `${definition.label}: ${effectiveRating === 'UNRATED' ? '' : `${effectiveRating} · `}${RATING_LABELS[effectiveRating]}`,
            css: `review-category review-category--${effectiveRating.toLowerCase()}`,
            chipCss: `ohm-fleet__review-chip ohm-fleet__review-chip--${effectiveRating.toLowerCase()}`,
            assessment: string(entry.assessment) || 'No assessment was recorded for this category.',
            coverageStatus: ['Complete', 'Partial', 'Unknown'].includes(entry.coverageStatus) ? entry.coverageStatus : 'Unknown',
            coverageNote: string(entry.coverageNote),
            coverageText: assessed !== null && total !== null ? `${assessed} of ${total} source artifacts assessed` : '',
            issues,
            hasInheritedOpportunity: effectiveRating === 'B' && issues.length === 0,
            hasIssues: issues.length > 0
        });
    }
    return result;
}

export function parseReview(value) {
    if (value == null || value === '') return { state: 'not-run', categories: [], artifacts: [] };
    const unavailable = { state: 'unavailable', categories: [], artifacts: [] };
    try {
        const report = typeof value === 'string' ? JSON.parse(value) : value;
        if (!object(report) || report.schemaVersion !== 1 || report.status !== 'Reviewed') return unavailable;
        const artifacts = list(report.artifacts).filter(object);
        const sources = [...artifacts, ...list(report.contextSources).filter(object)];
        const sourceMap = new Map(sources.map((artifact) => [string(artifact.artifactId), artifact]));
        if (sourceMap.size !== sources.length || sources.some((artifact) => !string(artifact.artifactId))) return unavailable;
        const summary = categories(report.categories, sourceMap);
        if (!summary) return unavailable;
        const formattedArtifacts = artifacts.map((artifact) => ({
            ...artifact,
            artifactId: string(artifact.artifactId),
            label: sourceLabel(artifact),
            artifactType: string(artifact.artifactType),
            sourceVersion: string(artifact.sourceVersion),
            sourceHash: string(artifact.sourceHash),
            sourcePath: string(artifact.sourcePath),
            factsText: `${count(artifact.characterCount) === null ? 'Character count unavailable' : `${artifact.characterCount.toLocaleString()} characters`} · ${count(artifact.estimatedTokens) === null ? 'Token estimate unavailable' : `approximately ${artifact.estimatedTokens.toLocaleString()} source tokens`}`,
            boundModel: artifact.modelBindingKnown === true ? string(artifact.boundModel) || 'Model identity unavailable' : 'Model binding not established',
            categories: categories(artifact.categories, sourceMap)
        }));
        if (formattedArtifacts.some((artifact) => !artifact.categories)) return unavailable;
        const assessed = object(report.coverage) ? count(report.coverage.assessedArtifactCount) : null;
        const total = object(report.coverage) ? count(report.coverage.artifactCount) : null;
        return {
            state: 'reviewed',
            categories: summary,
            artifacts: formattedArtifacts,
            reviewer: string(report.reviewer) || 'Reviewer identity not recorded',
            reviewerModel: string(report.reviewerModel) || 'Model configuration not recorded',
            reviewerTemplate: string(report.reviewerTemplate),
            reviewerVersion: string(report.reviewerVersion),
            rubricVersion: string(report.rubricVersion),
            reviewedAt: string(report.reviewedAt),
            coverageText: assessed !== null && total !== null ? `${assessed} of ${total} source artifacts assessed` : 'Assessment coverage not recorded',
            limitations: list(report.limitations).filter((item) => typeof item === 'string')
        };
    } catch (error) {
        return unavailable;
    }
}

export function reviewPriority(review) {
    if (!review || review.state !== 'reviewed') return 'NONE';
    for (const rating of ['C', 'B', 'UNRATED', 'A']) {
        if (review.categories.some((category) => category.rating === rating)) return rating;
    }
    return 'NONE';
}
