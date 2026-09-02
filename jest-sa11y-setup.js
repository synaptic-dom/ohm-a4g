// Registers the @sa11y/jest `toBeAccessible()` matcher for every test.
// v8 no longer auto-registers on import, so we call the registrar explicitly.
const { registerSa11yMatcher } = require('@sa11y/jest');

registerSa11yMatcher();
