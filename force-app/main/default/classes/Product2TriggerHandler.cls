// Product2TriggerHandler: Product2 object er trigger logic implement kore.
// Trailhead Reference: "Apex Triggers" (https://trailhead.salesforce.com/content/learn/modules/apex_triggers)
// "Apex Integration Services" (https://trailhead.salesforce.com/content/learn/modules/apex_integration_services)
public with sharing class Product2TriggerHandler {
    
    // Cached flag to save SOQL query if checked multiple times in a transaction
    private static Boolean isQcMemberCached;
    
    // Current user 'Product QC Group' er member kina check korar jonno method.
    // Era hole Quality Control team member jara product approve kore.
    public static Boolean isCurrentQcMember() {
        if (isQcMemberCached != null) {
            return isQcMemberCached;
        }
        List<GroupMember> members = [
            SELECT Id 
            FROM GroupMember 
            WHERE Group.DeveloperName = 'Product_QC_Group' 
              AND UserOrGroupId = :UserInfo.getUserId()
        ];
        isQcMemberCached = !members.isEmpty();
        return isQcMemberCached;
    }
    
    // Product update hobar age context trigger er main logic (Before Update).
    // Ekhane dynamic field changes track kora hoy and draft/pending state manage kora hoy.
    public void onBeforeUpdate(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        for (Product2 newProd : newProducts) {
            Product2 oldProd = oldMap.get(newProd.Id);
            
            // Product status null thakle active/inactive status setup kore neya hocche.
            String oldStatus = String.isNotBlank(oldProd.Status__c) ? oldProd.Status__c : (oldProd.IsActive ? 'Active' : 'Inactive');
            String newStatus = String.isNotBlank(newProd.Status__c) ? newProd.Status__c : (newProd.IsActive ? 'Active' : 'Inactive');
            
            // Condition 1: Product age 'Under Verify' status e chilo, ekhon approved hoye 'Active' hocche.
            // Proposed_Changes__c dynamic JSON data read kore actual fields e replace kora hobe.
            if (oldStatus == 'Under Verify' && newStatus == 'Active') {
                if (String.isNotBlank(newProd.Proposed_Changes__c)) {
                    try {
                        // JSON data deserialize kore map e neya hocche
                        Map<String, Object> changes = (Map<String, Object>) JSON.deserializeUntyped(newProd.Proposed_Changes__c);
                        
                        // Dynamic key checking and updating fields:
                        if (changes.containsKey('Name')) newProd.Name = (String) changes.get('Name');
                        if (changes.containsKey('Price__c')) newProd.Price__c = changes.get('Price__c') != null ? Decimal.valueOf(String.valueOf(changes.get('Price__c'))) : null;
                        if (changes.containsKey('Fake_Store_Price__c')) newProd.Fake_Store_Price__c = changes.get('Fake_Store_Price__c') != null ? Decimal.valueOf(String.valueOf(changes.get('Fake_Store_Price__c'))) : null;
                        if (changes.containsKey('Fake_Store_Image_URL__c')) newProd.Fake_Store_Image_URL__c = (String) changes.get('Fake_Store_Image_URL__c');
                        if (changes.containsKey('Category__c')) newProd.Category__c = (String) changes.get('Category__c');
                    } catch (Exception e) {
                        newProd.addError('Failed to deserialize proposed changes: ' + e.getMessage());
                    }
                    // Approval complete, tai temporary proposed changes path ta null kore deya hocche
                    newProd.Proposed_Changes__c = null;
                }
            }
            // Condition 2: Active product e update/edit kora hole details hold kore status 'Under Verify' korbo.
            // Ete changes gulo approve na howa porjonto original product values roll back thakbe.
            else if (oldStatus == 'Active' && newStatus == 'Active') {
                Map<String, Object> changes = new Map<String, Object>();
                Boolean hasChanged = false;
                
                // Specific monitoring fields check kora hocche. Chnage hole map e pathabo and data revert korbo.
                if (newProd.Name != oldProd.Name) {
                    changes.put('Name', newProd.Name);
                    newProd.Name = oldProd.Name; // Revert name to old value until approved
                    hasChanged = true;
                }
                if (newProd.Price__c != oldProd.Price__c) {
                    changes.put('Price__c', newProd.Price__c);
                    newProd.Price__c = oldProd.Price__c; // Revert price
                    hasChanged = true;
                }
                if (newProd.Fake_Store_Price__c != oldProd.Fake_Store_Price__c) {
                    changes.put('Fake_Store_Price__c', newProd.Fake_Store_Price__c);
                    newProd.Fake_Store_Price__c = oldProd.Fake_Store_Price__c;
                    hasChanged = true;
                }
                if (newProd.Fake_Store_Image_URL__c != oldProd.Fake_Store_Image_URL__c) {
                    changes.put('Fake_Store_Image_URL__c', newProd.Fake_Store_Image_URL__c);
                    newProd.Fake_Store_Image_URL__c = oldProd.Fake_Store_Image_URL__c;
                    hasChanged = true;
                }
                if (newProd.Category__c != oldProd.Category__c) {
                    changes.put('Category__c', newProd.Category__c);
                    newProd.Category__c = oldProd.Category__c;
                    hasChanged = true;
                }
                
                // Changes thakle Proposed_Changes__c field e JSON standard format e serialize kore data save kori
                if (hasChanged) {
                    newProd.Proposed_Changes__c = JSON.serialize(changes);
                    newProd.Status__c = 'Under Verify'; // Ekhon status change kore QC verification e pathano holo
                }
            }
        }
    }
    
    // Product update complete hole external system e sync data push korbo (After Update).
    // Apex integration limit or callout limit avoid korar jonno Queueable apex run kora hoy.
    public void onAfterUpdate(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        List<Id> productsToSync = new List<Id>();
        
        for (Product2 newProd : newProducts) {
            Product2 oldProd = oldMap.get(newProd.Id);
            
            String oldStatus = String.isNotBlank(oldProd.Status__c) ? oldProd.Status__c : (oldProd.IsActive ? 'Active' : 'Inactive');
            String newStatus = String.isNotBlank(newProd.Status__c) ? newProd.Status__c : (newProd.IsActive ? 'Active' : 'Inactive');
            
            // Product non-active status theke 'Active' hole sync trigger hobe.
            Boolean isStatusActivated = (newStatus == 'Active' && oldStatus != 'Active');
            Boolean hasFieldChanged = false;
            
            // Active records modified parameters check logic:
            if (newStatus == 'Active' && oldStatus == 'Active') {
                Map<String, Schema.SObjectField> fieldsMap = Schema.SObjectType.Product2.fields.getMap();
                for (String fieldName : fieldsMap.keySet()) {
                    // System level metadata fields context checking validation logic bad dicchi
                    if (fieldName == 'lastmodifieddate' || fieldName == 'lastmodifiedbyid' || 
                        fieldName == 'systemmodstamp' || fieldName == 'proposed_changes__c' ||
                        fieldName == 'qc_approver__c') {
                        continue;
                    }
                    if (newProd.get(fieldName) != oldProd.get(fieldName)) {
                        hasFieldChanged = true;
                        break;
                    }
                }
            }
            
            // Data modified or newly approved parameters check processing list
            if (isStatusActivated || hasFieldChanged) {
                productsToSync.add(newProd.Id);
            }
        }
        
        // Loop synchronization queueable job execute. Loop limit & system states validation check
        if (!productsToSync.isEmpty() && !System.isQueueable() && !System.isFuture()) {
            System.enqueueJob(new ProductExternalUpdateQueueable(productsToSync));
        }
    }
}
