import { createElement } from 'lwc';
import OhmRecommendations from 'c/ohmRecommendations';
import getRecommendations from '@salesforce/apex/OhmAuditController.getRecommendations';
import assignFinding from '@salesforce/apex/OhmAuditController.assignFinding';

// createRemediationTask is imported by the (untouched) v1 path; stub it so the
// module resolves even though these standalone tests never exercise it.
jest.mock(
    '@salesforce/apex/OhmAuditController.createRemediationTask',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.getRecommendations',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.assignFinding',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/user/Id', () => ({ default: '005000000000USER' }), {
    virtual: true
});

function mockRecs() {
    return [
        {
            findingId: 'FIND-1',
            signal: 'INSTRUCTION_BLOAT',
            severity: 'High',
            processLabel: 'Lead Concierge',
            plannerApiName: 'Lead_Concierge',
            savingsCentralWh: 52921,
            savingsLowWh: 47041,
            savingsHighWh: 58802,
            fixType: 'Trim_Instructions',
            recommendedTarget: 'Trim the scope',
            recommendationText: 'Cut 800 excess tokens from the topic scope.',
            findingStatus: 'Open',
            taskId: null,
            effort: 'Low'
        },
        {
            findingId: 'FIND-2',
            signal: 'MODEL_RIGHTSIZING',
            severity: 'Medium',
            processLabel: 'Order Support',
            plannerApiName: 'Order_Support',
            savingsCentralWh: 16083,
            savingsLowWh: 14000,
            savingsHighWh: 18000,
            fixType: 'Downsize_Model',
            recommendedTarget: 'Use a smaller model',
            recommendationText: 'Bind the cheaper model to this action.',
            findingStatus: 'Open',
            taskId: null,
            effort: 'Medium'
        }
    ];
}

async function flush(times = 6) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

function create(props = {}) {
    const el = createElement('c-ohm-recommendations', {
        is: OhmRecommendations
    });
    el.standalone = true;
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

function cards(el) {
    return Array.from(el.shadowRoot.querySelectorAll('[data-id="card"]'));
}

describe('c-ohm-recommendations (standalone quick-wins tab)', () => {
    beforeEach(() => {
        getRecommendations.mockReset();
        assignFinding.mockReset();
        getRecommendations.mockResolvedValue(mockRecs());
        assignFinding.mockResolvedValue('00T000000000009');
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('self-fetches and renders ranked quick-win cards', async () => {
        const el = create();
        await flush();

        expect(getRecommendations).toHaveBeenCalledTimes(1);
        const c = cards(el);
        expect(c).toHaveLength(2);

        const ranks = Array.from(
            el.shadowRoot.querySelectorAll('[data-id="rank"]')
        ).map((n) => n.textContent.trim());
        expect(ranks).toEqual(['#1', '#2']);

        // savings band + effort chip render
        expect(el.shadowRoot.textContent).toContain('52,921');
        expect(el.shadowRoot.textContent).toContain('Effort: Low');
        expect(el.shadowRoot.textContent).toContain('Cut 800 excess tokens');
    });

    it('create-task calls assignFinding to the current user and flips the card', async () => {
        const el = create();
        await flush();

        el.shadowRoot.querySelector('[data-id="create-task"]').click();
        await flush();

        expect(assignFinding).toHaveBeenCalledTimes(1);
        expect(assignFinding.mock.calls[0][0]).toEqual({
            findingId: 'FIND-1',
            userId: '005000000000USER',
            dueDate: null
        });
        expect(
            el.shadowRoot.querySelector('[data-id="created"]')
        ).not.toBeNull();
    });

    it('surfaces an error on the failing card when assignFinding rejects', async () => {
        assignFinding.mockRejectedValue({ body: { message: 'DML failed' } });
        const el = create();
        await flush();

        el.shadowRoot.querySelector('[data-id="create-task"]').click();
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="card-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('DML failed');
    });

    it('shows an on-brand empty state when there are no quick wins', async () => {
        getRecommendations.mockResolvedValue([]);
        const el = create();
        await flush();

        const empty = el.shadowRoot.querySelector('[data-id="empty"]');
        expect(empty).not.toBeNull();
        expect(empty.textContent).toContain('audit a process from the Fleet tab');
    });

    it('is accessible in both Calm variants', async () => {
        const dark = create();
        await flush();
        await expect(dark).toBeAccessible();

        const calm = create({ calmMode: true });
        await flush();
        await expect(calm).toBeAccessible();
    });
});
