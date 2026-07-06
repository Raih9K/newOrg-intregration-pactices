// imagePreviewer: UI preview component to display third party images.
// Record page fields tracking and dynamic data rendering handle kore.
// Trailhead Reference: "Lightning Web Component Basics" (https://trailhead.salesforce.com/content/learn/modules/lightning_web_components_basics)
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import IMAGE_URL_FIELD from '@salesforce/schema/Product2.Fake_Store_Image_URL__c';

export default class ImagePreviewer extends LightningElement {
    // Record page context parameter injection
    @api recordId;

    _imageUrl;

    // @wire: Salesforce standard database record access wire adapters
    @wire(getRecord, { recordId: '$recordId', fields: [IMAGE_URL_FIELD] })
    product;

    // API getter: record image validation values loading return
    @api
    get imageUrl() {
        return this._imageUrl || getFieldValue(this.product.data, IMAGE_URL_FIELD);
    }

    // API setter value assignment rules
    set imageUrl(value) {
        this._imageUrl = value;
    }
}
