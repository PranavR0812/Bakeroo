# Bakeroo Cloud Kitchen — Build Plan: Data Model & Admin Configuration

> **Scope of this document.** A sequenced, dependency-ordered build plan for standing up the
> **object / data model** and **admin configuration** in Salesforce. This is the plan, not the
> build. It follows the split-object design in `Bakeroo_Data_Model_v1.md` (Appendix A — the
> single-object variant — is **not** built) and treats the section-4 decisions in
> `Bakeroo_Project_Context.md` as settled.
>
> **The automation layer (record-triggered Flows, scheduled Flows, approvals) is the NEXT phase
> and is NOT designed here.** Where automation will later attach, it is marked as a *hook point*
> only. Experience Cloud site + Commerce (WebStore/WebCart) build-out are **boundaries/dependencies**,
> not in scope.

---

## Build status (updated as of the data-model build)

**Done and deployed to BOTH `BakerooScratch` (staging) and `BakerooOrg` (dev):**
- ✅ **§3 Prerequisites** — Dev Hub enabled on `BakerooOrg` (`target-dev-hub` set); Person Accounts enabled (both orgs); scratch org `BakerooScratch` created with the `PersonAccounts` feature.
- ✅ **§4 Standard-object custom fields + record types** — Account, Lead, Opportunity, Order, Product2. Record types `Account.Bulk_Buyer` / `Account.Supplier` and `Order.Same_Day_B2C` / `Order.Bulk_Scheduled_B2B` retrieved from dev (Customer = stock `PersonAccount` RT).
- ✅ **§5 All 12 custom objects + relationships/junctions** — `Ingredient__c`, `Recipe__c`, `Recipe_Ingredient__c` retrieved from dev; the rest scaffolded (incl. `Delivery_Agent__c` and the two-master `Inventory_Reservation__c`).
- ✅ **§7 All roll-ups & formulas** — R1 loyalty balance, R2 reserved qty, R3 PO total, F1 available qty, F2 line total.
- ✅ **§9 (partial) Tabs, app & record-type layouts** — 8 custom tabs; the pre-existing `Bakeroo` Lightning app (built manually in dev) retrieved and enhanced with the custom tabs; **Account** (`Bulk_Buyer`, `Supplier`) + **Order** (`Same_Day_B2C`, `Bulk_Scheduled_B2B`) record-type layouts built and assigned via a minimal partial `Admin` profile; the **Person Account** layout customized in dev (loyalty balance + default delivery address).

**Not yet started:** §8 pricebook + Product2 menu data · §9 remainder (per-custom-object layouts, Lightning record pages/FlexiPages) · §10 permission sets/profiles/roles/OWD-sharing · automation phase.

**Deviations from the original plan (applied during build):**
- Order record types are named `Same_Day_B2C` / `Bulk_Scheduled_B2B` (not `Same_Day` / `Bulk_Scheduled`).
- "Customer" account type uses the stock **`PersonAccount`** record type (no separate `Customer` RT created).
- Address fields (`Account.Default_Delivery_Address__c`, `Order.Delivery_Address__c`, `Delivery__c.Delivery_Address__c`) are **`TextArea`** — Salesforce has no custom compound-Address field type (corrects gotcha #15).
- **Gotcha #4 resolved via the junction approach** — `Inventory_Reservation__c` is a two-master junction, so `Quantity_Reserved__c` is a native roll-up and `Quantity_Available__c` is fully declarative.
- **§9 — the `Bakeroo` Lightning app already existed in dev** (built manually) and pointed at the *standard* `PurchaseOrder`/`PurchaseOrderItem` tabs; retrieved and corrected to use the custom **`Purchase_Order__c`** tab plus the other custom-object tabs.
- **§9 — Person Account layout is a special case.** Person fields (`PersonEmail`, etc.) only work on the dedicated `PersonAccount-Person Account Layout`, not a business `Account` layout; and the person-account record type **cannot** be assigned via profile `layoutAssignments` (both orgs reject `Account.PersonAccount`). The PA layout is used automatically for all person accounts. Its loyalty/delivery customization is **dev-only** (it references dev's stock Sales Cloud sample fields the scratch org lacks).
- **§9 — layout assignment done via a minimal partial `Admin` profile** (only `layoutAssignments`), not a full-profile deploy, to avoid touching the ~893 lines of other Admin settings.

**Open items carried to §10:** OWD inconsistency (dev-built objects are `ReadWrite`; scaffolded ones `Private`/`ControlledByParent`); manual Lead→Opportunity field mapping; layout assignment currently only on the `Admin` profile (the function-based profiles/perm sets in §10 will need their own assignments).

---

## 0. Resolved decisions (locked before planning)

These four were open in the context doc and have been resolved with the owner:

| # | Open decision | Resolution | Impact on this plan |
|---|---|---|---|
| 1 | Delivery agent: `User` lookup vs custom object | **`Delivery_Agent__c` custom object** with an availability flag; `Delivery__c.Delivery_Agent__c` = `Lookup(Delivery_Agent__c)` | Adds one object; **deliberate deviation from doc decision 12**. No driver logins, licenses, profiles, roles, or sharing. |
| 2 | Person Accounts (irreversible) | **Enabled.** Already enabled on the dev org; declared as a scratch-org feature for staging. | First prerequisite. Customer record type = Person Account. |
| 3 | COD payment path | **Pay-before-kitchen only.** No COD. | `Order.Payment_Status__c` = Pending / Paid / Refunded (no COD value). |
| 4 | Target org / workflow | **Dev Hub + scratch org for staging → deploy to `BakerooOrg` (Dev Edition) as promotion target.** | Drives the environment section and the deployable-vs-manual split. |

---

## 1. Environment & workflow

**Observed project state** *(initial snapshot — see "Build status" above for what has since changed: Dev Hub is now enabled and `BakerooScratch` exists)*
- Source-format SFDX project. Single package dir `force-app/main/default`. `sourceApiVersion 67.0`, no namespace.
- Deploy mechanism: `sf project deploy start` (metadata API, source format).
- Default authed org `BakerooOrg` is a **Developer Edition** org (`orgfarm-…-dev-ed`) — **persistent, `tracksSource: false`**. Not a scratch org, not a sandbox.
- No Dev Hub currently authorized; no scratch orgs exist.
- `config/project-scratch-def.json` is Developer edition and **does not** list `PersonAccounts` or `Communities`.

**Target workflow**
1. **Enable Dev Hub** on a Developer Edition org (BakerooOrg can be its own Dev Hub) and auth it.
2. **Update `config/project-scratch-def.json`** — add `"PersonAccounts"` to `features` (and, when the later Experience/Commerce phase starts, `"Communities"` / Commerce features — *not now*).
3. **Create a scratch org** as the build/staging surface (has source tracking).
4. Build + iterate on scratch; validate.
5. **Promote** validated metadata to `BakerooOrg` via `sf project deploy start`.

> **Key mental-model correction:** feature enablement (Person Accounts, Communities) is **org-level
> config, not deployable metadata**. It does not travel with `sf project deploy`. Each org gets it
> independently — dev manually (done), scratch via the `features` array. The scratch org is for
> staging **metadata**, not feature flags.

---

## 2. Build sequence (high level, dependency-ordered)

```
Prerequisites (irreversible / org-level)
   └─> Standard-object custom fields + record types (Account, Lead, Opportunity, Order, Product2)
        └─> Custom objects — PARENTS first (Ingredient__c, Recipe__c, Delivery_Agent__c)
             └─> Junctions & dependent objects (need parents to exist)
                  └─> Master-detail relationships
                       └─> Roll-up summary fields (only after their master-detail exists)
                            └─> Formula fields
                                 └─> Pricebooks + Product2 menu data
                                      └─> Tabs + Lightning app
                                           └─> Page layouts / Lightning record pages (per record type)
                                                └─> Permission sets → Profiles → Roles
                                                     └─> OWD / sharing (+ external sharing sets — manual)
```

**Golden ordering rules (see §11 gotchas for detail):**
- Person Accounts **before** anything referencing them.
- A master-detail **parent** object must exist before the child/junction that points to it.
- A **roll-up summary** can only be created **after** its master-detail relationship exists.
- Each **Product2** needs a **Standard Pricebook Entry** before it can join a custom pricebook.

---

## 3. Prerequisites (do these FIRST)

- [x] **P1 — Enable Dev Hub** — enabled on `BakerooOrg`; `target-dev-hub=BakerooOrg` set. *Done.*
- [x] **P2 — ⚠️ Person Accounts enabled** (irreversible) — done on `BakerooOrg`; `"PersonAccounts"` added to `config/project-scratch-def.json` and verified on `BakerooScratch`. *Done, signed off.*
- [x] **P3 — Create scratch org** — `BakerooScratch` created (`sf org create scratch -f config/project-scratch-def.json -a BakerooScratch -v BakerooOrg`). *Done.*
- [ ] **P4 — Confirm base org settings:** Lightning Experience enabled (already), multi-currency **not** needed for V1 (Currency fields use org default), State/Country picklists optional. *Manual review.*
- [ ] **P5 — Standard Pricebook active** (needed before menu pricing). *Standard Pricebook is auto-present; activation/entries are DATA, not metadata — see §8.*

> After P2, Person Account record types and the Account↔Contact person model exist. All later
> Account work assumes this.

---

## 4. Standard-object custom fields & record types

Build these before custom objects where custom objects reference them (e.g. `Order`, `Product2`, `Account` as lookup/MD parents). Record types are created here; **layouts are assigned later** (§9).

### 4.1 Account — 3 record types + fields
- [ ] Record types: **Customer** (Person Account RT — requires P2), **Bulk_Buyer** (Business), **Supplier** (Business).
- [ ] `Loyalty_Points_Balance__c` — **Roll-Up Summary** (SUM of `Loyalty_Point_Transaction__c.Points__c`). ⏳ **Deferred until §7** — the MD child object must exist first. *Placeholder note here; created in §7.*
- [ ] `Default_Delivery_Address__c` — Address (compound) — *Customer only (layout).* 
- [ ] `Payment_Terms__c` — Picklist (Net 15 / Net 30 / …) — *Supplier only.*
- [ ] `Default_Lead_Time_Days__c` — Number — *Supplier only; fallback when not set per ingredient.*
- [ ] `Active_Supplier__c` — Checkbox — *Supplier only.*

### 4.2 Lead — fields
- [ ] `Estimated_Quantity__c` — Number
- [ ] `Requested_Delivery_Date__c` — Date  *(the feasibility anchor)*
- [ ] `Items_of_Interest__c` — Long Text Area
- [ ] `Bulk_Source__c` — Picklist (Bulk button / Threshold trip)
- [ ] **Lead conversion field mapping** for the above → Opportunity fields (see §11 gotcha #14). *Manual "Map Lead Fields".*

### 4.3 Opportunity — fields
- [ ] `Requested_Delivery_Date__c` — Date (carried from Lead)
- [ ] `Feasibility_Status__c` — Picklist (Feasible / Shortfall-Replenishable / Not-Feasible)
- [ ] `Deposit_Amount__c` — Currency
- [ ] `Deposit_Paid__c` — Checkbox *(gates the commit point — automation hook, later)*
- [ ] `Total_Quantity__c` — Number

### 4.4 Order — 2 record types + fields
- [ ] Record types: **Same_Day** (B2C), **Bulk_Scheduled** (B2B).
- [ ] `Order_Type__c` — Picklist (B2C / B2B) *(redundant with RT, handy in reports)*
- [ ] `Scheduled_Delivery_Date__c` — Date/Time
- [ ] `Same_Day_Flag__c` — Checkbox
- [ ] `Kitchen_Status__c` — Picklist (Queued / Preparing / Prepared)
- [ ] `Payment_Status__c` — Picklist (**Pending / Paid / Refunded** — no COD, per decision 3)
- [ ] `Source_Opportunity__c` — Lookup(Opportunity) *(bulk orders only)*
- [ ] `Delivery_Address__c` — Address (compound)
- [ ] **OrderItem**: standard `Quantity` + `Product2` via `PricebookEntry` (no custom fields required for V1).

### 4.5 Product2 — fields (menu item)
- [ ] `Category__c` — Picklist (Cakes / Breads / …)
- [ ] `Prep_Time_Min__c` — Number *(feeds same-day feasibility, later)*
- [ ] `Is_Available__c` — Checkbox
- [ ] Recipe link is on the child side (`Recipe__c.Product__c`) — built in §5.

> **No shadow Product2 for ingredients and no procurement pricebook** — those belong to the
> rejected Appendix A single-object variant. Ingredients live only as `Ingredient__c`.

---

## 5. Custom objects — build order (PARENTS first)

Each object: create the object, then its fields, then its relationships. Relationships that are
**master-detail** or that **feed a roll-up** are called out. Standard system fields (Id, Name,
CreatedDate, Owner) assumed. All API names carry `__c`; junctions named `<A>_<B>__c`.

### Tier 1 — standalone / parent objects (no dependency on other custom objects)

#### 5.1 `Ingredient__c` (raw-material master)
- [ ] Object: Name = Text or Auto-Number.
- [ ] `Unit_of_Measure__c` — Picklist (g / kg / ml / each …)
- [ ] `Reorder_Threshold__c` — Number
- [ ] `Safety_Stock__c` — Number
- [ ] `Is_Perishable__c` — Checkbox *(V2 shelf-life flag)*
- [ ] `Preferred_Supplier__c` — **Lookup(Account)** *(convenience default; junction is authoritative)*

#### 5.2 `Recipe__c` (bill-of-materials header)
- [ ] Object: Name = Text or Auto-Number.
- [ ] `Product__c` — **Lookup(Product2)** *(1 product → 1 recipe)*
- [ ] `Yield__c` — Number
- [ ] `Active__c` — Checkbox *(future recipe versioning)*

#### 5.3 `Delivery_Agent__c` (driver — resolved decision 1)
- [ ] Object: Name = Text (agent name).
- [ ] `Is_Available__c` — Checkbox *(feeds later auto-assign automation)*
- [ ] `Phone__c` — Phone
- [ ] `Active__c` — Checkbox
- [ ] `Delivery_Manager__c` — Lookup(User) *(optional: internal manager who oversees the agent)*

### Tier 2 — objects/junctions that depend on Tier 1 (+ standard objects)

#### 5.4 `Recipe_Ingredient__c` — **junction** (Recipe ↔ Ingredient) — load-bearing
- [ ] `Recipe__c` — **Master-Detail(Recipe__c)** ← *primary master; create Recipe__c first (5.2)*
- [ ] `Ingredient__c` — **Lookup(Ingredient__c)**  *(per doc; not MD — Recipe is the owning parent)*
- [ ] `Quantity_Required__c` — Number *(per recipe yield)*
- [ ] `Unit__c` — Picklist (matches ingredient UoM)

#### 5.5 `Ingredient_Inventory__c` (stock rows — 1 per ingredient in V1)
- [ ] `Ingredient__c` — **Master-Detail(Ingredient__c)** ← *create Ingredient__c first (5.1)*
- [ ] `Quantity_On_Hand__c` — Number
- [ ] `Quantity_Reserved__c` — **Roll-Up Summary** ⏳ *created in §7 — needs the reservation junction to exist first (see gotcha #4).*
- [ ] `Quantity_Available__c` — **Formula** (`Quantity_On_Hand__c − Quantity_Reserved__c`) ⏳ *created in §7 after the roll-up.*
- [ ] `Batch__c` / `Expiry__c` — *V2, leave out of V1.*

#### 5.6 `Ingredient_Supplier__c` — **junction** (Ingredient ↔ Supplier Account) — procurement source of truth
- [ ] `Ingredient__c` — **Master-Detail(Ingredient__c)** ← *primary master*
- [ ] `Supplier__c` — **Lookup(Account)** *(filter to Supplier record type on layout/validation)*
- [ ] `Unit_Price__c` — Currency
- [ ] `Lead_Time_Days__c` — Number *(drives "can we replenish in time?")*
- [ ] `Is_Preferred__c` — Checkbox
- [ ] `Min_Order_Qty__c` — Number

#### 5.7 `Inventory_Reservation__c` (soft + forward holds) — **junction, see gotcha #4**
- [ ] `Order__c` — **Master-Detail(Order)** ← *primary master; cascade-release on order cancel*
- [ ] `Ingredient_Inventory__c` — **Master-Detail(Ingredient_Inventory__c)** ← *secondary master — enables the `Quantity_Reserved__c` roll-up.* **(Refinement of the doc, which listed Ingredient as a plain lookup — see gotcha #4 for rationale & the alternative.)**
- [ ] `Quantity__c` — Number
- [ ] `Reservation_Type__c` — Picklist (Soft / Forward)
- [ ] `Needed_By_Date__c` — Date *(= delivery date for forward holds)*
- [ ] `Status__c` — Picklist (Active / Finalized / Released) *(roll-up filters on Active)*

#### 5.8 `Purchase_Order__c` (replenishment order to supplier)
- [ ] `Supplier__c` — **Lookup(Account)** *(Supplier RT)*
- [ ] `Status__c` — Picklist (Draft / Pending Approval / Sent / Received / Closed)
- [ ] `Source__c` — Picklist (Reactive / Forward)
- [ ] `Linked_Order__c` — **Lookup(Order)** *(set only for Entry-B bulk shortfall)*
- [ ] `Needed_By_Date__c` — Date
- [ ] `Expected_Delivery_Date__c` — Date
- [ ] `Approval_Status__c` — Picklist (Auto / Approved / Rejected)
- [ ] `Total__c` — **Roll-Up Summary** ⏳ *created in §7 (needs PO Line + its line-total formula).*

#### 5.9 `Purchase_Order_Line__c` (PO line items)
- [ ] `Purchase_Order__c` — **Master-Detail(Purchase_Order__c)** ← *create PO first (5.8)*
- [ ] `Ingredient__c` — **Lookup(Ingredient__c)**
- [ ] `Quantity_Ordered__c` — Number
- [ ] `Quantity_Received__c` — Number *(partial deliveries)*
- [ ] `Unit_Price__c` — Currency *(snapshot from junction)*
- [ ] `Line_Total__c` — **Formula** (`Quantity_Ordered__c × Unit_Price__c`) *(source for PO Total roll-up)*
- [ ] `Line_Status__c` — Picklist (Open / Partially Received / Received)

#### 5.10 `Delivery__c` (fulfillment)
- [ ] `Order__c` — **Master-Detail(Order)**
- [ ] `Delivery_Agent__c` — **Lookup(Delivery_Agent__c)** ← *resolved decision 1; create Delivery_Agent__c first (5.3)*
- [ ] `Status__c` — Picklist (Assigned / Out for delivery / Delivered / Failed)
- [ ] `Scheduled_Date__c` — Date/Time
- [ ] `Delivered_At__c` — Date/Time
- [ ] `Delivery_Address__c` — Address (compound)

#### 5.11 `Feedback__c` (post-delivery review)
- [ ] `Order__c` — **Lookup(Order)**
- [ ] `Customer__c` — **Lookup(Account)**
- [ ] `Rating__c` — Number (1–5)
- [ ] `Comments__c` — Long Text Area

#### 5.12 `Loyalty_Point_Transaction__c` (earn/redeem ledger)
- [ ] `Customer__c` — **Master-Detail(Account)** ← *enables the Account loyalty roll-up*
- [ ] `Order__c` — **Lookup(Order)** *(earn source)*
- [ ] `Points__c` — Number *(+earn / −redeem, signed)*
- [ ] `Type__c` — Picklist (Earn / Redeem / Adjustment)

---

## 6. Relationship summary (what points where)

| Child | Field | Type | Parent | Notes |
|---|---|---|---|---|
| Recipe__c | Product__c | Lookup | Product2 | 1 product → 1 recipe |
| Ingredient__c | Preferred_Supplier__c | Lookup | Account | convenience default |
| Recipe_Ingredient__c | Recipe__c | **Master-Detail** | Recipe__c | primary |
| Recipe_Ingredient__c | Ingredient__c | Lookup | Ingredient__c | |
| Ingredient_Inventory__c | Ingredient__c | **Master-Detail** | Ingredient__c | |
| Ingredient_Supplier__c | Ingredient__c | **Master-Detail** | Ingredient__c | primary |
| Ingredient_Supplier__c | Supplier__c | Lookup | Account (Supplier) | |
| Inventory_Reservation__c | Order__c | **Master-Detail** | Order | primary; cascade-release |
| Inventory_Reservation__c | Ingredient_Inventory__c | **Master-Detail** | Ingredient_Inventory__c | secondary → enables reserved roll-up |
| Purchase_Order__c | Supplier__c | Lookup | Account (Supplier) | |
| Purchase_Order__c | Linked_Order__c | Lookup | Order | Entry-B link |
| Purchase_Order_Line__c | Purchase_Order__c | **Master-Detail** | Purchase_Order__c | |
| Purchase_Order_Line__c | Ingredient__c | Lookup | Ingredient__c | |
| Delivery__c | Order__c | **Master-Detail** | Order | |
| Delivery__c | Delivery_Agent__c | Lookup | Delivery_Agent__c | |
| Feedback__c | Order__c / Customer__c | Lookup | Order / Account | |
| Loyalty_Point_Transaction__c | Customer__c | **Master-Detail** | Account | enables balance roll-up |
| Loyalty_Point_Transaction__c | Order__c | Lookup | Order | |

**Two junctions (per naming convention):** `Recipe_Ingredient__c` (Recipe ↔ Ingredient) and
`Ingredient_Supplier__c` (Ingredient ↔ Supplier Account). `Inventory_Reservation__c` is *also*
implemented as a two-master junction (Order + Ingredient_Inventory) — see gotcha #4.

---

## 7. Roll-up summary & formula fields (create AFTER their master-detail exists)

> A roll-up summary can only be defined on the **master** side of an existing **master-detail**
> relationship. Build the MD relationship first, then return to add these.

| # | Field (on parent) | Type | Aggregates | MD dependency | Filter |
|---|---|---|---|---|---|
| R1 | `Account.Loyalty_Points_Balance__c` | Roll-Up (SUM) | `Loyalty_Point_Transaction__c.Points__c` | Loyalty_Point_Transaction__c MD→Account (5.12) | none (Points signed) |
| R2 | `Ingredient_Inventory__c.Quantity_Reserved__c` | Roll-Up (SUM) | `Inventory_Reservation__c.Quantity__c` | Inventory_Reservation__c **secondary MD**→Ingredient_Inventory__c (5.7) | `Status__c = Active` |
| R3 | `Purchase_Order__c.Total__c` | Roll-Up (SUM) | `Purchase_Order_Line__c.Line_Total__c` | Purchase_Order_Line__c MD→Purchase_Order__c (5.9) | none |
| F1 | `Ingredient_Inventory__c.Quantity_Available__c` | Formula | `Quantity_On_Hand__c − Quantity_Reserved__c` | needs R2 to exist | — |
| F2 | `Purchase_Order_Line__c.Line_Total__c` | Formula | `Quantity_Ordered__c × Unit_Price__c` | — (build before R3) | — |

**Order within §7:** F2 → R3 ; (R2 needs the 5.7 secondary MD) → F1 ; R1 independent.

---

## 8. Pricebooks & Product2 menu setup

- [ ] **Standard Pricebook** — present by default; must be **active**. *DATA/config, not metadata.*
- [ ] **Menu products** — create `Product2` records for menu items with `Category__c`, `Prep_Time_Min__c`, `Is_Available__c`. *These are **DATA**, loaded via `sf data import` / Data Loader — not metadata.*
- [ ] **Standard Pricebook Entry** for each Product2 (**required before** any custom pricebook entry). *DATA.*
- [ ] **`Bakeroo Menu` custom Pricebook2** (optional but recommended so the storefront reads a dedicated catalog) + PricebookEntry per product. *Pricebook2 object def can be metadata; entries are DATA.*
- [ ] Link each product to its `Recipe__c` (`Recipe__c.Product__c`) — recipe + `Recipe_Ingredient__c` rows are DATA.

> **Boundary:** the Commerce WebStore/WebCart and the Experience Cloud storefront that *consume*
> this pricebook are **out of scope** (next phases). We only stand up Product2 + pricebook here.
>
> **No procurement pricebook / no shadow ingredient products** (that is the Appendix A variant we
> are not building).

---

## 9. Tabs, app, page layouts & Lightning record pages

- [x] **Custom tabs** for each custom object that needs one — built all 8 (Ingredient, Recipe, Ingredient_Inventory, Purchase_Order, Delivery, Delivery_Agent, Feedback, Loyalty_Point_Transaction); junctions + `Purchase_Order_Line__c` get no tab. *Deployed both orgs.*
- [x] **`Bakeroo` Lightning app** — already existed in dev; retrieved and enhanced with the 8 custom tabs, re-grouped, and corrected off the wrong standard `PurchaseOrder`/`PurchaseOrderItem` tabs onto the custom `Purchase_Order__c` tab. Bakery-brown brand + `Bakeroo_UtilityBar` preserved. *Deployed both orgs.*
- [x] **Page layouts per record type:**
  - Account: **Customer** — done via the dedicated **`PersonAccount-Person Account Layout`** (new *Loyalty & Delivery* section: loyalty balance read-only + default delivery address); **`Account-Bulk_Buyer Layout`**, **`Account-Supplier Layout`** (payment terms, lead time, active-supplier). *Business layouts on both orgs; PA layout dev-only.*
  - Order: **`Order-Same_Day_B2C Layout`** (kitchen status, same-day flag, payment) vs **`Order-Bulk_Scheduled_B2B Layout`** (source opportunity, scheduled date, payment). *Deployed both orgs.*
  - [ ] Custom objects: one layout each; surface roll-ups/formulas read-only — **deferred** (auto-generated defaults in use for now). *Metadata.*
- [ ] **Lightning record pages (FlexiPages)** per object/record type as needed; assign per app/record type — **deferred** (org default record pages in use). *Metadata.*
- [x] Assign record types → layouts per profile — done for the **4 business/order** record types via a minimal partial **`Admin`** profile (`layoutAssignments` only). Person-account RT cannot be assigned this way (see deviations); §10 profiles/perm sets will add their own assignments. *Deployed both orgs.*

---

## 10. Admin configuration: profiles, permission sets, roles, sharing

### 10.1 Role hierarchy (maps to actor hierarchy in context doc §2)

> Drivers are a **custom object**, not users → **no driver role/profile**. Delivery Manager is
> internal (manages the data).

```
Managing_Director (MD)
├── Sales_Manager (SM)
│   └── Sales_Rep (SR)
└── Operations_Manager (OM)
    ├── Support_Executive (SE)
    └── Delivery_Manager
```
System Administrator = standard profile, effectively top / no role needed. *Roles are metadata.*

### 10.2 Profiles (minimal) + Permission Sets (function-based)

Prefer **minimal profiles + permission sets** for object/field access.

| Profile (base) | Who | Notes |
|---|---|---|
| System Administrator (standard) | Admin | full config |
| Bakeroo Internal (clone of Standard User, minimal) | SM/SR/OM/SE/Delivery Mgr/MD | object access granted via perm sets |
| Customer Community Plus (Login or Member) | **Experience Cloud customers (external)** | loyalty + own orders; site build is a later phase |

| Permission Set | Grants | Assigned to |
|---|---|---|
| `Bakeroo_Sales` | Lead, Opportunity, Quote, Order (R/W); Product2, Pricebook (R) | SM, SR |
| `Bakeroo_Operations` | Ingredient, Recipe, Recipe_Ingredient, Ingredient_Inventory, Inventory_Reservation, Ingredient_Supplier, Purchase_Order(+Line), Delivery, Delivery_Agent (R/W) | OM |
| `Bakeroo_Procurement` | Purchase_Order(+Line), Ingredient_Supplier (R/W) | OM (can fold into Operations) |
| `Bakeroo_Delivery_Mgmt` | Delivery, Delivery_Agent (R/W) | Delivery Manager |
| `Bakeroo_Support` | Case (R/W); Account/Order (R) | SE |
| `Bakeroo_Customer_Community` | Product2/Pricebook (R), own Order/Feedback (R/W), Loyalty (R) | external customers |

*Permission sets and (partial) profiles are metadata. Permission-set **assignment** to users is
often manual or scripted (`sf org assign permset`).*

### 10.3 Org-wide defaults / sharing

| Object | Internal OWD | External OWD | Rationale |
|---|---|---|---|
| Account / Contact | Private | Private | customers see only their own Person Account |
| Order / OrderItem | Private | Private | customers see own via sharing set |
| Product2 / Pricebook2 | Public Read Only | (catalog access) | menu is shared to all |
| Ingredient / Recipe / *Inventory / Reservation / Ingredient_Supplier | Private | No Access | internal kitchen/ops data |
| Purchase_Order(+Line) | Private | No Access | procurement internal |
| Delivery / Delivery_Agent | Private | No Access | internal ops |
| Feedback__c | Private | Private | customer sees own |
| Loyalty_Point_Transaction__c | (controlled by parent — MD to Account) | — | follows Account |
| Case | Private | Private | customer sees own |

- **OWD `sharingModel`** is in each object's metadata → **deployable**. **Sharing rules** → deployable.
- **External sharing (sharing sets, external OWD, the "External Access" column)** for Experience
  Cloud users is configured in the **Experience workspace and is largely manual / not cleanly
  deployable** — flagged, and tied to the (out-of-scope) site build. For now, plan the **internal**
  OWD/sharing; external sharing sets are a boundary item that lands with the site.

---

## 11. Ordering traps & gotchas

1. **Person Accounts first & irreversible.** Enable before any metadata that references person accounts (Customer RT, person fields, Loyalty MD→Account behavior). Done on dev; feature-flag on scratch. No undo on the persistent org.
2. **Master-detail parent must pre-exist.** Build `Ingredient__c`, `Recipe__c`, `Purchase_Order__c`, `Ingredient_Inventory__c`, `Delivery_Agent__c` **before** the children/junctions that MD to them.
3. **Roll-up after master-detail.** R1–R3 (§7) can't be created until their MD relationship exists. Sequence: object → MD → roll-up. `Quantity_Available__c` formula (F1) needs `Quantity_Reserved__c` (R2) to already exist.
4. **⚠️ `Quantity_Reserved__c` roll-up trap (design refinement).** The doc lists `Inventory_Reservation__c` as **MD→Order** + **Lookup→Ingredient**. But a native roll-up of reserved quantity onto inventory requires the reservation to be **master-detail to the inventory/ingredient side** — you cannot roll up across a lookup. Resolution: make `Inventory_Reservation__c` a **two-master junction** — **primary MD→Order** (keeps cascade-release on cancel) + **secondary MD→Ingredient_Inventory__c** (enables the `Quantity_Reserved__c` roll-up, filtered `Status = Active`). Ownership/sharing follow the primary (Order → customer). **Alternative if you prefer to keep Ingredient as a plain lookup:** drop the native roll-up and compute `Quantity_Reserved__c` via automation next phase (a rollup Flow/trigger) — but then `Quantity_Available__c` is not declarative in V1. **Recommended: the junction approach**, so availability is fully declarative.
5. **Standard Pricebook Entry before custom.** Each Product2 needs a Standard Pricebook Entry before joining `Bakeroo Menu`.
6. **Products/pricebook entries/recipes/ingredients are DATA, not metadata.** They will **not** arrive via `sf project deploy`. Load separately (`sf data import tree` / Data Loader) after metadata deploys. Plan a seed data set.
7. **Junction field-creation order sets the primary master.** The **first** master-detail created becomes the primary (controls ownership, sharing, delete). Create `Recipe__c` MD before the `Ingredient__c` field on `Recipe_Ingredient__c`; create `Order__c` MD before `Ingredient_Inventory__c` MD on `Inventory_Reservation__c`.
8. **Lookup→MD conversion needs every child to have a parent.** On a fresh build (no orphan records) this is free; if data exists first, it blocks.
9. **Record types need their picklist values + must be assigned** to profiles/permission sets and mapped to layouts, or users can't pick them.
10. **Person Account roll-ups & MD.** `Loyalty_Point_Transaction__c` MD→Account rolls up to the Person Account fine; ensure the balance field/layout is on the **Customer** (person) layout only.
11. **`Supplier__c` lookups should be constrained to the Supplier record type** (lookup filter or validation) so bulk buyers/customers aren't picked as suppliers.
12. **Deploy order inside a single push:** objects → fields → record types → MD relationships → roll-ups/formulas → tabs/app → layouts/flexipages → permission sets → profiles → roles → sharing. If deploying piecemeal, respect this or references dangle.
13. **`Delivery_Agent__c` deviates from doc decision 12** (User→custom object). Documented and intentional; the delivery auto-assign automation (later) will read `Is_Available__c` on this object instead of User presence.
14. **Lead conversion field mapping is manual.** Custom Lead fields (`Estimated_Quantity__c`, `Requested_Delivery_Date__c`, etc.) only carry to Opportunity/Account/Contact if mapped in **Setup → Map Lead Fields**. Not fully captured by object metadata.
15. **Address compound fields** (`Default_Delivery_Address__c`, `Delivery_Address__c`) are custom Address-type fields — verify they render on layouts; they can't be used in some formula contexts.

---

## 12. Deployable-as-metadata vs manual/declarative-only vs data

| Item | How it's delivered |
|---|---|
| Custom objects, custom fields, record types | **Metadata (deploy)** |
| Master-detail & lookup relationships | **Metadata (deploy)** |
| Roll-up summary & formula fields | **Metadata (deploy)** |
| Page layouts, Lightning record pages (flexipages), compact layouts | **Metadata (deploy)** |
| Tabs, Lightning app | **Metadata (deploy)** |
| Permission sets | **Metadata (deploy)** |
| Profiles | **Metadata (deploy, partial)** — some settings need manual touch-up |
| Roles / role hierarchy | **Metadata (deploy)** |
| OWD `sharingModel`, sharing rules | **Metadata (deploy)** |
| **Person Accounts enablement** | **Manual (irreversible)** on persistent orgs / **feature flag** on scratch — done |
| **Dev Hub enablement** | **Manual** (Setup) |
| Scratch org creation | **CLI** (uses `features` in scratch def) |
| **Lead field mapping** (Map Lead Fields) | **Manual / partial metadata** |
| Standard Pricebook activation | **Config/data** |
| **Product2 records, Pricebook entries, Recipes, Ingredients, Inventory seed** | **DATA** (`sf data import` / Data Loader) — not metadata |
| **External sharing sets / external OWD / Experience site** | **Manual**, lands with the (out-of-scope) site build |
| Permission-set assignment to users | **Manual / scripted** (`sf org assign permset`) |

---

## 13. Automation hook points (NEXT phase — noted, not designed here)

For continuity only — where the automation layer will attach to this model:

- **Same-day feasibility** → record-triggered Flow on `Order` create (reads `Prep_Time_Min__c`, capacity).
- **Inventory deduction** → Flow when `Order.Kitchen_Status__c → Prepared` (finalize reservations, decrement `Quantity_On_Hand__c` via `Recipe_Ingredient__c`).
- **Reactive reorder (Entry A)** → Flow on `Ingredient_Inventory__c` update (threshold + safety stock + lead time).
- **Forward shortfall (Entry B)** → Flow on `Opportunity` Closed-Won + `Deposit_Paid__c` (create forward reservation; trigger PO with `Linked_Order__c`).
- **Goods receipt** → Flow on `Purchase_Order_Line__c` update (replenish; if Entry B, release the gated kitchen drop).
- **Delivery success** → Flow on `Delivery__c.Status__c = Delivered` (Feedback request + Loyalty accrual).
- **Auto-assign delivery agent** → Flow reading `Delivery_Agent__c.Is_Available__c`.
- **Scheduled kitchen drop** → Scheduled Flow, N hours before `Scheduled_Delivery_Date__c`, gated on goods-receipt.
- **Approvals** → bulk discount above threshold (OM/MD); high-value Purchase Order (OM).
- **`Quantity_Reserved__c`** → if gotcha #4's junction approach is *not* taken, this becomes an automation-computed field here instead of a native roll-up.

---

## 14. Suggested execution order (checklist digest)

1. [x] Prereqs P1–P5 (Dev Hub, Person Accounts, scratch org, settings, standard pricebook).
2. [x] Standard-object custom fields + record types (§4) — Account, Lead, Opportunity, Order, Product2.
3. [x] Tier-1 custom objects: `Ingredient__c`, `Recipe__c`, `Delivery_Agent__c` (§5.1–5.3).
4. [x] Tier-2 objects & junctions: `Recipe_Ingredient__c`, `Ingredient_Inventory__c`, `Ingredient_Supplier__c`, `Inventory_Reservation__c`, `Purchase_Order__c`, `Purchase_Order_Line__c`, `Delivery__c`, `Feedback__c`, `Loyalty_Point_Transaction__c` (§5.4–5.12), incl. master-detail relationships.
5. [x] Roll-ups & formulas (§7): F2 → R3; secondary-MD → R2 → F1; R1.
6. [ ] Pricebooks + Product2 menu (§8) — metadata objects now, **seed DATA later**.
7. [~] Tabs, app, layouts, Lightning pages per record type (§9) — tabs, app, and Account/Order record-type layouts + assignment **done**; per-custom-object layouts and Lightning record pages deferred.
8. [ ] Permission sets → profiles → roles (§10.1–10.2).
9. [ ] Internal OWD/sharing (§10.3); flag external sharing sets for the site phase.
10. [ ] `sf project deploy start` to scratch → validate → deploy to `BakerooOrg`.
11. [ ] Load seed data (products, pricebook entries, ingredients, recipes, inventory) — DATA.
12. [ ] Hand off to the **automation phase** (§13).

---

*End of build plan. Boundaries: Experience Cloud site + Commerce WebStore/WebCart and the entire
automation layer are explicitly out of scope here and are the next phases.*
