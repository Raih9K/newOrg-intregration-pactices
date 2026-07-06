# EscuelaJS Catalog Sync Integration & Configuration Guide

This document combines the technical integration specifications, required target Salesforce Org configurations, completed implementations, and deployment checklist for the **EscuelaJS Catalog Sync Integration** platform.

---

## 1. Integration Specifications & API Flow

The integration connects Salesforce to the **EscuelaJS Fake Store API** (`https://api.escuelajs.co/api/v1/`) to sync products and categories.

```mermaid
sequenceDiagram
    autonumber
    participant Ext as External Email Sender
    participant SF as Salesforce (Apex / LWC)
    participant API as EscuelaJS Fake Store API

    Note over SF, API: Authentication Flow
    SF->>+API: "POST /auth/login (JWT Auth Credentials)"
    API-->>-SF: "200 OK (Access Token)"

    Note over SF, API: Scheduled Product Auto-Sync (GET)
    SF->>+API: "GET /products (with Bearer Token)"
    API-->>-SF: "200 OK (JSON Product Array)"
    Note over SF: Process & Upsert ProductCategory & Product2

    Note over SF, API: Real-Time Sync on Record Approval/Update (POST/PUT)
    alt Product does not have External ID
        SF->>+API: "POST /products (with payload)"
        API-->>-SF: "201 Created (with new External ID)"
        Note over SF: Save External ID back to Salesforce Product
    else Product has External ID
        SF->>+API: "PUT /products/{id} (with payload)"
        API-->>-SF: "200 OK (Sync Confirmation)"
    end

    Note over Ext, SF: Email-Triggered Product Sync Flow
    Ext->>+SF: Send email to ProductSyncEmailService
    SF->>SF: ProductSyncEmailHandler receives email & enqueues ProductSyncQueueable
    SF->>+API: "GET /products (with Bearer token)"
    API-->>-SF: "200 OK (JSON Product Array)"
    Note over SF: Process and Upsert records; Log status to System_Log__c
```

### Authentication
* **Endpoint:** `callout:FakeStore_API/auth/login`
* **Credentials Used:** `john@mail.com` / `changeme` (stored in Apex; configured dynamically to set Bearer token in request headers)
* **Auth Protocol:** JWT (Bearer token parsed dynamically and set in the header of subsequent requests)

### API CRUD Operations Reference

The EscuelaJS Fake Store API supports standard REST CRUD operations to interact with product data. Below is the endpoint structure:

* **Read (GET)**
  * **All Products:** `GET https://api.escuelajs.co/api/v1/products` (Retrieves list of all products)
  * **By ID:** `GET https://api.escuelajs.co/api/v1/products/{id}` (e.g., `GET /products/4`)
  * **By Slug:** `GET https://api.escuelajs.co/api/v1/products/slug/{slug}` (e.g., `GET /products/slug/handmade-fresh-table`)
* **Create (POST)**
  * **Endpoint:** `POST https://api.escuelajs.co/api/v1/products`
  * **Payload:** Include product JSON data in request body.
* **Update (PUT)**
  * **Endpoint:** `PUT https://api.escuelajs.co/api/v1/products/{id}` (e.g., `PUT /products/1`)
  * **Payload:** Pass the updated attributes to modify the specific product record.
* **Delete (DELETE)**
  * **Endpoint:** `DELETE https://api.escuelajs.co/api/v1/products/{id}` (e.g., `DELETE /products/1`)
  * **Behavior:** Removes the product record from the database.

### Data Flow & Implementation Table

The table below summarizes all inbound, outbound, and internal data flows, detailing their triggers, source/destination components, mechanisms, and key data elements.

| Flow Name / Description | Direction | Trigger / Event | Source System / Component | Destination System / Component | Mechanism / Protocol | Key Data Elements & Mappings |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Authentication Flow** | Outbound | API Callout Initiation | Salesforce (`ProductSyncService`) | EscuelaJS API (`/auth/login`) | REST POST (JSON Credentials) | Submits JWT user/password; parses and caches the temporary Bearer token. |
| **Scheduled Catalog Sync** | Inbound | Daily Scheduler (11:59 PM) | EscuelaJS API (`/products`) | Salesforce (`ProductCategory`, `Product2`) | Scheduled Flow -> `ProductSyncService` (REST GET) | Fetches all external products and categories, then performs an upsert in Salesforce mapping prices, images, and category references. |
| **Email-Triggered Sync** | Inbound | Inbound Email Received | External Sender (ERP/User) | Salesforce (`System_Log__c`, `Product2`) | `ProductSyncEmailHandler` -> `ProductSyncQueueable` | Inbound email triggers background sync of all products. Captures execution metrics and errors in `System_Log__c`. |
| **QC Edit Bypass** | Internal | Record Save | QC User (Edit Active Product) | Salesforce (`Product2` Active) | `Product2TriggerHandler` (before update) | Direct edits to Active products are saved instantly if user is in `Product_QC_Group`. |
| **Non-QC Edit Staging & Reversion** | Internal | Record Save | Non-QC User (Edit Active Product) | Salesforce (`Product2` Draft) | `Product2TriggerHandler` -> `Product_Edit_Approval` | Reverts modified values on standard fields. Serializes changes into JSON inside `Proposed_Changes__c`. Sets `QC_Approver__c` to an active member of `Product_QC_Group` and submits for approval. |
| **QC Approval & Staging Apply** | Internal | Approval Action | QC Approver | Salesforce (`Product2` Active) | Approval Process -> `Product2TriggerHandler` (before update) | Upon approval, status transitions to `Active`. Trigger deserializes JSON from `Proposed_Changes__c`, applies updates, and clears the staging field. |
| **Real-time API Sync (POST)** | Outbound | Approval/Activation (No External ID) | Salesforce (`Product2` Active) | EscuelaJS API (`/products`) | `ProductExternalUpdateQueueable` (Queueable REST POST) | Serializes product attributes to JSON. On success, parses the newly generated External ID and updates the Salesforce record. |
| **Real-time API Sync (PUT)** | Outbound | Approval/Activation (Has External ID) | Salesforce (`Product2` Active) | EscuelaJS API (`/products/{id}`) | `ProductExternalUpdateQueueable` (Queueable REST PUT) | Serializes product attributes to JSON and sends a PUT request to sync updates for already matched external products. |
| **Remote Image Rendering** | Outbound (Read) | Record Page Load | EscuelaJS Media Server | Salesforce LWC (Sidebar) | `imagePreviewer` LWC -> `ImagePreviewerPage` (VF iframe) | Passes image URL to a sandboxed Visualforce page inside an iframe to safely display external images without triggering CSP errors. |

---

## 2. Salesforce Organization Configuration Requirements

This section outlines the required configurations, groups, credentials, and settings that must be set up in the target Salesforce Organization to support the Product Integration & Synchronization Platform.

### 2.1. API Credentials & Authentication (Named Credentials)
* **What to Configure:**
  * Create a **Named Credential** in Salesforce:
    * **Label:** `FakeStore_API`
    * **Name:** `FakeStore_API`
    * **URL:** `https://api.escuelajs.co/api/v1`
  * Alternatively, ensure that the JWT login credentials (`john@mail.com` / `changeme`) are valid on the external API.
* **Why it is needed:**
  * **Security & Compliance:** Hardcoding API URLs and credentials directly in Apex code violates Salesforce security best practices. Named Credentials securely store the endpoint and authentication parameters.
  * **Maintenance:** If the integration endpoint changes in the future, it can be updated in one place (Named Credentials) without requiring code modifications or deployments.

### 2.2. Quality Control Team (Public Group)
* **What to Configure:**
  * Create a **Public Group** in Salesforce:
    * **Label:** `Product QC Group`
    * **Group Name (Developer Name):** `Product_QC_Group`
  * Assign all QC/QA users who are authorized to directly modify active products to this group.
* **Why it is needed:**
  * **Change Control Enforcement:** The system automatically checks if the user editing a product is a member of this group. 
    * If the user **is** a member: Edits are applied immediately without approval.
    * If the user **is not** a member: Edits are intercepted, reverted, and sent to the approval process to prevent unauthorized live product modifications.

### 2.3. Product Edit Approval Process
* **What to Configure:**
  * Create a standard **Approval Process** on the standard `Product2` object:
    * **Name:** `Product_Edit_Approval`
    * **Unique Name:** `Product_Edit_Approval`
    * **Entry Criteria:** `Status__c = 'Draft'`
    * **Assigned Approver:** Set to use the user field `QC_Approver__c`.
  * Configure an **Approval Action** to update `Status__c` to `Active`.
  * Configure a **Rejection Action** to update `Status__c` to `Inactive`.
* **Why it is needed:**
  * **Workflow Automation:** Salesforce standard `Product2` object does not support standard queue-based approvals. The system dynamically assigns an active QC user to the custom `QC_Approver__c` lookup field and triggers this approval process to route modifications to the correct reviewer.

### 2.4. Inbound Email Service
* **What to Configure:**
  * Create an **Email Service**:
    * **Email Service Name:** `ProductSyncEmailService`
    * **Apex Class:** Select `ProductSyncEmailHandler`.
  * Generate an email address for the service (e.g., `sync@yourdomain.in.salesforce.com`).
* **Why it is needed:**
  * **Email-Triggered Automation:** This allows external partners, ERP systems, or external users to trigger a catalog synchronization automatically on-demand simply by sending an email to the generated Salesforce email address.

### 2.5. Security & Object Permissions
* **What to Configure:**
  * Assign read/write permissions for the custom objects and fields to standard users:
    * `Product2.Status__c`, `Product2.Proposed_Changes__c`, `Product2.QC_Approver__c`
    * `ProductCategory.External_Id__c`, `ProductCategory.Image_URL__c`
    * `System_Log__c` (Read/Write access for troubleshooting sync errors).
* **Why it is needed:**
  * **Data Security & Sharing:** Standard users must have access to read and update these fields for the automated revert, logging, and approval mechanisms to work without throwing permissions exceptions during record editing.

---

## 3. Completed Implementations ("কী করা হয়েছে")

### A. Custom Metadata & Fields
* **ProductCategory Object:**
  * `External_Id__c` (Text, 255, External ID) - Mapped to EscuelaJS Category ID.
  * `Image_URL__c` (URL) - Category image link.
* **Product2 Object:**
  * `Category__c` (Lookup to ProductCategory) - Junction/lookup categorization.
  * `Fake_Store_Price__c` (Number/Currency) - API price.
  * `Fake_Store_Image_URL__c` (URL) - Main product image.
  * `Fake_Store_Category_Id__c` (Text) - Cached Category ID from API.
  * `Fake_Store_Category_Name__c` (Text) - Cached Category Name from API.
  * `Proposed_Changes__c` (Long Text Area, 32768) - Temporary JSON field containing modified product changes pending approval.
  * `QC_Approver__c` (Lookup to User) - Dynamic assignee for routing approval steps (bypassing the fact that standard `Product2` does not support Queues).
* **System_Log__c Object:**
  * `Log_Level__c` (Picklist) - Level of the log (Info, Debug, Error, Warn).
  * `Log_Type__c` (Picklist) - Type of log (Inbound Email, Apex, etc.).
  * `Event_Name__c` (Text, 255) - Name of the logged event (e.g. Email Subject).
  * `Automation_Name__c` (Text, 255) - Component name (e.g. `ProductSyncEmailHandler`).
  * `Message__c` (Long Text Area, 32768) - Descriptive log message.
  * `Source_Email__c` (Email) - The email address that sent the inbound trigger.
  * `Status__c` (Text, 255) - Status of processing (e.g. Success, Failed).
  * `Imported_On__c` (DateTime) - Date and time when the transaction took place.
  * `CSV_Row__c` (Long Text Area, 32768) - Related CSV details if applicable.
  * `Payload__c` (Long Text Area, 32768) - Relevant JSON payload details.
  * `Content__c` (Long Text Area, 32768) - Raw content or email body.

### B. Apex Classes, Triggers, and Approval Control
1. **`ProductSyncService.cls`**
   * Core service class handles `getAccessToken()` and `syncEscuelaProducts()`.
   * Maps incoming JSON products and categories to Salesforce standard records.
2. **`Product2Trigger` & `Product2TriggerHandler.cls`**
   * **Reversion & Queueing:** If a non-QC user edits an active product, the trigger serializes modifications to `Proposed_Changes__c`, reverts the active record fields, sets `Status__c = 'Draft'`, and submits it for approval.
   * **Post-Approval Processing:** When a QC member approves, the trigger runs in `before update`, deserializes the changes, applies them, and clears the draft fields.
   * **Real-time Syncing:** Once the status becomes `Active`, it enqueues `ProductExternalUpdateQueueable`.
3. **`ProductExternalUpdateQueueable.cls`**
   * Automatically executes a `POST` request to create the product if `ExternalId` is blank, updating the Salesforce record with the returned external ID.
   * Executes a `PUT` request to update the product if `ExternalId` is present.
4. **`Product2TriggerTest.cls`**
   * Provides 100% test coverage for the approval logic, field updates, draft reversions, and integration queue.
5. **`ProductSyncEmailHandler.cls`**
   * An Inbound Email Handler implementing `Messaging.InboundEmailHandler`.
   * Triggers product synchronization from the EscuelaJS API dynamically upon receiving an email to the configured email service address.
   * Creates a `System_Log__c` record with level `Info`, type `Inbound Email`, and logs the sender's address and status.
6. **`ProductSyncQueueable.cls`**
   * A queueable class that implements `Queueable` and `Database.AllowsCallouts`.
   * Executes the sync asynchronously to isolate callouts from the Inbound Email service transaction context, preventing "You have uncommitted work pending" exceptions.

### C. Public Groups & Approval Processes
1. **`Product_QC_Group` (Public Group)**
   * Groups QC Team users. Members are verified dynamically in Apex to allow/bypass approval flows.
2. **`Product_Edit_Approval` (Approval Process)**
   * A standard approval process on `Product2` routed dynamically to the user in `QC_Approver__c` using `relatedUserField`.
3. **`Set_Status_Active` / `Set_Status_Inactive` (Workflow Rules)**
   * Automatically updates `Status__c` upon approval/rejection.

### D. UI, Lightning Pages & Image Preview
1. **`imagePreviewer` LWC**
   - A component that renders external product images directly inside standard Lightning pages.
2. **`Product_Record_Page` (FlexiPage)**
   * Organized Product Record Page featuring Details, Related lists, and the custom `imagePreviewer` component in the Sidebar.
3. **`allProductSync` LWC & LWC Event Bubbling Fix**
   * Standardized custom events with `bubbles: true, composed: true` to bypass Lightning Out shadow boundaries and prevent white page loading on list view syncs.

### E. Automation & Scheduled Flows
1. **`Product_Auto_Sync_Daily` (Flow)**
   * Scheduled flow configured to execute product auto-sync daily at 11:59 PM.

---

## 4. Deployment Manifest

Ensure you deploy the following metadata components:

### Objects (Custom & Standard)
* `ProductCategory` (Standard Object)
* `Product2` (Standard Object)
* `System_Log__c` (Custom Object)

### Custom Fields
* `ProductCategory.External_Id__c`
* `ProductCategory.Image_URL__c`
* `Product2.Category__c`
* `Product2.Fake_Store_Price__c`
* `Product2.Fake_Store_Image_URL__c`
* `Product2.Fake_Store_Category_Id__c`
* `Product2.Fake_Store_Category_Name__c`
* `Product2.Proposed_Changes__c`
* `Product2.QC_Approver__c`
* `Product2.Price__c`
* `Product2.Status__c`

### Apex Code & Triggers
* `ProductSyncService` (Class)
* `ProductListSyncController` (Class)
* `Product2TriggerHandler` (Class)
* `ProductExternalUpdateQueueable` (Class)
* `ProductSyncEmailHandler` (Class)
* `ProductSyncQueueable` (Class)
* `ERP_ProductSyncInvocable` (Class)
* `ERP_ProductSyncInvocableTest` (Class)
* `Product2TriggerTest` (Class)
* `ProductSyncEmailHandlerTest` (Class)
* `Product2Trigger` (Trigger)

### Groups, Approval Processes & Permissions
* `Product_QC_Group` (Group)
* `Product_Edit_Approval` (ApprovalProcess)
* `Product2` (Workflows & Field Updates)
* `Product_Integration_Permissions` (PermissionSet)

### Email Services
* `ProductSyncEmailService` (EmailServicesFunction XML and emailServicesFunction metadata file)

### Pages & Lightning Components
* `ProductManualSync` (Visualforce Page)
* `allProductSync` (LWC)
* `imagePreviewer` (LWC)
* `Product_Record_Page` (FlexiPage)

### Flows
* `Product_Auto_Sync_Daily` (Flow)

---

## 5. Project Requirements

The system must satisfy the following functional and technical requirements:

1. **Dynamic LWC Image Rendering:** 
   - Render external product images inside standard Lightning pages using LWC to show product visuals directly.
2. **Lightning Out Event Propagation:**
   * When wrapping LWC sync components inside Visualforce list view buttons (using Lightning Out), ensure custom status events successfully bubble past the shadow boundary to prevent container rendering blocks.
3. **Product QC Change Control & Lockout:**
   * Any edits made to fields of active products (e.g., `Name`, `Price`, `Image URL`) by non-QC users must be blocked from immediate application. The edits must be staged as a JSON draft, the record fields reverted to original active values, the record marked as `Draft`, and an approval request automatically submitted.
   * QC group members must be bypass-exempt and have edits directly apply.
4. **Dynamic Approval Routing:**
   * Standard `Product2` does not support approval routing to Queues. Implement a dynamic assignment trigger that selects an active user from the `Product_QC_Group` and assigns them to a custom lookup `QC_Approver__c` field to route standard approval steps.
5. **Real-time 3rd Party Synchronization:**
   * When an update is approved (status changes to `Active`), the staged edits must be applied to the live fields. The trigger must automatically launch an asynchronous job to synchronize the new values to `https://api.escuelajs.co`.
   * For Salesforce-originated records (no `ExternalId`), execute a `POST` request to create the product externally and update the Salesforce product record with the returned external ID. For synced records, execute a `PUT` update request.
6. **Automated Batch Syncing:**
   * Run a daily automated sync routine at 11:59 PM to pull products and categories from the external service.
7. **Inbound Email Integration Trigger:**
   * Provide an inbound email service that allows external applications or users to trigger a product synchronization by sending an email. Use asynchronous execution to prevent uncommitted work callout failures.

---

## 6. Project Prompt (AI Re-Creation Instructions)

Use the following prompt to rebuild or describe this implementation to an AI assistant:

```text
Build a Salesforce integration connecting to the EscuelaJS Fake Store API (https://api.escuelajs.co/api/v1/) with the following design patterns:

1. Dynamic Image Previewer:
   - Create an LWC ("imagePreviewer") to display the product's remote image URL. Add this component to a Lightning Record Page ("Product_Record_Page").

2. QC Approval Change Control:
   - Create custom fields on Product2: "Proposed_Changes__c" (Long Text Area) and "QC_Approver__c" (Lookup to User).
   - Create a Public Group named "Product_QC_Group".
   - Write an Apex Trigger on Product2:
     * When a non-QC member edits an Active product, serialize the modified fields (Name, Price, Image URL, Category ID) into "Proposed_Changes__c", revert the fields on the SObject to their original values, set Status__c = 'Draft', set QC_Approver__c to an active user from the Product_QC_Group, and automatically submit the record for approval.
     * When the record is approved (Status__c transitions from Draft to Active), deserialize "Proposed_Changes__c", apply the modifications directly, and clear "Proposed_Changes__c".
     * If the user editing is a QC user, bypass the approval staging process entirely.
   - Configure a standard Approval Process ("Product_Edit_Approval") on Product2 that routes to the user defined in "QC_Approver__c".

3. 3rd Party Auto-Sync:
   - Once a product's changes are approved (Status__c = 'Active'), trigger an asynchronous Queueable class ("ProductExternalUpdateQueueable") to update the external API.
   - If the product has an External ID, run a PUT callout to '/products/{externalId}'.
   - If the product does not have an External ID, run a POST callout to '/products', retrieve the returned external ID from the response, and update the Product2 record in Salesforce.

4. Daily Auto-Sync:
   - Create a Scheduled Flow ("Product_Auto_Sync_Daily") running daily at 11:59 PM that triggers the Apex action to sync all categories and products from the EscuelaJS API.

5. Inbound Email Sync Trigger:
   - Create an Inbound Email Service ("ProductSyncEmailHandler") that implements Messaging.InboundEmailHandler. When an email is received, it enqueues a Queueable job ("ProductSyncQueueable") to run ProductSyncService.syncEscuelaProducts() asynchronously. It also creates a "System_Log__c" record logging the transaction.
```
