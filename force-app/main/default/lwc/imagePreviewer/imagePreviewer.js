import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import IMAGE_URL_FIELD from '@salesforce/schema/Product2.Fake_Store_Image_URL__c';

export default class ImagePreviewer extends LightningElement {
    @api recordId;

    _imageUrl;

    @wire(getRecord, { recordId: '$recordId', fields: [IMAGE_URL_FIELD] })
    product;

    @api
    get imageUrl() {
        return this._imageUrl || getFieldValue(this.product.data, IMAGE_URL_FIELD);
    }

    set imageUrl(value) {
        this._imageUrl = value;
    }
}
