import { createElement } from 'lwc';
import OhmRecommendations from 'c/ohmRecommendations';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createFindingRemediationTask';
import { mockFindings, mockVolumeAssumption } from 'c/ohmTestData';

jest.mock(
    '@salesforce/apex/OhmAuditController.createFindingRemediationTask',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function create(props = {}) {
    const el = createElement('c-ohm-recommendations', { is: OhmRecommendations });
    Object.assign(
        el,
        {
            findings: mockFindings(),
            reportId: 'AUDIT-1',
            volumeAssumption: mockVolumeAssumption()
        },
        props
    );
    document.body.appendChild(el);
    return el;
}

async function flush() {
    return Promise.resolve();
}

describe('c-ohm-recommendations', () => {
    beforeEach(() => {
        createRemediationTask.mockReset();
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders one card per finding', () => {
        const el = create();
        const cards = el.shadowRoot.querySelectorAll('[data-id="rec-card"]');
        expect(cards.length).toBe(4);
    });

    it('single h2 with data-focus-heading', () => {
        const el = create();
        expect(
            el.shadowRoot.querySelectorAll('h2[data-focus-heading]').length
        ).toBe(1);
    });

    it('create-task flow sends only the saved finding identity and flips the card', async () => {
        createRemediationTask.mockResolvedValue('00T000000000009');
        const findings = mockFindings().map((f, i) =>
            Object.assign({}, f, { id: `FIND-${i}` })
        );
        const el = create({ findings });

        const firstCard = el.shadowRoot.querySelector('[data-id="rec-card"]');
        firstCard.dispatchEvent(
            new CustomEvent('createtask', { detail: { findingId: 'FIND-0' } })
        );
        await flush();
        await flush();

        expect(createRemediationTask).toHaveBeenCalledTimes(1);
        expect(createRemediationTask).toHaveBeenCalledWith({ findingId: 'FIND-0', note: null });

        // Card now reflects the created task.
        const card = el.shadowRoot.querySelector('[data-id="rec-card"]');
        expect(card.finding.remediationTaskId).toBe('00T000000000009');
    });

    it('surfaces an error on the failing card when the Apex call rejects', async () => {
        createRemediationTask.mockRejectedValue({
            body: { message: 'DML failed' }
        });
        const findings = mockFindings().map((f, i) =>
            Object.assign({}, f, { id: `FIND-${i}` })
        );
        const el = create({ findings });

        el.shadowRoot
            .querySelector('[data-id="rec-card"]')
            .dispatchEvent(
                new CustomEvent('createtask', { detail: { findingId: 'FIND-0' } })
            );
        await flush();
        await flush();

        const card = el.shadowRoot.querySelector('[data-id="rec-card"]');
        expect(card.errorMessage).toBe('DML failed');
    });

    it('shows an empty state when there are no findings', () => {
        const el = create({ findings: [] });
        expect(el.shadowRoot.querySelector('[data-id="rec-empty"]')).not.toBeNull();
    });

    it('keeps the single dark interface accessible for existing callers', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
