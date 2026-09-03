// Validate the draft-intent regex against realistic questions (no deps, no model).
Pattern DRAFT_INTENT = Pattern.compile(
  '(?is)(^\\s*(please\\s+)?(draft|rewrite|trim|tighten|shorten|condense|optimi[sz]e)\\b'
  + '|(draft|rewrit|trimm|tighten|shorten|condens|optimi[sz])\\w*\\s+(version|copy|edition)'
  + '|\\b(draft|rewrite|trim|tighten|shorten|condense|optimi[sz]e)\\s+'
  + '(the\\s+|these\\s+|this\\s+|its\\s+)?(instructions|scope|topic|prompt)\\b)');
List<String> shouldBeDraft = new List<String>{
  'Draft the trimmed instructions for this topic.',
  'Rewrite these instructions to be shorter.',
  'Can you tighten the scope?',
  'Give me a shortened version',            // inflection: shortened
  'Show me a trimmed version of the scope', // inflection: trimmed
  'Please condense the instructions.'
};
List<String> shouldBeQnA = new List<String>{
  'Why is this process wasteful?',
  'How much energy would trimming the scope reduce, and what grade would we get?', // reduce + trim
  'How do I reduce the footprint of this agent?',   // reduce
  'Is there a draft report I can see?',              // draft (noun)
  'What could we save?',
  'Explain why Lead Concierge (unoptimized) is flagged as wasteful.'
};
for (String s : shouldBeDraft) {
  Boolean m = DRAFT_INTENT.matcher(s).find();
  System.debug('OHM_RX EXPECT_DRAFT got=' + m + (m?'':'  <-- FALSE NEGATIVE') + ' :: ' + s);
}
for (String s : shouldBeQnA) {
  Boolean m = DRAFT_INTENT.matcher(s).find();
  System.debug('OHM_RX EXPECT_QNA   got=' + m + (m?'  <-- FALSE POSITIVE':'') + ' :: ' + s);
}
