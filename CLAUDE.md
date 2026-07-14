# CLAUDE.md

Guidance for AI agents (Claude Code) working in this repository.

## Project

**Bakeroo Cloud Kitchen** — a Salesforce implementation exercise for an imaginary delivery-only
cloud kitchen (bakery-leaning). It spans three clouds: **Commerce (D2C) + Experience Cloud**
(storefront), **Sales Cloud** (B2B bulk pipeline), and **Service Cloud** (support). The domain has
three moving parts: a B2C same-day path, a B2B future-dated bulk path, and an ingredient
inventory / procurement loop.

**Design is the source of truth — read it first** (in `design-docs/`, in this order):
1. `Bakeroo_Project_Context.md` — intent, settled decisions (§4 is SETTLED), open questions, conventions.
2. `Bakeroo_Data_Model_v1.md` — objects, fields, relationships, ER diagram. **Appendix A is a REJECTED variant — do not build it.**
3. `Bakeroo_Process_Flows_v1.md` — the three process flows.

`Bakeroo_Build_Plan.md` (repo root) is the sequenced build plan for the data model + admin config,
and tracks progress.

## Tech stack & project shape

- **Source-format SFDX project.** Single package dir: `force-app/main/default`.
- `sourceApiVersion` **67.0**, no namespace (`sfdx-project.json`).
- Metadata lives under `force-app/main/default/objects/<Object>/{fields,recordTypes}/…`.
- Tooling present: Prettier (`.prettierrc`), ESLint (`eslint.config.js`), Jest (`jest.config.js`),
  Husky hooks (`.husky/`). LWC/Apex folders are scaffolded but empty (data-model phase).

## Orgs & workflow

Two orgs are used. **Confirm the target org before any deploy/retrieve — never assume.**

| Alias | Type | Role |
|---|---|---|
| `BakerooOrg` | Developer Edition (persistent, `tracksSource:false`) | **Dev Hub** + **promotion target** (the "real" org) |
| `BakerooScratch` | Scratch org (source-tracked) | **Build/staging** surface |

**Workflow:** build + iterate on `BakerooScratch` → validate → **promote** to `BakerooOrg`.
- Default `target-org` may be either — check with `sf config list` before deploying.
- `target-dev-hub = BakerooOrg`.
- Scratch org is created from `config/project-scratch-def.json` (includes the `PersonAccounts` feature).

> **Feature flags are org-level config, NOT deployable metadata.** Person Accounts / Communities do
> not travel with `sf project deploy`. Each org enables them independently — dev manually, scratch
> via the `features` array in the scratch def.

## Common commands

```bash
# Inspect
sf config list                                   # see target-org / target-dev-hub
sf org list                                       # authed orgs
sf sobject list -o <org> --sobject all            # list objects (check before scaffolding!)
sf sobject describe -s <Object> -o <org>          # fields on an object

# Scratch org
sf org create scratch -f config/project-scratch-def.json -a BakerooScratch -v BakerooOrg -d -y 30

# Deploy / retrieve (source format)
sf project deploy start -o <org>                  # deploy source to org
sf project deploy start -o <org> --dry-run        # validate only
sf project deploy preview -o BakerooScratch       # check source-tracking conflicts (scratch)
sf project retrieve start -o <org> -m "CustomObject:Foo__c"   # pull existing metadata into source

# Open / data
sf org open -o <org>                              # open org in browser (add --path "lightning/…")
sf data query -o <org> -q "SELECT …"
```

## Conventions

- **API names:** custom objects/fields end in `__c`; junctions named `<A>_<B>__c`
  (e.g. `Recipe_Ingredient__c`, `Ingredient_Supplier__c`).
- **Split-object design is settled:** customer orders use standard `Order`/`OrderItem`; supplier
  procurement uses custom `Purchase_Order__c`/`Purchase_Order_Line__c`. **Do not merge them.**
- All consumption logic routes through the **Recipe → Recipe_Ingredient** junction.
- Preserve the **reservation → deduction** lifecycle (reserve at checkout/commit, finalize-and-deduct
  at prep, release on cancel).
- Anything marked **V2** in the docs is out of scope unless the owner reopens it.
- **Always check the dev org (`BakerooOrg`) before scaffolding an object/field** — some were built
  manually there. If it exists, **retrieve it into source** rather than authoring fresh XML that
  might diverge.

## Salesforce gotchas (learned on this project)

- **Person Accounts are irreversible** once enabled. Enabled on both orgs. Never plan an undo.
- **Roll-up summaries require master-detail**, and can only be created **after** the MD exists.
  You cannot roll up across a lookup. (This is why `Inventory_Reservation__c` is a two-master
  junction: MD→Order + MD→Ingredient_Inventory, so `Quantity_Reserved__c` can roll up natively.)
- **Standard objects don't need an `<Object>.object-meta.xml`.** Retrieving record types drops an
  empty `<CustomObject></CustomObject>` shell into `objects/Account/` or `objects/Order/` — **delete
  it**, or source-tracking flags a phantom conflict. Custom objects DO keep their object-meta.
- **Data ≠ metadata.** Product2 records, Pricebook entries, Ingredients, Recipes, and Inventory rows
  are **DATA** — they don't deploy with `sf project deploy`; load via `sf data import` / Data Loader.
- **No custom compound Address field type.** Address fields here are `TextArea` (`Delivery_Address__c`,
  `Default_Delivery_Address__c`); use standard `ShippingAddress` if structured components are needed.
- **Lead → Opportunity field mapping is manual** (Setup → Map Lead Fields), not captured in metadata.
- Each `Product2` needs a **Standard Pricebook Entry** before joining a custom pricebook.
- **Person Account layouts are a separate type.** Person fields (`PersonEmail`, `PersonMobilePhone`,
  etc.) can only live on the dedicated `PersonAccount-Person Account Layout` — a business `Account`
  layout rejects them ("Cannot use field:PersonEmail in a layout"). The person-account record type
  **cannot** be assigned via profile `layoutAssignments` (both orgs reject `recordType Account.PersonAccount`);
  the PA layout is used automatically for all person accounts. Customize the PA layout by retrieving
  `Layout:PersonAccount-Person Account Layout` and editing it.
- **`CustomTab` needs a valid `motif`** (icon), e.g. `Custom53: Bread`; an invalid name fails deploy.
  Junctions and line-item objects (`Recipe_Ingredient__c`, `Purchase_Order_Line__c`, …) get **no tab**.
- **Deployed custom fields get NO field-level security.** A custom field created in the UI auto-grants
  FLS to your profile; a field pushed via `sf project deploy` grants FLS to **nobody** — *except* `required`
  and master-detail fields, which are auto-visible. Symptom: `FieldDefinition` (Tooling) lists the field,
  but `sf sobject describe` / SOQL-select / Apex / DML all say **"No such column / Field does not exist"**
  (describe honours FLS; Tooling doesn't). Fix by granting FLS via a permission set — the broad
  **`Bakeroo_All_Fields`** perm set covers every custom field and is assigned to admin on both orgs.
  This bit the whole model (Product2/Order/Account fields were invisible until it was assigned).
  Roll-up (`Summary`) and formula fields must be `<editable>false</editable>` in FLS.
- **Assign layouts via a *minimal partial* profile** — deploy a `Profile` file containing only
  `<custom>`, `<userLicense>`, and the `<layoutAssignments>` you want. Do **not** retrieve+redeploy
  the full profile (Admin is ~893 lines) — the partial merges the assignments without touching other
  settings. (Retrieving `Profile:Admin` alone returns **no** `layoutAssignments`; they only come back
  when layouts are retrieved in the same call.)
- **Stock cloud layouts reference sample fields the scratch org lacks** (e.g. `CustomerPriority__c`,
  `SLA__c`). If you retrieve a stock layout as a template, **don't keep it in source** — it exists in
  dev already and won't validate against scratch. Same reason the customized PA layout is dev-only.

## Testing & quality

- Run Prettier / ESLint before committing where applicable; Husky may enforce on commit.
- LWC unit tests: `npm run test` (Jest) once components exist.
- Apex tests: `sf apex run test -o <org>` once classes exist.
- For metadata-only changes, validate with `sf project deploy start --dry-run` before promoting to `BakerooOrg`.

## Git guidelines

- **Do NOT add a `Co-Authored-By` trailer** (or any AI attribution) to commit messages.
- **Commit only when asked; push only when explicitly asked.** Never `git push` without a request.
- Write clear, imperative commit subjects with a concise body summarizing what/why.
- Never skip hooks (`--no-verify`) or bypass signing unless explicitly asked.

## Scope guardrails

- **In scope now:** object/data model + admin config (objects, fields, record types, relationships,
  roll-ups, pricebooks, layouts, profiles/permission sets/roles, OWD/sharing).
- **NOT yet (next phase):** the automation layer — record-triggered Flows, scheduled Flows, approval
  processes. Note *where* automation hooks in, but don't design it.
- **Boundaries (out of scope):** Experience Cloud site + Commerce WebStore/WebCart build-out.

---

## Change log — work completed so far

Data-model + record-type layer built per `Bakeroo_Build_Plan.md` and deployed to **both**
`BakerooScratch` and `BakerooOrg`.

**Open decisions resolved with the owner:**
- Delivery agent → **`Delivery_Agent__c` custom object** (not a `User` lookup; deviates from data-model doc decision 12).
- Person Accounts → **enabled** (irreversible) on both orgs.
- Payment → **pay-before-kitchen only**; `Order.Payment_Status__c` = Pending / Paid / Refunded (no COD).
- Environment → **Dev Hub + scratch (staging) → `BakerooOrg` (promotion)**.

**Environment:**
- Enabled Dev Hub on `BakerooOrg`; set `target-dev-hub=BakerooOrg`.
- Added `PersonAccounts` to `config/project-scratch-def.json`; created scratch org `BakerooScratch`.

**Custom objects (12) + relationships:**
- Retrieved from dev (built manually there): `Ingredient__c`, `Recipe__c`, `Recipe_Ingredient__c`.
- Scaffolded fresh: `Delivery_Agent__c`, `Ingredient_Inventory__c`, `Ingredient_Supplier__c`,
  `Inventory_Reservation__c` (two-master junction), `Purchase_Order__c`, `Purchase_Order_Line__c`,
  `Delivery__c`, `Feedback__c`, `Loyalty_Point_Transaction__c`.
- All master-detail / lookup relationships and the three junctions in place.

**Standard-object custom fields + record types:**
- Account — fields (`Loyalty_Points_Balance__c` roll-up, `Default_Delivery_Address__c`,
  `Payment_Terms__c`, `Default_Lead_Time_Days__c`, `Active_Supplier__c`); record types
  `Bulk_Buyer`, `Supplier` retrieved (Customer = stock `PersonAccount` RT).
- Order — 7 fields (incl. `Payment_Status__c` without COD); record types `Same_Day_B2C`,
  `Bulk_Scheduled_B2B` retrieved.
- Lead, Opportunity, Product2 — custom fields per plan §4.

**Roll-ups & formulas (§7):**
- `Account.Loyalty_Points_Balance__c` (SUM), `Ingredient_Inventory__c.Quantity_Reserved__c`
  (SUM, `Status=Active`) + `Quantity_Available__c` (formula), `Purchase_Order__c.Total__c` (SUM) +
  `Purchase_Order_Line__c.Line_Total__c` (formula).

**Tabs, app & record-type layouts (§9, partial):**
- 8 custom tabs (Ingredient, Recipe, Ingredient_Inventory, Purchase_Order, Delivery, Delivery_Agent,
  Feedback, Loyalty_Point_Transaction); junctions + line items get no tab.
- `Bakeroo` Lightning app already existed in dev — retrieved and enhanced with the custom tabs,
  re-grouped, and pointed off the wrong standard `PurchaseOrder`/`PurchaseOrderItem` tabs onto the
  custom `Purchase_Order__c` tab. Bakery-brown brand + `Bakeroo_UtilityBar` preserved.
- Record-type layouts: `Order-Same_Day_B2C`, `Order-Bulk_Scheduled_B2B`, `Account-Bulk_Buyer`,
  `Account-Supplier` (built + assigned via a minimal partial `Admin` profile, both orgs);
  `PersonAccount-Person Account Layout` customized with a *Loyalty & Delivery* section (dev-only).
- **Deferred:** per-custom-object layouts (auto-generated defaults in use) and Lightning record pages.

**§8 pricebook + menu data (DONE, both orgs):**
- Added missing `Recipe_Ingredient__c.Quantity_Required__c` (Number) — the load-bearing junction quantity
  was specified in Build Plan §5.4 but never built.
- **Fixed a pervasive FLS gap** — deployed optional custom fields had no field-level security, so the admin
  couldn't see/load most of the model. New broad permission set **`Bakeroo_All_Fields`** (Read/Edit on all
  custom fields, RO on roll-up/formula, CRUD on custom objects), assigned to admin on both orgs. See gotcha.
- Activated the (previously inactive) **Standard Pricebook**; created active **`Bakeroo Menu`** Pricebook2.
- Seeded a small farm-to-table dataset via re-runnable `scripts/apex/seed_menu_data.apex`: 10 `Ingredient__c`
  + inventory rows, 5 `Product2` menu items (across categories) with Standard + Bakeroo Menu price entries,
  5 `Recipe__c` linked to products, 21 `Recipe_Ingredient__c` rows with quantities. Roll-ups/formulas
  (`Quantity_Available__c`, etc.) verified populating.

**Not yet done:** §9 remainder (per-object layouts, FlexiPages) · §10 permission sets/profiles/roles/OWD-sharing
(the `Bakeroo_All_Fields` set is an interim FLS fix; the granular function sets are still to build) ·
the automation phase.

**Known open items:**
- OWD inconsistency: dev-built objects are `ReadWrite`; scaffolded ones `Private`/`ControlledByParent`
  — reconcile in §10.
- Address fields are `TextArea` (no custom compound-address type).
- Lead→Opportunity field mapping still to be done manually.
- **`BakerooOrg` has leftover stock sample data** — ~17 `GenWatt`/`SLA`/`Installation` `Product2` rows on a
  stray active custom pricebook literally named **"Standard"** (not the real Standard Pricebook). Pre-existing,
  untouched by the seed; clean up if/when it clutters the menu. Scratch is clean.
- `Recipe_Ingredient__c.Unit__c` (Build Plan §5.4) still unbuilt — deferred (unit derivable from ingredient UoM).
