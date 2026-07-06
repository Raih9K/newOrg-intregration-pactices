// allProductSync: Sub-component sync execution setup component.
// Salesforce LWC component code context, manual sync and message routing handle kore.
// Trailhead Reference: "Lightning Web Component Basics" (https://trailhead.salesforce.com/content/learn/modules/lightning_web_components_basics)
import { LightningElement, track } from 'lwc';
import runManualSync from '@salesforce/apex/ProductListSyncController.runManualSync';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AllProductSync extends LightningElement {
    // @track: reactive variables monitor kore, state change hole component re-render hobe.
    @track isSyncing = false;

    // Button click run synchronization logic
    handleSync() {
        this.isSyncing = true;
        // Controller class execution call logic
        runManualSync()
            .then(() => {
                this.isSyncing = false;
                this.showToast('Success', 'Products synchronized successfully!', 'success');
                
                // Parent component er sathe communicate korar jonno custom event create kore dispatch kora hocche.
                // bubbles/composed key are used for event propagation rules.
                this.dispatchEvent(new CustomEvent('syncflowcompleted', {
                    bubbles: true,
                    composed: true,
                    detail: { success: true }
                }));
            })
            .catch(error => {
                this.isSyncing = false;
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Error', 'Failed to sync: ' + msg, 'error');
                
                this.dispatchEvent(new CustomEvent('syncflowcompleted', {
                    bubbles: true,
                    composed: true,
                    detail: { success: false, error: msg }
                }));
            });
    }

    // UI screen alert or popup standard Toast Event handler method
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
            }),
        );
    }
}
