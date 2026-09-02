const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    // @sa11y/jest registers the toBeAccessible() matcher via its setup module.
    setupFilesAfterEnv: [
        ...(jestConfig.setupFilesAfterEnv || []),
        '<rootDir>/jest-sa11y-setup.js'
    ],
    collectCoverageFrom: [
        ...(jestConfig.collectCoverageFrom || []),
        '!force-app/main/default/lwc/ohmTestData/**',
        '!force-app/main/default/lwc/**/__tests__/**'
    ],
    coverageThreshold: {
        global: {
            statements: 80,
            branches: 65,
            functions: 80,
            lines: 80
        }
    }
};
