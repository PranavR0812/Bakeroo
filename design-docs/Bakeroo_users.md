# Bakeroo Cloud Kitchen — Internal User Setup (Dev Org)

> **Purpose.** A runbook for creating the **internal staff users** on `BakerooOrg` (the persistent dev /
> promotion org) and wiring each to the right **role**, **profile**, and **permission sets**. All the
> supporting metadata (roles, the `Bakeroo Internal` profile, the function permission sets) is already
> built and deployed — this doc is the *assignment / provisioning* step, which is manual (users aren't
> tracked as deployable metadata).
>
> Related: `Bakeroo_Admin_Phase_Summary.md` (§2.7 perm sets / profile / roles), `Bakeroo_Build_Plan.md` §10.

---

## 0. What already exists (prerequisites — no build needed)

- **Roles (6):** `Managing_Director` › (`Sales_Manager` › `Sales_Rep`) + (`Operations_Manager` ›
  `Support_Executive`, `Delivery_Manager`). System Admin sits effectively at the top (no role needed).
- **Profile:** `Bakeroo Internal` (minimal, `Salesforce` license; carries business/order record-type visibility).
- **Permission sets:** `Bakeroo_Sales`, `Bakeroo_Operations`, `Bakeroo_Procurement`, `Bakeroo_Delivery_Mgmt`,
  `Bakeroo_Support` (function access) + `Bakeroo_All_Fields` (broad admin helper).
- **Delivery agents are NOT users** — they're `Delivery_Agent__c` records. No user/role/license for them.

---

## 1. ⚠️ Read first — Developer Edition license limit

`BakerooOrg` is a **Developer Edition** org, which ships with only a **small number of full `Salesforce`
licenses** (often ~2, plus a few Platform/Community ones). The `Bakeroo Internal` profile needs a
**`Salesforce`** license, so you may **not** be able to create all six role users.

**Before creating anyone:** *Setup → Company Information → User Licenses* — check the **Used vs. Total**
count for **Salesforce**.

- If licenses are tight, create the **minimum viable set** for what you're demonstrating (e.g. Admin +
  Sales Rep + Operations Manager), and simulate the rest with the admin.
- Sales/Support roles **require** a full `Salesforce` license (they use `Lead`/`Opportunity`/`Quote`/`Case`).
  Platform-type licenses **don't** include those standard CRM objects, so don't substitute them there.
- You can **deactivate** a user to free a license and reuse it for another role while testing.

---

## 2. User roster — who gets what

| # | Sample user | Role | Profile | Permission set(s) | Why |
|---|---|---|---|---|---|
| 1 | *(existing admin)* | — (top of hierarchy) | System Administrator | `Bakeroo_All_Fields` | Full config + full field visibility |
| 2 | Maya Director | `Managing_Director` | Bakeroo Internal | `Bakeroo_Sales`, `Bakeroo_Operations`, `Bakeroo_Procurement`, `Bakeroo_Delivery_Mgmt`, `Bakeroo_Support` | Oversees both branches → full functional access (role hierarchy already gives record visibility) |
| 3 | Sam Salesmgr | `Sales_Manager` | Bakeroo Internal | `Bakeroo_Sales` | B2B pipeline (Lead/Opp/Quote/Order R-W) |
| 4 | Riya Rep | `Sales_Rep` | Bakeroo Internal | `Bakeroo_Sales` | Works bulk Leads/Opps under the SM |
| 5 | Omar Opsmgr | `Operations_Manager` | Bakeroo Internal | `Bakeroo_Operations`, `Bakeroo_Procurement` | Kitchen + procurement (recipes, inventory, POs) |
| 6 | Sana Support | `Support_Executive` | Bakeroo Internal | `Bakeroo_Support` | Cases (R-W), Account/Order (R) |
| 7 | Dev Deliverymgr | `Delivery_Manager` | Bakeroo Internal | `Bakeroo_Delivery_Mgmt` | Deliveries + delivery agents (R-W) |

> **MD note:** the five perm sets give the MD hands-on access to every function. If you'd rather keep the
> MD read-oriented, assign fewer and rely on the role hierarchy for visibility — but note the function
> perm sets are what grant the *object/field* access; the role only grants *record* visibility down the tree.
>
> **Procurement:** folded onto the Operations Manager here (§10.2 allows `Bakeroo_Procurement` to sit with
> Operations). Split it onto a dedicated buyer if you add that role later.

---

## 3. Create users — Option A: Setup UI (recommended for the persistent org)

For each user (repeat per row above):

1. *Setup → Users → Users → **New User**.*
2. **First/Last Name**, **Alias**, **Email** (a real inbox you can reach — the activation email lands there).
3. **Username** — must be **globally unique across all Salesforce**, email-formatted. Convention:
   `role@bakeroo.<yourorg>.dev` (e.g. `sales.rep@bakeroo.bakeroo.dev`). It does *not* need to be a real address.
4. **User License** → **Salesforce**.  **Profile** → **Bakeroo Internal**.
5. **Role** → pick the matching role (Managing Director / Sales Manager / Sales Rep / Operations Manager /
   Support Executive / Delivery Manager).
6. Leave "Generate new password and notify user immediately" checked → **Save**.
7. Repeat for each role. (Do the **Managing Director first**, then the managers, then their reports — roles
   already exist, so order doesn't strictly matter, but it reads cleaner.)

Then assign permission sets — see **§5**.

---

## 4. Create users — Option B: CLI (`sf org create user`)

Faster and repeatable. Create one JSON per user under `config/users/` (git-ignored or kept as templates —
these hold no secrets). Example `config/users/sales_rep.json`:

```json
{
  "Email": "riya.rep@bakeroo.example.com",
  "Username": "sales.rep@bakeroo.<yourorg>.dev",
  "LastName": "Rep",
  "FirstName": "Riya",
  "Alias": "sRep",
  "ProfileName": "Bakeroo Internal",
  "permsets": ["Bakeroo_Sales"]
}
```

Create the user (it also assigns the `permsets` listed):

```bash
sf org create user -o BakerooOrg --definition-file config/users/sales_rep.json
```

> **Role is not set by this command.** Assign the role afterward (see **§6**). Also mind the **license
> limit** (§1) — `sf org create user` will fail if no `Salesforce` license is free.

Repeat with a JSON per role, setting the matching `permsets` from the §2 table (the MD file lists all five).

---

## 5. Assign permission sets

**UI:** *Setup → Users → Users → (open user) → Permission Set Assignments → Edit Assignments* → add the
set(s) from the §2 table → Save.

**CLI** (per user, per set — `--on-behalf-of` takes the username):

```bash
sf org assign permset -o BakerooOrg --name Bakeroo_Sales --on-behalf-of "sales.rep@bakeroo.<yourorg>.dev"
```

For the MD, assign all five:

```bash
sf org assign permset -o BakerooOrg --on-behalf-of "md@bakeroo.<yourorg>.dev" \
  --name Bakeroo_Sales --name Bakeroo_Operations --name Bakeroo_Procurement \
  --name Bakeroo_Delivery_Mgmt --name Bakeroo_Support
```

> Permission sets grant the **object CRUD + field-level security**. The `Bakeroo Internal` profile stays
> minimal on purpose — do **not** move object access onto the profile.

---

## 6. Assign roles

If you created users in the UI (§3) you already set the role. For CLI-created users, set it afterward:

**UI:** open the user → **Role** → pick the matching role → Save.

**CLI (data update):** look up the role Id, then set it on the user:

```bash
# find the role Id
sf data query -o BakerooOrg -q "SELECT Id,Name,DeveloperName FROM UserRole WHERE DeveloperName='Sales_Rep'"
# set it on the user
sf data update record -o BakerooOrg -s User -w "Username='sales.rep@bakeroo.<yourorg>.dev'" -v "UserRoleId=<roleId>"
```

---

## 7. Record types & layouts

- **Record-type visibility** is already granted by the `Bakeroo Internal` profile (Account `Bulk_Buyer`/
  `Supplier`, Order `Same_Day_B2C`/`Bulk_Scheduled_B2B`), so these users can pick the right RTs. Actual
  create/edit is gated by each user's function perm set (e.g. only Sales/Ops can create Orders).
- **Caveat — tailored layouts:** the record-type page layouts (e.g. `Order-Same_Day_B2C`) are currently
  assigned via the **Admin** profile only. `Bakeroo Internal` users will see the **default** layout per RT
  until layout assignments are added to that profile. Follow-up (small): deploy a partial `Bakeroo Internal`
  profile with `<layoutAssignments>` for the four business/order RTs (same minimal-partial technique used for Admin).

---

## 8. Post-setup verification

- *Setup → Users* — confirm each user's **Profile**, **Role**, and **active** status.
- Log in as (or use *Login As*) a role user and confirm scope, e.g.:
  - **Sales Rep** sees Leads/Opportunities/Quotes/Orders; **cannot** see Purchase Orders.
  - **Operations Manager** sees Recipes/Inventory/Purchase Orders; **cannot** edit Opportunities.
  - **Support Executive** sees Cases + read-only Account/Order.
- Spot-check a **supplier lookup** (e.g. on a Purchase Order) shows only Supplier-record-type accounts.
- Confirm the role **hierarchy** — a manager can see their reports' records (e.g. SM sees SR's Opportunities).

---

## 9. Notes & housekeeping

- **Delivery agents** are `Delivery_Agent__c` **records**, not users — create them as data, no license.
- **Community/external customers** are a **separate** setup (Experience Cloud phase, Build Plan §16) — a
  `Customer Community Plus` profile + `Bakeroo_Customer_Community` perm set + sharing sets, not covered here.
- Keep usernames on a consistent domain suffix so they're easy to find and won't collide globally.
- To free a `Salesforce` license, **deactivate** (don't delete — users can't be deleted) an unused user.
- This is a **`BakerooOrg`-only** task. On `BakerooScratch`, the scratch admin is usually enough; create
  role users there only if you need to test sharing/visibility.

---

## Appendix — permission-set → role quick map

| Permission set | Grants (scope) | Assigned to |
|---|---|---|
| `Bakeroo_Sales` | Lead, Opportunity, Quote, Order (R/W); Product2, Pricebook (R) | Sales Manager, Sales Rep, (MD) |
| `Bakeroo_Operations` | Ingredient, Recipe(+junction), Inventory, Reservation, Ingredient-Supplier, Purchase Order(+Line), Delivery, Delivery Agent (R/W); Order (R) | Operations Manager, (MD) |
| `Bakeroo_Procurement` | Purchase Order(+Line), Ingredient-Supplier (R/W); Ingredient (R) | Operations Manager, (MD) |
| `Bakeroo_Delivery_Mgmt` | Delivery, Delivery Agent (R/W); Order (R) | Delivery Manager, (MD) |
| `Bakeroo_Support` | Case (R/W); Account, Contact, Order (R) | Support Executive, (MD) |
| `Bakeroo_All_Fields` | FLS on all custom fields (RO on roll-up/formula) + CRUD on custom objects | System Admin |
