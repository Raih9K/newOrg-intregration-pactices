// singleProductSyncAction: Quick Action modal implementation JavaScript component.
// Sobe records list navigation check runtime.
// Trailhead Reference: "Lightning Web Component Basics" (https://trailhead.salesforce.com/content/learn/modules/lightning_web_components_basics)
import { LightningElement, api, track } from 'lwc';
import syncSingleProduct from '@salesforce/apex/ProductListSyncController.syncSingleProduct';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class SingleProductSyncAction extends LightningElement {
    // Record page specific contextual variable
    @api recordId;
    @track isSyncing = true;

    _hasTriggered = false;

    // Component load validation hook
    renderedCallback() {
        // Record ID complete availability state confirmation checker
        if (this.recordId && !this._hasTriggered) {
            this._hasTriggered = true;
            setTimeout(() => {
                this.handleSync();
            }, 0);
        }
    }

    // Callout execution parameters and controller binding
    handleSync() {
        this.isSyncing = true;
        syncSingleProduct({ recordId: this.recordId })
            .then(() => {
                this.isSyncing = false;
                this.showToast('Success', 'Product synchronized to 3rd Party API successfully!', 'success');
                this.closeAction();
            })
            .catch(error => {
                this.isSyncing = false;
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Error', 'Failed to sync: ' + msg, 'error');
                this.closeAction();
            });
    }

    // Alert toast display helper method
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
            }),
        );
    }

    // Modal view window exit dispatcher action close
    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
