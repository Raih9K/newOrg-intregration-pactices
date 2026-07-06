import { LightningElement, track } from 'lwc';
import runManualSync from '@salesforce/apex/ProductListSyncController.runManualSync';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AllProductSync extends LightningElement {
    @track isSyncing = false;

    handleSync() {
        this.isSyncing = true;
        runManualSync()
            .then(() => {
                this.isSyncing = false;
                this.showToast('Success', 'Products synchronized successfully!', 'success');
                
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
