// Product2Trigger: Product2 object er trigger. Ekhane write / update context check kora hoy.
// Trailhead Reference: "Apex Triggers" (https://trailhead.salesforce.com/content/learn/modules/apex_triggers)
trigger Product2Trigger on Product2 (before update, after update) {
    // Handler class er object banano hocche
    Product2TriggerHandler handler = new Product2TriggerHandler();
    
    // Trigger.isBefore check kore jeno save hobar age validation ba changes kora jay.
    // Trigger.isUpdate check kore jeno sudhu record update hobar somoy run hoy.
    if (Trigger.isBefore && Trigger.isUpdate) {
        // before update logic run korar jonno handler call kora hocche
        handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    } 
    // Trigger.isAfter check kore jeno record save hobar por database actions ba sync callout kora jay.
    else if (Trigger.isAfter && Trigger.isUpdate) {
        // after update logic run korar jonno handler call kora hocche
        handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}

