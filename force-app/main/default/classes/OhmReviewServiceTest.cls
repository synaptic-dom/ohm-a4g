@IsTest
private class OhmReviewServiceTest {
    private static final String PID = '16j000000000001AAA';
    private static final String TID = '16k000000000001AAA';
    private static final String AID = '16l000000000001AAA';
    private class FixtureResponse {
        public Integer schemaVersion;
        public List<OhmReviewService.RawArtifact> artifacts;
        public List<OhmReviewService.RawCategory> categories;
    }
    private class Reviewer extends OhmReviewService.Transport {
        String mode; Integer calls = 0; String evidence;
        Reviewer(String mode) { this.mode = mode; }
        public override String generate(String input) {
            calls++; evidence = input;
            if (mode == 'failure') throw new OhmReviewService.ReviewException('Template unavailable.');
            if (mode == 'oversized') return 'x'.repeat(100001);
            OhmReviewService.Evidence facts = (OhmReviewService.Evidence)JSON.deserialize(input, OhmReviewService.Evidence.class);
            FixtureResponse response = new FixtureResponse();
            response.schemaVersion = 1; response.artifacts = new List<OhmReviewService.RawArtifact>();
            for (OhmReviewService.ArtifactEvidence artifact : facts.artifacts) {
                OhmReviewService.RawArtifact item = new OhmReviewService.RawArtifact();
                item.artifactId = artifact.artifactId; item.categories = categories();
                if (!artifact.modelBindingKnown) item.categories[2].status = 'unknown';
                response.artifacts.add(item);
            }
            response.categories = categories(); response.categories[2].status = 'unknown';
            if (mode == 'missingArtifact') response.artifacts.remove(0);
            if (mode == 'duplicateArtifact') response.artifacts[1].artifactId = response.artifacts[0].artifactId;
            if (mode == 'missingCategory') response.artifacts[0].categories.remove(0);
            if (mode == 'duplicateCategory') response.categories[1].id = 'INPUT';
            if (mode == 'numeric') response.categories[0].assessment = 'There are 200 unnecessary tokens.';
            if (mode == 'unit') response.categories[0].assessment = 'This saves kWh.';
            if (mode == 'longProse') response.categories[0].assessment = 'x'.repeat(601);
            if (mode == 'candidate' || mode == 'falseQuote' || mode == 'foreignQuote' || mode == 'wrongCode'
                || mode == 'ownerMismatch' || mode == 'unknownIssue' || mode == 'numericQuote') {
                OhmReviewService.RawIssue finding = issue('INPUT_REDUNDANCY', facts.artifacts[1].artifactId, facts.artifacts[1].instructions);
                if (mode == 'falseQuote') finding.evidence[0].quote = 'Fabricated source text.';
                if (mode == 'foreignQuote') finding.evidence[0].artifactId = 'foreign';
                if (mode == 'wrongCode') finding.code = 'MODEL_CAPABILITY_RISK';
                if (mode == 'ownerMismatch') {
                    finding.evidence[0].artifactId = facts.artifacts[2].artifactId; finding.evidence[0].quote = facts.artifacts[2].instructions;
                }
                if (mode == 'unknownIssue') response.artifacts[1].categories[0].status = 'unknown';
                response.artifacts[1].categories[0].issues.add(finding);
            }
            if (mode == 'modelCandidate') {
                response.artifacts[2].categories[2].issues.add(issue('MODEL_OVERSIZED_CANDIDATE', facts.artifacts[2].artifactId, facts.artifacts[2].instructions));
            }
            if (mode == 'unknownModelClaim') {
                response.artifacts[0].categories[2].status = 'reviewed';
                response.artifacts[0].categories[2].issues.add(issue('MODEL_OVERSIZED_CANDIDATE', facts.artifacts[0].artifactId, facts.artifacts[0].instructions));
            }
            if (mode == 'crossArtifact') {
                OhmReviewService.RawIssue finding = issue('INPUT_CONFLICT', facts.artifacts[1].artifactId, facts.artifacts[1].instructions);
                OhmReviewService.QuoteEvidence quote = new OhmReviewService.QuoteEvidence();
                quote.artifactId = facts.artifacts[0].artifactId; quote.quote = facts.artifacts[0].instructions; finding.evidence.add(quote);
                response.artifacts[1].categories[0].issues.add(finding);
            }
            if (mode == 'configuration') {
                response.artifacts[1].categories[3].issues.add(issue('CALLS_REPEAT_CANDIDATE',
                    facts.contextSources[0].artifactId, 'run @actions.LookupWeather'));
            }
            if (mode == 'emptyInstructionCandidate') {
                response.artifacts[1].categories[0].issues.add(issue('INPUT_UNNECESSARY_CONTEXT',
                    facts.contextSources[0].artifactId, 'run @actions.LookupWeather'));
            }
            if (mode == 'deterministicCodeOnly') {
                response.artifacts[1].categories[3].issues.add(issue('CALLS_DETERMINISTIC_ALTERNATIVE',
                    facts.contextSources[0].artifactId, 'run @actions.LookupWeather'));
            }
            if (mode == 'deterministicInstruction') {
                response.artifacts[2].categories[3].issues.add(issue('CALLS_DETERMINISTIC_ALTERNATIVE',
                    facts.artifacts[2].artifactId, facts.artifacts[2].instructions));
            }
            if (mode == 'partial') response.artifacts[0].categories[0].status = 'unknown';
            if (mode == 'candidatePartial') {
                response.artifacts[0].categories[0].status = 'unknown';
                response.artifacts[1].categories[0].issues.add(issue('INPUT_REDUNDANCY', facts.artifacts[1].artifactId, facts.artifacts[1].instructions));
            }
            if (mode == 'nestedResponse') return JSON.serialize(response);
            OhmReviewService.RawReview flat = new OhmReviewService.RawReview(); flat.schemaVersion = 1;
            flat.assessments = new List<OhmReviewService.RawAssessment>();
            for (OhmReviewService.RawArtifact artifact : response.artifacts) {
                for (OhmReviewService.RawCategory category : artifact.categories) flat.assessments.add(row(artifact.artifactId, category));
            }
            for (OhmReviewService.RawCategory category : response.categories) flat.assessments.add(row('bundle', category));
            if (mode == 'missingRow') flat.assessments.remove(0);
            if (mode == 'duplicateRow') flat.assessments[1] = flat.assessments[0];
            if (mode == 'unknownAlias') flat.assessments[0].artifactId = 'artifact_999';
            if (mode == 'realIdAsAlias') flat.assessments[0].artifactId = PID;
            if (mode == 'contextAsArtifact') flat.assessments[0].artifactId = 'configuration_1';
            if (mode == 'bundleCase') flat.assessments[flat.assessments.size()-1].artifactId = 'BUNDLE';
            if (mode == 'statusCase') flat.assessments[0].status = 'REVIEWED';
            if (mode == 'categoryCase') flat.assessments[0].categoryId = 'input';
            if (mode == 'reordered') {
                List<OhmReviewService.RawAssessment> reversed = new List<OhmReviewService.RawAssessment>();
                for (Integer i = flat.assessments.size()-1; i >= 0; i--) reversed.add(flat.assessments[i]);
                flat.assessments = reversed;
            }
            String encoded = JSON.serialize(flat);
            if (mode == 'inventedGrade') encoded = encoded.substring(0, encoded.length()-1) + ',"grade":"A"}';
            return encoded;
        }
    }
    private static OhmReviewService.RawAssessment row(String artifactId, OhmReviewService.RawCategory category) {
        OhmReviewService.RawAssessment row = new OhmReviewService.RawAssessment();
        row.artifactId = artifactId; row.categoryId = category.id; row.status = category.status;
        row.assessment = category.assessment; row.issues = category.issues; return row;
    }
    private static List<OhmReviewService.RawCategory> categories() {
        List<OhmReviewService.RawCategory> result = new List<OhmReviewService.RawCategory>();
        for (String id : new List<String>{'INPUT','OUTPUT','MODEL','CALLS'}) {
            OhmReviewService.RawCategory category = new OhmReviewService.RawCategory();
            category.id = id; category.status = 'reviewed';
            category.assessment = 'The supplied source has been assessed for this category.';
            category.issues = new List<OhmReviewService.RawIssue>(); result.add(category);
        }
        return result;
    }
    private static OhmReviewService.RawIssue issue(String code, String artifactId, String quote) {
        OhmReviewService.RawIssue result = new OhmReviewService.RawIssue();
        result.code = code; result.evidence = new List<OhmReviewService.QuoteEvidence>();
        OhmReviewService.QuoteEvidence source = new OhmReviewService.QuoteEvidence();
        source.artifactId = artifactId; source.quote = quote; result.evidence.add(source);
        result.explanation = 'The repeated wording may be unnecessary for the required behavior.';
        result.recommendation = 'Review a more concise equivalent after checking its purpose.';
        result.preserve = 'Required behavior and conditional routing.';
        result.validation = 'Compare expected behavior before adopting the proposed change.';
        return result;
    }
    private static OhmDTO.AgentModel graph() {
        OhmDTO.AgentModel result = new OhmDTO.AgentModel();
        OhmDTO.AgentNode agent = new OhmDTO.AgentNode();
        agent.id = PID; agent.developerName = 'Weather_v1'; agent.masterLabel = 'Weather';
        agent.instructions = 'Help users retrieve a weather forecast.';
        agent.sourceKind = 'RetrievedAgentScript'; agent.sourceHash = OhmSourceImportService.sha256(agent.instructions);
        agent.sourceVersion = 'published-version'; agent.sourcePath = 'weather.agent#system'; agent.sourceBindingVerified = true;
        agent.configurationSource = 'topic forecast:\n  reasoning:\n    run @actions.LookupWeather\n';
        agent.configurationSourcePath = 'weather.agent';
        agent.configurationSourceHash = OhmSourceImportService.sha256(agent.configurationSource);
        result.agentsById.put(PID, agent);
        OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
        topic.id = TID; topic.plannerId = PID; topic.developerName = 'forecast'; topic.masterLabel = 'Forecast';
        topic.instructions = 'Ask for location. Preserve the alert branch.';
        topic.sourceKind = 'RetrievedAgentScript'; topic.sourceHash = OhmSourceImportService.sha256(topic.instructions);
        topic.sourceVersion = 'published-version'; topic.sourcePath = 'weather.agent#forecast'; topic.sourceBindingVerified = true;
        result.topics.add(topic);
        OhmDTO.ActionNode action = new OhmDTO.ActionNode();
        action.id = AID; action.plannerId = PID; action.pluginId = TID; action.developerName = 'SummarizeForecast';
        action.masterLabel = 'Summarize forecast'; action.invocationTargetType = 'generatePromptResponse';
        action.invocationTarget = 'ForecastPrompt'; action.instructions = 'Summarize the grounded forecast for the requested location.';
        action.sourceKind = 'RetrievedPromptTemplate'; action.sourceHash = OhmSourceImportService.sha256(action.instructions);
        action.sourceVersion = 'active-prompt-version'; action.sourcePath = 'ForecastPrompt.prompt#active'; action.sourceBindingVerified = true;
        action.boundModel = 'sfdc_ai__DefaultOpenAIGPT4OmniMini'; action.modelAssumed = false;
        result.actions.add(action); return result;
    }
    private static OhmReviewService.Result run(OhmDTO.AgentModel source, String mode) {
        OhmReviewService.transport = new Reviewer(mode);
        return (OhmReviewService.Result)JSON.deserialize(OhmReviewService.review(source), OhmReviewService.Result.class);
    }
    private static void rejected(OhmDTO.AgentModel source, String mode) {
        Boolean rejected = false;
        try { run(source, mode); } catch (OhmReviewService.ReviewException ex) { rejected = true; }
        System.assert(rejected, 'Expected rejection: ' + mode);
    }
    @IsTest static void semanticReviewRunsOnceAndEveryArtifactHasOwnCategories() {
        OhmDTO.AgentModel source = graph();
        OhmReviewService.Result result = run(source, 'clean');
        System.assertEquals(1, ((Reviewer)OhmReviewService.transport).calls);
        System.assertEquals(3, result.artifacts.size()); System.assertEquals(4, result.categories.size());
        System.assertEquals(OhmReviewTemplate.TEMPLATE_API_NAME, result.reviewerTemplate);
        System.assertEquals(OhmReviewTemplate.REVIEWER_MODEL, result.reviewerModel);
        for (OhmReviewService.ArtifactResult artifact : result.artifacts) {
            System.assertEquals(4, artifact.categories.size());
            System.assertEquals('A', artifact.categories[0].rating);
            System.assertEquals('UNRATED', artifact.categories[2].rating, 'Known model identity cannot prove fit.');
            System.assertEquals('Unknown', artifact.categories[2].coverageStatus);
        }
        System.assertEquals('UNRATED', result.categories[2].rating);
        System.assertEquals(source.topics[0].sourceHash, result.artifacts[1].sourceHash);
        System.assertEquals(source.topics[0].instructions.length(), result.artifacts[1].characterCount);
        System.assert(((Reviewer)OhmReviewService.transport).evidence.contains(source.actions[0].instructions));
    }
    @IsTest static void candidatesAreBAndCodeOwnsQualitativeEnvironmentalMechanism() {
        OhmReviewService.Result result = run(graph(), 'candidate');
        System.assertEquals('B', result.artifacts[1].categories[0].rating);
        System.assertEquals('A', result.artifacts[0].categories[0].rating, 'Another artifact issue must not invent a local issue.');
        System.assertEquals('B', result.categories[0].rating);
        System.assertEquals('Reviewer', result.artifacts[1].categories[0].issues[0].origin);
        System.assert(result.categories[0].environmentalMechanism.contains('may reduce'));
    }
    @IsTest static void hardBudgetIsAConfiguredRuleNotRemovabilityOrSavings() {
        OhmDTO.AgentModel source = graph(); source.topics[0].instructions = 'x'.repeat(4004);
        source.topics[0].sourceHash = OhmSourceImportService.sha256(source.topics[0].instructions);
        OhmReviewService.Result result = run(source, 'clean');
        System.assertEquals('C', result.artifacts[1].categories[0].rating);
        System.assertEquals('C', result.categories[0].rating);
        OhmReviewService.Issue rule = result.artifacts[1].categories[0].issues[0];
        System.assertEquals('Rule', rule.origin); System.assertEquals('INPUT_HARD_BUDGET', rule.code);
        System.assert(rule.explanation.contains('Configured source review budget exceeded'));
        System.assert(rule.recommendation.contains('do not trim required behavior'));
        System.assertEquals(1000, result.artifacts[1].hardBudgetTokens);
    }
    @IsTest static void softBudgetAloneDoesNotDemoteSemanticReview() {
        OhmDTO.AgentModel source = graph(); source.topics[0].instructions = 'x'.repeat(2400);
        source.topics[0].sourceHash = OhmSourceImportService.sha256(source.topics[0].instructions);
        System.assertEquals('A', run(source, 'clean').artifacts[1].categories[0].rating);
    }
    @IsTest static void missingEvidenceRemainsUnknownWhileCandidatesRemainVisible() {
        OhmReviewService.Result result = run(graph(), 'partial');
        System.assertEquals('UNRATED', result.categories[0].rating); System.assertEquals('Partial', result.categories[0].coverageStatus);
        result = run(graph(), 'candidatePartial');
        System.assertEquals('B', result.categories[0].rating); System.assertEquals('Partial', result.categories[0].coverageStatus);
        System.assertEquals(2, result.categories[0].assessedArtifactCount);
    }
    @IsTest static void knownModelCandidateRetainsUnknownEvaluationCoverage() {
        OhmReviewService.Result result = run(graph(), 'modelCandidate');
        System.assertEquals('B', result.artifacts[2].categories[2].rating);
        System.assertEquals('Unknown', result.artifacts[2].categories[2].coverageStatus);
        System.assertEquals('B', result.categories[2].rating);
        System.assertEquals('Unknown', result.categories[2].coverageStatus);
        rejected(graph(), 'unknownModelClaim');
    }
    @IsTest static void configurationIsQuotableWithoutBeingCountedAsInstructionInput() {
        OhmDTO.AgentModel source = graph();
        OhmReviewService.Result result = run(source, 'configuration');
        System.assertEquals(3, result.artifacts.size()); System.assertEquals(1, result.contextSources.size());
        System.assertEquals(null, result.contextSources[0].instructions, 'Result stores source context metadata and exact issue quotes, not duplicate full source.');
        System.assertEquals('B', result.artifacts[1].categories[3].rating);
        System.assertEquals('configuration:' + PID, result.artifacts[1].categories[3].issues[0].evidence[0].artifactId);
        OhmReviewService.Evidence input = (OhmReviewService.Evidence)JSON.deserialize(((Reviewer)OhmReviewService.transport).evidence, OhmReviewService.Evidence.class);
        System.assertEquals(source.agentsById.get(PID).configurationSource, input.contextSources[0].instructions);
        System.assertEquals(TokenEstimator.approxTokens(source.agentsById.get(PID).instructions), result.artifacts[0].estimatedTokens);
    }
    @IsTest static void missingConfigurationDoesNotBecomeCleanCallCoverage() {
        OhmDTO.AgentModel source = graph(); source.agentsById.get(PID).configurationSource = null;
        OhmReviewService.Result result = run(source, 'clean');
        System.assertEquals('UNRATED', result.categories[3].rating); System.assertEquals('Unknown', result.categories[3].coverageStatus);
    }
    @IsTest static void emptyInstructionsStayVisibleWithoutAffirmativeInputOrOutputCoverage() {
        OhmDTO.AgentModel source = graph();
        source.agentsById.get(PID).instructions = '';
        source.agentsById.get(PID).sourceHash = OhmSourceImportService.sha256('');
        source.actions[0].instructions = ' \n\t ';
        source.actions[0].sourceHash = OhmSourceImportService.sha256(source.actions[0].instructions);
        OhmReviewService.Result result = run(source, 'clean');
        System.assertEquals(3, result.artifacts.size(), 'Empty published artifacts remain visible.');
        for (Integer index : new List<Integer>{0,2}) {
            for (Integer categoryIndex : new List<Integer>{0,1}) {
                OhmReviewService.Category category = result.artifacts[index].categories[categoryIndex];
                System.assertEquals('UNRATED', category.rating);
                System.assertEquals('Unknown', category.coverageStatus);
                System.assert(category.assessment.contains('No authored instruction text'));
            }
            System.assertEquals('A', result.artifacts[index].categories[3].rating,
                'Verified nonblank configuration still supports a static call assessment.');
        }
        System.assertEquals('UNRATED', result.categories[0].rating);
        System.assertEquals('Partial', result.categories[0].coverageStatus);
    }
    @IsTest static void configurationCandidateOnEmptyInstructionKeepsBWithUnknownCoverage() {
        OhmDTO.AgentModel source = graph(); source.topics[0].instructions = '';
        source.topics[0].sourceHash = OhmSourceImportService.sha256('');
        OhmReviewService.Result result = run(source, 'emptyInstructionCandidate');
        System.assertEquals('B', result.artifacts[1].categories[0].rating);
        System.assertEquals('Unknown', result.artifacts[1].categories[0].coverageStatus);
        System.assertEquals('B', result.categories[0].rating);
        System.assertEquals('Partial', result.categories[0].coverageStatus);
    }
    @IsTest static void whitespaceConfigurationCannotEstablishStaticCallCoverage() {
        OhmDTO.AgentModel source = graph(); source.agentsById.get(PID).configurationSource = ' \n\t ';
        source.agentsById.get(PID).configurationSourceHash = OhmSourceImportService.sha256(' \n\t ');
        OhmReviewService.Result result = run(source, 'clean');
        System.assertEquals(0, result.contextSources.size());
        System.assertEquals('UNRATED', result.categories[3].rating);
        System.assertEquals('Unknown', result.categories[3].coverageStatus);
        System.assertEquals('A', run(graph(), 'clean').categories[3].rating,
            'The same review has known static scope when nonblank verified configuration is supplied.');
    }
    @IsTest static void deterministicAlternativeCannotBeGroundedOnlyInExistingConfigurationCode() {
        rejected(graph(), 'deterministicCodeOnly');
        System.assertEquals(1, ((Reviewer)OhmReviewService.transport).calls,
            'The invalid semantic candidate is rejected after review, never silently converted to a clean result.');
    }
    @IsTest static void deterministicAlternativeCanCiteActualPromptComputationInstructions() {
        OhmDTO.AgentModel source = graph();
        source.actions[0].instructions = 'Calculate the sum of the supplied invoice line amounts and return the total.';
        source.actions[0].sourceHash = OhmSourceImportService.sha256(source.actions[0].instructions);
        OhmReviewService.Result result = run(source, 'deterministicInstruction');
        System.assertEquals('B', result.artifacts[2].categories[3].rating);
        System.assertEquals('CALLS_DETERMINISTIC_ALTERNATIVE', result.artifacts[2].categories[3].issues[0].code);
        System.assertEquals(AID, result.artifacts[2].categories[3].issues[0].evidence[0].artifactId);
        System.assertEquals(source.actions[0].instructions, result.artifacts[2].categories[3].issues[0].evidence[0].quote);
        System.assertEquals('B', result.categories[3].rating);
        source.actions[0].instructions = 'Set a total by adding the supplied invoice line amounts.';
        source.actions[0].sourceHash = OhmSourceImportService.sha256(source.actions[0].instructions);
        System.assertEquals('B', run(source, 'deterministicInstruction').artifacts[2].categories[3].rating,
            'Ordinary English beginning with set is not confused with explicit set-at-variable DSL.');
    }
    @IsTest static void deterministicAlternativeRejectsCodeOnlyQuotesInsideAnInstructionArtifact() {
        OhmDTO.AgentModel source = graph();
        source.actions[0].instructions = 'run @actions.LookupWeather\n'
            + 'set @variables.total = @outputs.total\n'
            + 'with "Input:amount" = @variables.amount\n'
            + 'if @variables.total:\nelse:';
        source.actions[0].sourceHash = OhmSourceImportService.sha256(source.actions[0].instructions);
        rejected(source, 'deterministicInstruction');
        System.assertEquals(1, ((Reviewer)OhmReviewService.transport).calls,
            'Code embedded in an instruction artifact cannot qualify as a model-computation instruction.');
    }
    @IsTest static void exactEvidenceCanCompareArtifactsButCannotInventOrBorrowUnrelatedQuotes() {
        System.assertEquals('B', run(graph(), 'crossArtifact').artifacts[1].categories[0].rating);
        rejected(graph(), 'falseQuote'); rejected(graph(), 'foreignQuote'); rejected(graph(), 'ownerMismatch');
    }
    @IsTest static void categoryAndArtifactCoverageMustBeCompleteAndUnique() {
        for (String mode : new List<String>{'missingArtifact','duplicateArtifact','missingCategory','duplicateCategory'}) rejected(graph(), mode);
    }
    @IsTest static void flatRowsRequireExactCompleteAliasesWithoutGuessingOrNestedRecovery() {
        for (String mode : new List<String>{'missingRow','duplicateRow','unknownAlias','realIdAsAlias','contextAsArtifact','nestedResponse',
            'bundleCase','statusCase','categoryCase'}) {
            rejected(graph(), mode);
        }
    }
    @IsTest static void aliasOrderingUsesRealSourceIdentityInsteadOfGraphListOrder() {
        OhmDTO.AgentModel source = graph();
        OhmDTO.TopicNode extra = (OhmDTO.TopicNode)JSON.deserialize(JSON.serialize(source.topics[0]), OhmDTO.TopicNode.class);
        extra.id = '16k000000000002AAA'; extra.developerName = 'alerts';
        source.topics.add(extra);
        run(source, 'clean');
        String before = ((Reviewer)OhmReviewService.transport).evidence;
        source.topics = new List<OhmDTO.TopicNode>{source.topics[1], source.topics[0]};
        OhmReviewService.Result result = run(source, 'clean');
        String after = ((Reviewer)OhmReviewService.transport).evidence;
        System.assertEquals(before, after, 'Reordering inventory cannot change the model-visible aliases or evidence order.');
        Set<String> actualIds = new Set<String>{PID,TID,AID,extra.id};
        for (OhmReviewService.ArtifactResult artifact : result.artifacts) {
            System.assert(actualIds.contains(artifact.artifactId), 'Final artifact identities remain the original source IDs.');
        }
    }
    @IsTest static void aliasRowsAndQuotesMapBackToRealSourceIdentities() {
        OhmReviewService.Result result = run(graph(), 'crossArtifact');
        OhmReviewService.Evidence input = (OhmReviewService.Evidence)JSON.deserialize(((Reviewer)OhmReviewService.transport).evidence, OhmReviewService.Evidence.class);
        System.assertEquals('artifact_1', input.artifacts[0].artifactId);
        System.assertEquals('artifact_2', input.artifacts[1].artifactId);
        System.assertEquals('artifact_3', input.artifacts[2].artifactId);
        System.assertEquals('configuration_1', input.contextSources[0].artifactId);
        System.assertEquals(PID, result.artifacts[0].artifactId);
        System.assertEquals(TID, result.artifacts[1].categories[0].issues[0].evidence[0].artifactId);
        System.assertEquals(PID, result.artifacts[1].categories[0].issues[0].evidence[1].artifactId);
        result = run(graph(), 'configuration');
        System.assertEquals('configuration:' + PID, result.artifacts[1].categories[3].issues[0].evidence[0].artifactId);
        System.assertEquals('configuration:' + PID, result.contextSources[0].artifactId);
    }
    @IsTest static void flatRowsMayArriveInAnyOrderButCodeOwnsFinalOrder() {
        OhmReviewService.Result result = run(graph(), 'reordered');
        System.assertEquals(PID, result.artifacts[0].artifactId);
        System.assertEquals('INPUT', result.artifacts[0].categories[0].id);
        System.assertEquals('CALLS', result.categories[3].id);
    }
    @IsTest static void semanticCodesCannotForgeRulesGradesOrNumericClaims() {
        for (String mode : new List<String>{'wrongCode','unknownIssue','inventedGrade','numeric','unit','longProse'}) rejected(graph(), mode);
    }
    @IsTest static void exactOriginalQuotesMayContainNumerals() {
        OhmDTO.AgentModel source = graph(); source.topics[0].instructions = 'Return 3 grounded forecast details.';
        source.topics[0].sourceHash = OhmSourceImportService.sha256(source.topics[0].instructions);
        System.assertEquals('B', run(source, 'numericQuote').artifacts[1].categories[0].rating);
    }
    @IsTest static void staleImportedOrMissingSourceCannotReachTheReviewer() {
        for (String kind : new List<String>{'badHash','imported','missing'}) {
            OhmDTO.AgentModel source = graph();
            if (kind == 'badHash') source.topics[0].sourceHash = 'wrong';
            if (kind == 'imported') source.topics[0].sourceKind = 'ImportedAgentScript';
            if (kind == 'missing') source.topics[0].instructions = null;
            rejected(source, 'clean'); System.assertEquals(0, ((Reviewer)OhmReviewService.transport).calls);
        }
    }
    @IsTest static void sourceAndReplyBoundsFailWithoutTruncationOrFallback() {
        OhmDTO.AgentModel source = graph(); source.topics[0].instructions = 'x'.repeat(60001);
        source.topics[0].sourceHash = OhmSourceImportService.sha256(source.topics[0].instructions);
        rejected(source, 'clean'); System.assertEquals(0, ((Reviewer)OhmReviewService.transport).calls);
        rejected(graph(), 'oversized'); rejected(graph(), 'failure');
    }
    @IsTest static void repeatedExactLinesAreCodeFactsAndDoNotInventSemanticIssues() {
        OhmDTO.AgentModel source = graph();
        String line = 'Preserve the forecast conditions and preserve every required alert branch before suggesting a change.';
        source.topics[0].instructions = line + '\n' + line;
        source.topics[0].sourceHash = OhmSourceImportService.sha256(source.topics[0].instructions);
        OhmReviewService.Result result = run(source, 'clean');
        System.assertEquals(1, result.artifacts[1].exactDuplicates.size());
        System.assertEquals(2, result.artifacts[1].exactDuplicates[0].occurrences);
        System.assertEquals('A', result.artifacts[1].categories[0].rating);
    }
}
