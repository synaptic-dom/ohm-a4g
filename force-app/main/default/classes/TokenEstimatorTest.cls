@IsTest
private class TokenEstimatorTest {
    @IsTest
    static void test_approxTokens() {
        System.assertEquals(0, TokenEstimator.approxTokens(null), 'null -> 0');
        System.assertEquals(0, TokenEstimator.approxTokens(''), 'empty -> 0');
        System.assertEquals(1, TokenEstimator.approxTokens('abcd'), '4 chars -> 1');
        System.assertEquals(2, TokenEstimator.approxTokens('abcde'), '5 chars -> ceil(1.25)=2');
    }

    @IsTest
    static void test_canonical5200() {
        // canon C9 fixture: 5200 chars -> 1300 tokens
        String s = 'x'.repeat(5200);
        System.assertEquals(1300, TokenEstimator.approxTokens(s), '5200 chars -> 1300 tokens');
    }

    @IsTest
    static void test_promptTurnTokens_noThrow() {
        OhmDTO.AgentNode a = new OhmDTO.AgentNode();
        a.description = 'abcd';
        Integer t = TokenEstimator.promptTurnTokens(a, null, null, 10, 20);
        System.assert(t > 0, 'sums without throwing');
    }
}
