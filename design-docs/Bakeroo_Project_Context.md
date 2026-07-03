# Bakeroo Cloud Kitchen — Project Context & Handoff

> **Purpose of this document.** This is a context/handoff brief for AI agents (e.g. Claude Code) joining the Bakeroo project in a fresh conversation. It captures what the project is, how it started, the design decisions made and *why*, the current state, and what's next. Read this first; it is the source of truth for intent. Detailed artifacts live in two companion files (see [File index](#file-index)). **Treat the decisions in section 4 as settled unless the project owner reopens them** — several were chosen after weighing alternatives that were explicitly rejected.

---

## 1. What Bakeroo is

**Bakeroo Cloud Kitchen** is an *imaginary* cloud kitchen (delivery-only food business, bakery-leaning) used as the domain for a **Salesforce implementation exercise**. The goal is to design and build a Salesforce application spanning three clouds:

- **Commerce Cloud (D2C) + Experience Cloud** — the customer storefront, cart, and checkout.
- **Sales Cloud** — the B2B / bulk-order pipeline (Lead → Opportunity → Quote → Order).
- **Service Cloud** — customer support (cases, handled by a Support Executive or AI agent).

The project owner is comfortable with Salesforce concepts and terminology, so agents can use Salesforce vocabulary freely (record types, master-detail, roll-up summaries, record-triggered Flows, PricebookEntry, etc.) without over-explaining basics.

The domain has three moving parts that make it interesting: a **B2C same-day path**, a **B2B future-dated bulk path**, and an **ingredient inventory / procurement loop** that both customer paths feed into.

---

## 2. How the project started

The owner uploaded **three handwritten notebook photos** containing rough markups:

1. **Users / role hierarchy** — the actors in the system.
2. **A "V1" process-flow sketch** — customer journey from storefront through delivery, plus the bulk-order and inventory branches.
3. **A data-model sketch** — a "Standard" vs "Custom" object split.

The opening request was: *read the notes and produce process flows for (1) a small same-day order, (2) a bulk order for a later date, and (3) how ingredient inventory gets replenished from suppliers* — with the object list and data model to follow. Everything since has been iterative refinement of those flows and then the data model.

### Actors / role hierarchy (from the notes)

| Role | Abbrev | Notes |
|---|---|---|
| System Admin | — | Configures/maintains the org |
| Sales Manager | SM | Owns SRs |
| Sales Rep | SR | Works bulk Leads/Opportunities |
| Operations Manager | OM | Formerly "Kitchen Manager"; owns kitchen + procurement |
| Managing Director / CEO | MD | Top of hierarchy |
| Experience Cloud Customer | — | B2C shoppers (external users) |
| Support Executive | SE | Handles Cases (Service Cloud); may be AI-assisted |
| Delivery Agent (Driver) | — | Fulfills deliveries |
| Delivery Manager | — | Oversees delivery agents |

Rough reporting sketch from the notes: MD at top; SM → SRs; OM branch → (kitchen/ops) and SE (support). These map to **profiles / roles / permission sets**, not objects.

---

## 3. The three process flows (summary)

Full written steps + Mermaid diagrams are in `Bakeroo_Process_Flows_v1.md`. In brief:

**Flow 1 — Small same-day order (B2C, Commerce):** guest browses → adds to cart as guest → **login/register at the cart→checkout boundary** → same-day feasibility check (cutoff + capacity) → ingredient availability + **soft reservation** → payment → Order created → kitchen queue → prep **deducts inventory** (finalizes reservation) → auto-assign delivery agent → status notifications → delivered → **Feedback + Loyalty Points**. Branches for cancel/refund/failed delivery; **Support Case** can be raised in parallel.

**Flow 2 — Bulk order for a later date (B2B, Sales):** two entry points — an explicit **"Bulk Order?" button** (guest-accessible) or an **automatic bulk-threshold trip** from the cart. Captures a **requested delivery date** (the anchor). New buyer → Lead → convert to Account+Contact+Opportunity; returning buyer → new Opportunity on the existing Account. **Feasibility check** (kitchen capacity + ingredient projection to the requested date) → **Quote** (feasible date + bulk price) → **discount approval** if above threshold → **deposit** → **Closed-Won = commit point** (create forward reservation; trigger replenishment PO into Flow 3 if short) → scheduled Order → **scheduled automation drops it into the kitchen** N hours before the date, gated on goods-receipt → prep/deliver → Feedback + Loyalty.

**Flow 3 — Ingredient replenishment (procurement):** **two entry points** converging on one pipeline. **Entry A (reactive):** consumption pushes an ingredient below threshold (threshold + safety stock + lead time). **Entry B (forward):** a committed bulk order needs stock that isn't there yet. Flagged ingredients are **batched, grouped by supplier**, and turned into **one consolidated Purchase Order per supplier** → approval tiering (auto vs OM) → alert OM/Admin → supplier fulfills → **goods receipt** (partial deliveries handled) → inventory replenished. For Entry-B POs, goods receipt **signals back to Flow 2** to release the gated kitchen drop.

### How the flows connect
- Flows 1 & 2 consume ingredients at prep → feed Flow 3 **Entry A**.
- Flow 2 hands a forward shortfall to Flow 3 **Entry B**; Flow 3 hands a goods-receipt confirmation back to Flow 2.
- Both customer flows end in Feedback + Loyalty and can spin off a Support Case.

---

## 4. Key design decisions (with rationale) — treat as settled

These are the choices an agent must **not** silently undo.

1. **Split-object design for orders vs procurement.** Customer orders use **standard `Order` / `OrderItem`**; supplier procurement uses **custom `Purchase_Order__c` / `Purchase_Order_Line__c`**. *Rationale:* different lifecycles/fields, plus multi-supplier logic and a receiving (goods-receipt, partial-delivery) step tip the balance toward separation. The single-object alternative (everything on `Order` via record types, ingredients as shadow `Product2` records) was written up and **rejected** — it survives only as *Appendix A* in the data-model doc as a decision record.

2. **Three-cloud split by a bulk threshold.** Small orders stay in Commerce self-service; crossing the bulk threshold (or clicking "Bulk Order?") routes into the Sales pipeline. This keeps B2C and B2B cleanly separated in the model.

3. **Bulk order has two entry points**, one of which is **guest-accessible** ("Bulk Order?" button → bulk screen, no login/cart needed). Account/Contact are only created at Lead conversion — keeps the B2B path low-friction.

4. **Forced login at the cart→checkout boundary (not storefront entry).** *Rationale:* **loyalty is core to V1** and needs a durable identity anchor (Contact / Person Account); but browsing and cart stay guest-friendly to protect conversion. (Guest checkout is a V2 consideration, deliberately deferred because it would undercut loyalty.)

5. **Account record types:** **Customer = Person Account** (individual consumers, loyalty lives here); **Bulk Buyer = Business Account**; **Supplier = Business Account**. ⚠️ **Person Accounts are irreversible once enabled** — flagged for explicit owner sign-off before enabling in the org.

6. **Product2 = sellable menu item; `Ingredient__c` = raw material (custom).** They are distinct. **`Recipe__c`** bridges them as a bill-of-materials via the **`Recipe_Ingredient__c` junction** (quantity of each ingredient per recipe). Inventory deduction and the bulk feasibility projection both depend on this junction being accurate — it is load-bearing.

7. **Ingredient master vs stock are separate objects** (`Ingredient__c` vs `Ingredient_Inventory__c`). *Rationale:* lets V2 batch/expiry tracking add multiple stock rows per ingredient without reworking the model. V1 can run one inventory row per ingredient.

8. **`Inventory_Reservation__c` is a first-class object.** It powers the **soft reserve** (same-day, Flow 1) and **forward reserve** (bulk, Flow 2), and feeds `Quantity Available` so the system never oversells. Without it, the feasibility projection has nothing to read.

9. **`Ingredient_Supplier__c` junction is the procurement source of truth** (carries unit price, lead time, is-preferred, min order qty). The `Preferred Supplier` lookup on `Ingredient__c` is only a convenience default. The "can we replenish before the requested date?" check reads lead time from this junction.

10. **Bulk feasibility = a projection to the requested date**, not a "do we have it now?" check: `projected stock on date = current on-hand − already reserved/committed + inbound POs arriving before the date`, compared to `Recipe needs × bulk quantity`. **Three outcomes:** enough → forward-reserve; shortfall but replenishable in time → proceed + trigger PO; shortfall not replenishable in time → renegotiate/decline. The projection runs at **Quote** stage (no spend); the real replenishment PO is placed only at **Closed-Won + deposit** (deposit de-risks buying perishables); and the kitchen drop is **gated on goods-receipt** of that PO.

11. **Loyalty = ledger + rollup.** `Loyalty_Point_Transaction__c` (earn/redeem/adjustment) with a roll-up balance on `Account`, not a single mutable balance field — gives an auditable history and a self-maintaining balance.

12. **Delivery = `Delivery__c` custom object; Delivery Agent = `User` lookup** (assumes drivers are licensed users). **Open:** if drivers won't be licensed, swap to a lightweight `Delivery_Agent__c` object with an availability flag — see section 7.

13. **A `Quote` step sits between Opportunity and Order** for bulk, as the natural home for negotiated pricing.

14. **Procurement is not purely reactive.** Confirmed future bulk orders pre-trigger procurement (Flow 3 Entry B) rather than waiting for stock to hit the reactive threshold — the forecast-driven idea, scoped tightly to bulk orders where reactive reordering fails.

Additional flow refinements folded into V1 (lower-level, but real): payment must clear before the kitchen starts; same-day feasibility gate (cutoff time + capacity); customer status notifications; cancel/refund/failed-delivery branches; auto-assign delivery agent; consolidated **one-PO-per-supplier** with line items; PO approval tiering by value; goods-receipt with partial deliveries.

### Explicitly deferred to V2
Guest checkout; recurring / contract bulk orders (standing weekly orders); expiry / shelf-life / FIFO tracking for perishables; broader forecast-driven procurement beyond bulk orders.

---

## 5. Object model (summary)

Full field-level detail and the Mermaid ER diagram are in `Bakeroo_Data_Model_v1.md`. Object inventory:

**Standard (reused):** `Account` (Customer/Bulk Buyer/Supplier via record types), `Contact`, `Lead`, `Opportunity`, `Quote` (+`QuoteLineItem`), `Product2`, `Pricebook2`/`PricebookEntry`, `Order`/`OrderItem` (customer orders only), `WebCart`/`CartItem` (Commerce), `Case`.

**Custom:** `Recipe__c`, `Ingredient__c`, `Recipe_Ingredient__c` (junction), `Ingredient_Inventory__c`, `Inventory_Reservation__c`, `Ingredient_Supplier__c` (junction), `Purchase_Order__c`, `Purchase_Order_Line__c`, `Delivery__c`, `Feedback__c`, `Loyalty_Point_Transaction__c`.

**Key junctions:** `Recipe_Ingredient__c` (Recipe ↔ Ingredient), `Ingredient_Supplier__c` (Ingredient ↔ Supplier Account). **Entry-B link:** `Purchase_Order__c.Linked_Order__c` → the bulk `Order` it replenishes for.

---

## 6. Current status

**Done (design):**
- Three process flows finalized with diagrams → `Bakeroo_Process_Flows_v1.md`.
- Data model finalized (objects, fields, relationships, ER diagram) on the **split-object** design → `Bakeroo_Data_Model_v1.md`, with the rejected single-object variant preserved as Appendix A.

**Not yet started:** any actual org configuration/metadata, and the **automation layer** (next).

---

## 7. Next steps & open questions

**Next: the automation layer** (design outlined, not yet detailed/built):
- **Roll-ups / formulas:** `Ingredient_Inventory__c.Quantity Available` (On Hand − Reserved; Reserved = roll-up of active reservations); `Account.Loyalty Points Balance` (roll-up of transactions); `Purchase_Order__c.Total` (roll-up of lines).
- **Record-triggered Flows:** same-day feasibility on Order create; inventory deduction when Kitchen Status → Prepared; reactive reorder on inventory update (Entry A); forward-shortfall on Opportunity Closed-Won + deposit (Entry B); goods-receipt on PO Line update (replenish; if Entry B, release kitchen drop); delivery success → Feedback request + loyalty accrual.
- **Scheduled Flow:** drop bulk order into kitchen N hours before delivery date, gated on goods-receipt confirmation.
- **Approval processes:** bulk discount above threshold → OM/MD; high-value Purchase Order → OM.

**Open decisions still pending sign-off:**
- **Delivery agents:** licensed `User` records vs a `Delivery_Agent__c` custom object (affects the Delivery lookup).
- **Person Accounts:** confirm before enabling (irreversible).
- **Payment:** whether COD is allowed alongside pay-before-kitchen.

---

## 8. Conventions for agents

- Custom objects/fields use the `__c` suffix; junctions named `<A>_<B>__c`.
- When building automation, respect the **split** between customer `Order` and supplier `Purchase_Order__c` — do not merge them.
- The **Recipe → Recipe Ingredient** junction is the single mechanism for both inventory deduction and bulk feasibility; keep all consumption logic routed through it.
- Preserve the **reservation → deduction** lifecycle: reserve at checkout/commit, finalize-and-deduct at prep, release on cancel.
- Anything the docs mark **V2** should not be built into V1 without the owner reopening it.

---

## File index

| File | Contents |
|---|---|
| `Bakeroo_Project_Context.md` | *This file* — project overview, decisions, status, handoff notes |
| `Bakeroo_Process_Flows_v1.md` | Three process flows: written steps + Mermaid flowcharts |
| `Bakeroo_Data_Model_v1.md` | Objects, fields, relationships, Mermaid ER diagram; Appendix A = rejected single-object variant |
