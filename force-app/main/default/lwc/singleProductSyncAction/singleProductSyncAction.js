import { LightningElement, api, track } from 'lwc';
import syncSingleProduct from '@salesforce/apex/ProductListSyncController.syncSingleProduct';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class SingleProductSyncAction extends LightningElement {
    @api recordId;
    @track isSyncing = true;

    _hasTriggered = false;

    renderedCallback() {
        // Defer execution until recordId is fully loaded and populated in the component
        if (this.recordId && !this._hasTriggered) {
            this._hasTriggered = true;
            setTimeout(() => {
                this.handleSync();
            }, 0);
        }
    }

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

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
            }),
        );
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
