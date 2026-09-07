import { LightningElement, api } from 'lwc';
export default class OhmLoadingState extends LightningElement {
    @api heading = 'Bringing your workspace together';
    @api detail = 'Reading your published bundles and their latest reviews.';
}
