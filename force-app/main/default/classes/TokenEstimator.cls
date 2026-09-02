/**
 * TokenEstimator — stateless token approximation (SPEC §S.3, canon C9).
 * approxTokens = ceil(chars / 4). 5200 chars -> 1300 tokens.
 */
public with sharing class TokenEstimator {

    /** ceil(len/4); null/'' -> 0. */
    public static Integer approxTokens(String text) {
        if (String.isEmpty(text)) {
            return 0;
        }
        return (Integer) Math.ceil(text.length() / 4.0);
    }

    /**
     * Sum of tokens for one prompt turn: system text + active topic scope +
     * in-context action descriptions + history + user message, plus the
     * typical output allowance. Reference/output constants from Ohm_Constants
     * with static-final fallbacks (never throws).
     */
    public static Integer promptTurnTokens(
        OhmDTO.AgentNode a,
        OhmDTO.TopicNode activeTopic,
        List<OhmDTO.ActionNode> inContext,
        Integer historyTokens,
        Integer userMsgTokens
    ) {
        Integer total = 0;
        if (a != null) {
            total += approxTokens(a.description) + approxTokens(a.capabilities);
        }
        if (activeTopic != null) {
            total += approxTokens(activeTopic.scope) + approxTokens(activeTopic.description);
        }
        if (inContext != null) {
            for (OhmDTO.ActionNode act : inContext) {
                total += approxTokens(act.description);
            }
        }
        total += (historyTokens == null ? 0 : historyTokens);
        total += (userMsgTokens == null ? 0 : userMsgTokens);

        Integer outputAllowance;
        try {
            OhmConstants c = OhmConstants.load();
            outputAllowance = (Integer) (c.typicalOutputTokens() * c.outputWeight());
        } catch (Exception e) {
            outputAllowance = 250; // typicalOutputTokens * outputWeight fallback
        }
        return total + outputAllowance;
    }
}
