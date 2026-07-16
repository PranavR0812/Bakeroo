# Bakeroo Cloud Kitchen — Admin Phase Summary

> **Purpose.** A consolidated record of the **data-model + admin-configuration phase** — what was
> built, what is still open, and what was deliberately left out of scope. It complements the
> forward-looking `Bakeroo_Build_Plan.md` (the plan) by describing the **as-built** state.
> Companion design docs: `Bakeroo_Project_Context.md`, `Bakeroo_Data_Model_v1.md`,
> `Bakeroo_Process_Flows_v1.md`.
>
> **Status as of 2026-07-16:** the admin phase is **complete**. All metadata is deployed to **both**
> `BakerooScratch` (staging) and `BakerooOrg` (dev/promotion target) unless noted otherwise.
> The **automation phase** (Flows, scheduled Flows, approvals) and the **Experience Cloud phase**
> (storefront, community users, external sharing) are the next phases and are out of scope here.

---

## 1. Environment & workflow

- **Source-format SFDX project**, single package dir `force-app/main/default`, `sourceApiVersion 67.0`, no namespace.
- **Two orgs:** `BakerooOrg` (Developer Edition — Dev Hub + promotion target) and `BakerooScratch`
  (source-tracked scratch org — build/staging). Workflow: build on scratch → validate → promote to `BakerooOrg`.
- **Person Accounts enabled** (irreversible) on both orgs — via Setup on dev, via the `PersonAccounts`
  feature in `config/project-scratch-def.json` on scratch.
- **Dev Hub** enabled on `BakerooOrg` (`target-dev-hub=BakerooOrg`).

---

## 2. What was built (as-built inventory)

### 2.1 Standard-object custom fields & record types
- **Account** — fields: `Loyalty_Points_Balance__c` (roll-up), `Default_Delivery_Address__c` (TextArea),
  `Payment_Terms__c`, `Default_Lead_Time_Days__c`, `Active_Supplier__c`. Record types: **Bulk_Buyer**,
  **Supplier** (business); **Customer** = stock **PersonAccount** RT.
- **Lead** — `Estimated_Quantity__c`, `Requested_Delivery_Date__c`, `Items_of_Interest__c`, `Bulk_Source__c`.
- **Opportunity** — `Requested_Delivery_Date__c`, `Feasibility_Status__c`, `Deposit_Amount__c`, `Deposit_Paid__c`,
  `Total_Quantity__c`, plus `Items_of_Interest__c` and `Bulk_Source__c` (added as 1:1 Lead-map targets).
- **Order** — `Order_Type__c`, `Scheduled_Delivery_Date__c`, `Same_Day_Flag__c`, `Kitchen_Status__c`,
  `Payment_Status__c` (Pending/Paid/Refunded — **no COD**), `Source_Opportunity__c`, `Delivery_Address__c` (TextArea).
  Record types: **Same_Day_B2C**, **Bulk_Scheduled_B2B**.
- **Product2** — `Category__c`, `Prep_Time_Min__c`, `Is_Available__c`.

### 2.2 Custom objects (12) + relationships
- **Tier 1:** `Ingredient__c`, `Recipe__c`, `Delivery_Agent__c`.
- **Tier 2 / junctions:** `Recipe_Ingredient__c`, `Ingredient_Inventory__c`, `Ingredient_Supplier__c`,
  `Inventory_Reservation__c` (two-master junction: MD→Order + MD→Ingredient_Inventory), `Purchase_Order__c`,
  `Purchase_Order_Line__c`, `Delivery__c`, `Feedback__c`, `Loyalty_Point_Transaction__c`.
- All master-detail / lookup relationships and the three junctions in place.
- **Delivery agent = custom object** (`Delivery_Agent__c`), not a `User` lookup — a deliberate deviation
  from data-model decision 12 (drivers are not licensed users).

### 2.3 Roll-up summaries & formulas
- `Account.Loyalty_Points_Balance__c` (SUM of Loyalty_Point_Transaction points).
- `Ingredient_Inventory__c.Quantity_Reserved__c` (SUM of active reservations) + `Quantity_Available__c` (formula).
- `Purchase_Order__c.Total__c` (SUM of line totals) + `Purchase_Order_Line__c.Line_Total__c` (formula).

### 2.4 Lookup filters (referential integrity)
- Required `lookupFilter` (`Account.RecordType.DeveloperName = Supplier`) on the three supplier lookups —
  `Ingredient_Supplier__c.Supplier__c`, `Purchase_Order__c.Supplier__c`, `Ingredient__c.Preferred_Supplier__c` —
  so customers / bulk buyers can't be selected as suppliers.

### 2.5 Pricebooks & menu data (DATA, not metadata)
- Standard Pricebook activated; active **`Bakeroo Menu`** Pricebook2 created.
- Seed dataset via re-runnable `scripts/apex/seed_menu_data.apex`: 10 ingredients + inventory rows,
  5 menu products (with Standard + Bakeroo Menu price entries), 5 recipes, 21 recipe-ingredient rows.

### 2.6 UI: tabs, app, layouts, record pages
- **8 custom tabs** (Ingredient, Recipe, Ingredient_Inventory, Purchase_Order, Delivery, Delivery_Agent,
  Feedback, Loyalty_Point_Transaction); junctions + line-items get no tab.
- **`Bakeroo` Lightning app** — bakery-brown brand + `Bakeroo_UtilityBar`, custom tabs grouped in.
- **Record-type page layouts:** Account `Bulk_Buyer` / `Supplier`; Order `Same_Day_B2C` / `Bulk_Scheduled_B2B`;
  the **PersonAccount** layout customized with a Loyalty & Delivery section (**dev-only** — references stock
  sample fields the scratch org lacks). Assigned via a minimal partial `Admin` profile.
- **Per-custom-object page layouts** for the 8 tab'd objects — fields grouped into named sections,
  roll-ups/formulas + auto-number Names read-only.
- **Lightning record pages (FlexiPages)** — one per tab'd custom object (8), highlights-panel header + a
  Details/Related tabset, assigned as **org-default** via a `View`/`Large`/`Flexipage` `actionOverride` on
  each object's metadata.

### 2.7 Permission sets, profile, roles
- **`Bakeroo_All_Fields`** — broad perm set (FLS on all custom fields, RO on roll-up/formula, CRUD on custom
  objects); assigned to admin on both orgs (fixes the deployed-field-FLS gap).
- **5 function permission sets** — `Bakeroo_Sales` (Lead/Opportunity/Quote/Order R-W, Product2/Pricebook R),
  `Bakeroo_Operations`, `Bakeroo_Procurement`, `Bakeroo_Delivery_Mgmt`, `Bakeroo_Support` — object CRUD + FLS
  scoped per function, master-detail parents pulled in read-only.
- **`Bakeroo Internal` profile** — minimal (Salesforce license); object/field access comes from the perm sets.
  Carries `recordTypeVisibilities` for the 4 business/order RTs (perm sets can't set an RT default); PersonAccount
  RT omitted (auto-used; profile assignment rejected).
- **6 roles:** `Managing_Director` › (`Sales_Manager` › `Sales_Rep`) + (`Operations_Manager` ›
  `Support_Executive`, `Delivery_Manager`).

### 2.8 Org-wide defaults / sharing
- **Custom objects:** `Ingredient__c` + `Recipe__c` set `Private`; others already correct
  (`ControlledByParent` details, `Private` standalones). Metadata, both orgs.
- **Standard objects:** `Account`/`Opportunity`/`Order`/`Case` = **Private**, `Product2` = **Public Read Only**.
  On scratch via metadata; on `BakerooOrg` set **manually** in Sharing Settings (2026-07-16) and verified via an
  `EntityDefinition` Tooling query (both orgs match). `Contact` follows Account (Controlled by Parent) under Person Accounts.

### 2.9 Quote enablement
- Quotes enabled on both orgs via deployable **`Settings:Quote` (`enableQuote=true`)** (previously enabled on
  dev only, manually). `Quote` + `QuoteLineItem` (R/W) granted in `Bakeroo_Sales`.

---

## 3. Manual / org-config steps (not metadata) — completed
- **Person Accounts** enabled (both orgs).
- **Dev Hub** enabled on `BakerooOrg`.
- **Standard-object OWD** on `BakerooOrg` set via Sharing Settings.
- **Standard Pricebook** activation + all seed **DATA** loaded (via Apex script).
- **Lead → Opportunity field mapping** (Setup → Object Manager → Lead → Map Lead Fields) — **done on `BakerooOrg`.**
  All four custom Lead fields now map 1:1: `Requested_Delivery_Date__c` → same; `Estimated_Quantity__c` →
  `Total_Quantity__c`; `Items_of_Interest__c` → same; `Bulk_Source__c` → same.

---

## 4. Still to do (in scope, but pending)
- **Lead field mapping on `BakerooScratch`** — Map Lead Fields is org config (not metadata), so it must be
  redone per org. Done on dev; **not yet applied to scratch** (only needed when the pipeline is exercised there;
  scratch orgs are disposable, so re-map on demand).
- **Assign** roles / function permission sets / `Bakeroo Internal` profile **to users** — deferred because no
  internal role users exist yet; admin retains full access via `Bakeroo_All_Fields`.

### Deferred by decision (minor / intentional, not blocking)
- `Recipe_Ingredient__c.Unit__c` — not built; unit is derivable from the ingredient's UoM.
- **Compact layouts** — not built (highlights panel uses the default); pure polish.
- **P4 base-org review** (multi-currency, State/Country picklists) — not needed for V1.

---

## 5. Intentionally out of scope (boundaries / other phases)

### Experience Cloud phase (next)
- **Community profile** (Customer Community Plus) and the **`Bakeroo_Customer_Community`** permission set —
  need an external Community license.
- **External sharing** — external OWD, sharing sets, guest access — configured largely in the Experience
  workspace (not cleanly deployable); lands with the site build.
- **Commerce WebStore / WebCart / CartItem** and the **Experience Cloud storefront** build-out.

### Automation phase (next)
- Record-triggered Flows (same-day feasibility, inventory deduction, reactive reorder, forward shortfall,
  goods receipt, delivery success), scheduled Flows (kitchen drop), and approval processes (bulk discount,
  high-value PO). Hook points are catalogued in `Bakeroo_Build_Plan.md` §13 — noted, not designed here.

### V2 (deferred in the design)
- Guest checkout; recurring / contract bulk orders; batch / expiry / FIFO for perishables; broader
  forecast-driven procurement beyond bulk orders.

### Rejected (not to be built)
- The **single-object Order** variant (procurement on standard `Order`/`OrderItem` via record types, ingredients
  as shadow `Product2`) — preserved only as **Appendix A** in `Bakeroo_Data_Model_v1.md`. The split-object design
  (`Order`/`OrderItem` for customers, `Purchase_Order__c`/`Purchase_Order_Line__c` for procurement) is the one built.

---

## 6. Deployment status snapshot

| Area | BakerooScratch | BakerooOrg | Notes |
|---|---|---|---|
| Custom objects, fields, record types, relationships | ✅ | ✅ | metadata |
| Roll-ups & formulas | ✅ | ✅ | metadata |
| Supplier lookup filters | ✅ | ✅ | metadata |
| Tabs, app | ✅ | ✅ | metadata |
| Record-type + per-object page layouts | ✅ | ✅ | PA layout dev-only |
| Lightning record pages (FlexiPages) + assignment | ✅ | ✅ | metadata |
| Permission sets (`Bakeroo_All_Fields` + 5 function) | ✅ | ✅ | not assigned to users |
| `Bakeroo Internal` profile (+ RT visibility) | ✅ | ✅ | metadata |
| Roles (6) | ✅ | ✅ | metadata |
| Custom-object OWD | ✅ | ✅ | metadata |
| Standard-object OWD | ✅ (metadata) | ✅ (manual, verified) | not kept in source |
| Quotes enabled (`Settings:Quote`) + in `Bakeroo_Sales` | ✅ | ✅ | metadata |
| Pricebook + menu seed data | ✅ | ✅ | DATA (Apex script) |
| Lead → Opportunity field mapping | ⬜ pending | ✅ done | manual, per-org |

---

*End of admin-phase summary. Next: automation phase (Flows / approvals) and the Experience Cloud phase.*
