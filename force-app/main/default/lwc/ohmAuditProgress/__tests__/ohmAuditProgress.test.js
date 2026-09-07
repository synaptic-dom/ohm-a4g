import { createElement } from 'lwc';
import OhmAuditProgress from 'c/ohmAuditProgress';

function create(run) {
    const element = createElement('c-ohm-audit-progress', { is: OhmAuditProgress });
    element.run = run;
    document.body.appendChild(element);
    return element;
}

describe('c-ohm-audit-progress', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); });

    it('presents backend progress and moves the active stage only when evidence changes', async () => {
        const el = create({ runStatus: 'Discovering', stageMessage: 'Retrieving published source (1 of 2)', percentComplete: 25 });
        expect(el.shadowRoot.querySelector('[role="status"]').textContent).toContain('Retrieving published source (1 of 2)');
        expect(el.shadowRoot.querySelector('[role="progressbar"]').getAttribute('aria-valuenow')).toBe('25');
        expect(el.shadowRoot.querySelector('.run__step--active').textContent).toContain('Retrieve source');
        el.run = { runStatus: 'Discovering', stageMessage: 'Validating source evidence', percentComplete: 55 };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.run__step--active').textContent).toContain('Verify version');
        el.run = { runStatus: 'Analyzing', stageMessage: 'Running efficiency signals', percentComplete: 75 };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.run__step--active').textContent).toContain('Review evidence');
    });

    it('does not invent percentage while queued or claim results are loaded when only the backend finished', async () => {
        const el = create({ runStatus: 'Queued' });
        expect(el.shadowRoot.querySelector('[role="progressbar"]')).toBeNull();
        el.run = { runStatus: 'LoadingResults', stageMessage: 'Loading the completed audit report.', percentComplete: 100 };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('h2').textContent).toBe('Preparing your review');
        expect(el.shadowRoot.textContent).not.toContain('Results below belong to this audit');
        el.run = { runStatus: 'Complete', percentComplete: 100 };
        await Promise.resolve();
        expect(el.shadowRoot.querySelectorAll('.run__step--done')).toHaveLength(3);
        expect(el.shadowRoot.querySelector('h2').textContent).toBe('Review ready');
    });

    it('shows only observed progress and keeps support links out of successful runs', async () => {
        const el = create({ reportId: 'R1', runStatus: 'Queued', percentComplete: '' });
        expect(el.shadowRoot.querySelector('[role="progressbar"]')).toBeNull();
        expect(el.shadowRoot.querySelector('.run__step--active')).toBeNull();
        expect(el.shadowRoot.querySelector('a')).toBeNull();
        el.run = { reportId: 'R1', runStatus: 'Discovering', stageMessage: 'Retrieving source for review', percentComplete: 10 };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.run__step--active').textContent).toContain('Retrieve source');
        expect(el.shadowRoot.querySelector('[role="progressbar"]').getAttribute('aria-valuenow')).toBe('10');
        el.run = { reportId: 'R1', runStatus: 'Failed', error: 'Source changed', terminal: true, percentComplete: 100 };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('[role="progressbar"]')).toBeNull();
        expect(el.shadowRoot.querySelector('.run__percent').textContent).toBe('Stopped');
        expect(el.shadowRoot.querySelector('.run__steps')).toBeNull();
        const support = el.shadowRoot.querySelector('details');
        expect(support.open).toBe(false);
        expect(support.querySelector('a').getAttribute('href')).toContain('/R1/view');
    });

    it('distinguishes a retry of a failed audit from resuming an interrupted status check', async () => {
        const el = create({ plannerId: 'P1', reportId: 'R1', runStatus: 'Failed', error: 'Version changed', terminal: true, canRetry: true });
        const handler = jest.fn();
        el.addEventListener('retry', handler);
        expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toBe('Version changed');
        expect(el.shadowRoot.querySelector('button').textContent).toBe('Retry audit');
        el.shadowRoot.querySelector('button').click();
        expect(handler.mock.calls[0][0].detail).toEqual({ plannerId: 'P1', reportId: 'R1' });
        el.run = { ...el.run, terminal: false, error: 'Connection interrupted' };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('button').textContent).toBe('Resume checking');
    });

    it('keeps progress stages and long error messages accessible in the single visual mode', async () => {
        const el = create({ plannerId: 'P1', reportId: 'R1', runStatus: 'Analyzing', stageMessage: 'Running efficiency signals', percentComplete: 75 });
        expect(el.shadowRoot.querySelector('[aria-current="step"]').getAttribute('aria-label')).toBe('Review evidence: current stage');
        expect(el.shadowRoot.querySelector('.run__step--done').textContent).toContain('✓');
        await expect(el).toBeAccessible();
        el.run = { plannerId: 'P1', reportId: 'R1', runStatus: 'Failed', error: `Source retrieval failed for ${'LongSalesforcePublicationName'.repeat(12)}. Retry the audit.`, terminal: true, canRetry: true };
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toBe(el.run.error);
        await expect(el).toBeAccessible();
    });
});
