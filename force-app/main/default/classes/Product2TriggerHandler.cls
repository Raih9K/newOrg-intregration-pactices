public with sharing class Product2TriggerHandler {
    
    private static Boolean isQcMemberCached;
    
    // Current user 'Product QC Group' er member kina check korar jonno method
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
    
    // Product update hobar age context trigger er main logic
    public void onBeforeUpdate(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        for (Product2 newProd : newProducts) {
            Product2 oldProd = oldMap.get(newProd.Id);
            
            // Product status null thakle active/inactive status setup kore neya hocche
            String oldStatus = String.isNotBlank(oldProd.Status__c) ? oldProd.Status__c : (oldProd.IsActive ? 'Active' : 'Inactive');
            String newStatus = String.isNotBlank(newProd.Status__c) ? newProd.Status__c : (newProd.IsActive ? 'Active' : 'Inactive');
            
            // Condition 1: Product age 'Under Verify' status e chilo, ekhon approved hoye 'Active' hocche.
            // Proposed_Changes__c dynamic JSON data r rishikesh-style actual fields e replace hobe.
            if (oldStatus == 'Under Verify' && newStatus == 'Active') {
                if (String.isNotBlank(newProd.Proposed_Changes__c)) {
                    try {
                        Map<String, Object> changes = (Map<String, Object>) JSON.deserializeUntyped(newProd.Proposed_Changes__c);
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
            // Condition 2: Active product e update/edit kora hole details hold kore record status change kora.
            else if (oldStatus == 'Active' && newStatus == 'Active') {
                Map<String, Object> changes = new Map<String, Object>();
                Boolean hasChanged = false;
                
                // Niche specific monitoring fields er content updates map store hobe logic trigger call block e
                if (newProd.Name != oldProd.Name) {
                    changes.put('Name', newProd.Name);
                    newProd.Name = oldProd.Name; // Main field block e original data revert korar jonno block path
                    hasChanged = true;
                }
                if (newProd.Price__c != oldProd.Price__c) {
                    changes.put('Price__c', newProd.Price__c);
                    newProd.Price__c = oldProd.Price__c;
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
                
                // Tracked modifications thakle data JSON path store dynamic and status changes
                if (hasChanged) {
                    newProd.Proposed_Changes__c = JSON.serialize(changes);
                    newProd.Status__c = 'Under Verify'; // Ekhon Draft bad diye 'Under Verify' setup kora holo
                }
            }
        }
    }
    
    // Product update complete hole dynamic bulk integrations API sync operations execution
    public void onAfterUpdate(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        List<Id> productsToSync = new List<Id>();
        
        for (Product2 newProd : newProducts) {
            Product2 oldProd = oldMap.get(newProd.Id);
            
            String oldStatus = String.isNotBlank(oldProd.Status__c) ? oldProd.Status__c : (oldProd.IsActive ? 'Active' : 'Inactive');
            String newStatus = String.isNotBlank(newProd.Status__c) ? newProd.Status__c : (newProd.IsActive ? 'Active' : 'Inactive');
            
            // Product non-active condition state current change parameters check logic
            Boolean isStatusActivated = (newStatus == 'Active' && oldStatus != 'Active');
            Boolean hasFieldChanged = false;
            
            // Active records modified parameter checking
            if (newStatus == 'Active' && oldStatus == 'Active') {
                Map<String, Schema.SObjectField> fieldsMap = Schema.SObjectType.Product2.fields.getMap();
                for (String fieldName : fieldsMap.keySet()) {
                    // System logs and validation utility updates ignore processing
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
            
            // Data modified or newly approved parameters check queue insertion logic
            if (isStatusActivated || hasFieldChanged) {
                productsToSync.add(newProd.Id);
            }
        }
        
        // Loop synchronization job execution 
        if (!productsToSync.isEmpty() && !System.isQueueable() && !System.isFuture()) {
            System.enqueueJob(new ProductExternalUpdateQueueable(productsToSync));
        }
    }
}
