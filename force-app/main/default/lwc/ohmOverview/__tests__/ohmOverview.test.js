import { createElement } from 'lwc';
import OhmOverview from 'c/ohmOverview';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import { reviewSummaryFixture } from '../../../../../../test-fixtures/review/reviewFixture';
jest.mock('@salesforce/apex/OhmAuditController.getFleet', () => ({ default: jest.fn() }), { virtual: true });
async function flush() { for (let i=0;i<8;i+=1) await Promise.resolve(); }
function create() { const el=createElement('c-ohm-overview',{is:OhmOverview}); document.body.appendChild(el); return el; }
afterEach(()=>{document.body.replaceChildren(); jest.clearAllMocks();});
it('uses real review counts and sends the supported opportunity to its bundle', async()=>{
    const review=reviewSummaryFixture();
    const blank={plannerId:'P1',label:'Unreviewed',audited:false};
    getFleet.mockResolvedValue([blank,{plannerId:'P2',label:'PromptTemplateActions_v1',audited:true,reviewJson:JSON.stringify(review)}]);
    const el=create(); expect(el.shadowRoot.querySelector('c-ohm-loading-state')).not.toBeNull(); await flush();
    expect(el.shadowRoot.querySelector('[data-id="reviewed"]').textContent).toContain('1');
    expect(el.shadowRoot.querySelector('[data-id="opportunities"]').textContent).toBe('1');
    expect(el.shadowRoot.textContent).toContain('Prompt Template Actions');
    const opened=jest.fn(); el.addEventListener('openprocess',opened); el.shadowRoot.querySelector('[data-id="next"]').click();
    expect(opened.mock.calls[0][0].detail.plannerId).toBe('P2');
});
it('does not turn a hidden model rating into a visible opportunity',async()=>{
    const review=reviewSummaryFixture(); review.categories.forEach(c=>{c.rating=c.id==='MODEL'?'C':'A';});
    getFleet.mockResolvedValue([{plannerId:'P1',label:'Agent',audited:true,reviewJson:JSON.stringify(review)}]);
    const el=create(); await flush(); expect(el.shadowRoot.querySelector('[data-id="opportunities"]').textContent).toBe('0');
});
it('offers refresh on empty state and retries a failed load without invented counts',async()=>{
    getFleet.mockRejectedValueOnce(new Error('Cannot connect')).mockResolvedValue([]);
    const el=create(); await flush(); expect(el.shadowRoot.querySelector('[data-id="reviewed"]')).toBeNull();
    el.shadowRoot.querySelector('.state button').click(); await flush(); expect(el.shadowRoot.textContent).toContain('Publish an Agent Script bundle');
    expect(el.shadowRoot.querySelector('[data-id="next"]')).toBeNull();
});
it('models the fleet footprint from the rows it already loaded and labels it as modeled',async()=>{
    const review=reviewSummaryFixture();
    const audited={plannerId:'P2',label:'Customer Support',audited:true,reviewJson:JSON.stringify(review),annualCalls:109500,
        energyWhLow:33585.84,energyWhCentral:37784.07,energyWhHigh:41982.3,savingsWhLow:17082,savingsWhCentral:19217.25,savingsWhHigh:21352.5,
        co2eGLow:4198.23,co2eGCentral:11335.221,co2eGHigh:19941.59,waterMlLow:26868.67,waterMlCentral:40806.8,waterMlHigh:58775.22,
        impactAssumptions:'109500 modeled calls/year per source block.',impactFactors:{energyPerPromptWh:{low:0.24,central:0.27,high:0.3},referencePromptTokens:500,methodologyVersion:'1.0'}};
    getFleet.mockResolvedValue([{plannerId:'P1',label:'Unreviewed',audited:false},audited]);
    const el=create(); await flush();
    const strip=el.shadowRoot.querySelector('[data-id="footprint"]');
    expect(strip.footprints).toHaveLength(2);
    expect(strip.factors.referencePromptTokens).toBe(500);
    expect(strip.assumptionSummary).toContain('109500');
    expect(strip.shadowRoot.querySelector('[data-id="savings-central"]').textContent).toBe('19.2 kWh');
    expect(strip.shadowRoot.querySelector('[data-id="energy-central"]').textContent).toContain('37.8 kWh');
    expect(el.shadowRoot.firstElementChild.firstElementChild.tagName.toLowerCase()).toBe('c-ohm-footprint-strip');
    expect(strip.shadowRoot.querySelector('[data-id="badge"]').textContent).toBe('Modeled, not measured');
    expect(strip.shadowRoot.querySelector('[data-id="coverage"]').textContent).toContain('1 reviewed bundle');
});
