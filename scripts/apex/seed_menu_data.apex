/*
 * Bakeroo §8 seed — small farm-to-table menu dataset (DATA, not metadata).
 * Idempotent-ish: deletes prior seed rows by known keys, then re-inserts.
 * Safe to run against an empty org (BakerooScratch first, then BakerooOrg).
 *
 * Covers: Ingredient__c, Ingredient_Inventory__c, Product2 (+ Standard &
 * Bakeroo Menu PricebookEntry), Recipe__c, Recipe_Ingredient__c.
 * Roll-ups/formulas (Quantity_Available__c, etc.) populate automatically.
 */

// ---- 0. Clean prior seed (makes the script re-runnable) --------------------
Set<String> skus = new Set<String>{'BREAD-001','PASTRY-001','CAKE-001','PASTRY-002','BEV-001'};
delete [SELECT Id FROM Recipe_Ingredient__c];
delete [SELECT Id FROM Recipe__c];
delete [SELECT Id FROM Ingredient_Inventory__c];
delete [SELECT Id FROM PricebookEntry WHERE Product2Id IN (SELECT Id FROM Product2 WHERE ProductCode IN :skus)];
delete [SELECT Id FROM Product2 WHERE ProductCode IN :skus];
delete [SELECT Id FROM Ingredient__c];
delete [SELECT Id FROM Pricebook2 WHERE Name = 'Bakeroo Menu'];

// ---- 1. Activate the Standard Pricebook (inactive by default) --------------
Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
if (!std.IsActive) { std.IsActive = true; update std; }

// ---- 2. Ingredients (raw materials) ----------------------------------------
Map<String, Ingredient__c> ing = new Map<String, Ingredient__c>();
ing.put('Flour',       new Ingredient__c(Name='All-Purpose Flour',  Unit_of_Measure__c='Kilogram (kg)', Reorder_Threshold__c=10, Safety_Stock__c=5,    Is_Perishable__c=false));
ing.put('Butter',      new Ingredient__c(Name='Butter',             Unit_of_Measure__c='Kilogram (kg)', Reorder_Threshold__c=5,  Safety_Stock__c=2,    Is_Perishable__c=true));
ing.put('Sugar',       new Ingredient__c(Name='Granulated Sugar',   Unit_of_Measure__c='Kilogram (kg)', Reorder_Threshold__c=8,  Safety_Stock__c=4,    Is_Perishable__c=false));
ing.put('Eggs',        new Ingredient__c(Name='Eggs',               Unit_of_Measure__c='Gram (g)',      Reorder_Threshold__c=2000, Safety_Stock__c=1000, Is_Perishable__c=true));
ing.put('Milk',        new Ingredient__c(Name='Whole Milk',         Unit_of_Measure__c='Liter (L)',     Reorder_Threshold__c=10, Safety_Stock__c=5,    Is_Perishable__c=true));
ing.put('Cocoa',       new Ingredient__c(Name='Cocoa Powder',       Unit_of_Measure__c='Kilogram (kg)', Reorder_Threshold__c=3,  Safety_Stock__c=1,    Is_Perishable__c=false));
ing.put('Blueberries', new Ingredient__c(Name='Fresh Blueberries',  Unit_of_Measure__c='Kilogram (kg)', Reorder_Threshold__c=3,  Safety_Stock__c=1,    Is_Perishable__c=true));
ing.put('Yeast',       new Ingredient__c(Name='Active Dry Yeast',   Unit_of_Measure__c='Gram (g)',      Reorder_Threshold__c=500, Safety_Stock__c=200,  Is_Perishable__c=false));
ing.put('Salt',        new Ingredient__c(Name='Salt',               Unit_of_Measure__c='Kilogram (kg)', Reorder_Threshold__c=2,  Safety_Stock__c=1,    Is_Perishable__c=false));
ing.put('Tea',         new Ingredient__c(Name='Black Tea Leaves',   Unit_of_Measure__c='Gram (g)',      Reorder_Threshold__c=500, Safety_Stock__c=200,  Is_Perishable__c=false));
insert ing.values();

// ---- 3. Inventory (1 stock row per ingredient) -----------------------------
Map<String, Decimal> onHand = new Map<String, Decimal>{
    'Flour'=>50, 'Butter'=>20, 'Sugar'=>40, 'Eggs'=>15000, 'Milk'=>60,
    'Cocoa'=>12, 'Blueberries'=>10, 'Yeast'=>2500, 'Salt'=>8, 'Tea'=>2000
};
List<Ingredient_Inventory__c> invs = new List<Ingredient_Inventory__c>();
for (String k : ing.keySet()) {
    invs.add(new Ingredient_Inventory__c(Ingredient__c=ing.get(k).Id, Quantity_On_Hand__c=onHand.get(k)));
}
insert invs;

// ---- 4. Products (sellable menu items) -------------------------------------
Map<String, Product2> prod = new Map<String, Product2>();
prod.put('BREAD-001',  new Product2(Name='Classic Sourdough Loaf', ProductCode='BREAD-001',  Category__c='Breads',    Prep_Time_Min__c=45, Is_Available__c=true, IsActive=true));
prod.put('PASTRY-001', new Product2(Name='Butter Croissant',       ProductCode='PASTRY-001', Category__c='Pastries',  Prep_Time_Min__c=30, Is_Available__c=true, IsActive=true));
prod.put('CAKE-001',   new Product2(Name='Chocolate Fudge Cake',   ProductCode='CAKE-001',   Category__c='Cakes',     Prep_Time_Min__c=90, Is_Available__c=true, IsActive=true));
prod.put('PASTRY-002', new Product2(Name='Blueberry Muffin',       ProductCode='PASTRY-002', Category__c='Pastries',  Prep_Time_Min__c=25, Is_Available__c=true, IsActive=true));
prod.put('BEV-001',    new Product2(Name='Masala Chai',            ProductCode='BEV-001',    Category__c='Beverages', Prep_Time_Min__c=8,  Is_Available__c=true, IsActive=true));
insert prod.values();

// ---- 5. Pricebook entries: Standard (required first) + Bakeroo Menu ---------
Map<String, Decimal> price = new Map<String, Decimal>{
    'BREAD-001'=>8.00, 'PASTRY-001'=>4.50, 'CAKE-001'=>32.00, 'PASTRY-002'=>3.75, 'BEV-001'=>3.25
};
List<PricebookEntry> stdEntries = new List<PricebookEntry>();
for (String sku : prod.keySet()) {
    stdEntries.add(new PricebookEntry(Pricebook2Id=std.Id, Product2Id=prod.get(sku).Id, UnitPrice=price.get(sku), IsActive=true));
}
insert stdEntries;

Pricebook2 menu = new Pricebook2(Name='Bakeroo Menu', IsActive=true, Description='D2C storefront catalog');
insert menu;
List<PricebookEntry> menuEntries = new List<PricebookEntry>();
for (String sku : prod.keySet()) {
    menuEntries.add(new PricebookEntry(Pricebook2Id=menu.Id, Product2Id=prod.get(sku).Id, UnitPrice=price.get(sku), IsActive=true, UseStandardPrice=false));
}
insert menuEntries;

// ---- 6. Recipes (1 per product) --------------------------------------------
Map<String, Recipe__c> rec = new Map<String, Recipe__c>();
rec.put('BREAD-001',  new Recipe__c(Name='Classic Sourdough Loaf Recipe', Product__c=prod.get('BREAD-001').Id,  Yield__c=2,  Active__c=true));
rec.put('PASTRY-001', new Recipe__c(Name='Butter Croissant Recipe',       Product__c=prod.get('PASTRY-001').Id, Yield__c=12, Active__c=true));
rec.put('CAKE-001',   new Recipe__c(Name='Chocolate Fudge Cake Recipe',   Product__c=prod.get('CAKE-001').Id,   Yield__c=1,  Active__c=true));
rec.put('PASTRY-002', new Recipe__c(Name='Blueberry Muffin Recipe',       Product__c=prod.get('PASTRY-002').Id, Yield__c=12, Active__c=true));
rec.put('BEV-001',    new Recipe__c(Name='Masala Chai Recipe',            Product__c=prod.get('BEV-001').Id,    Yield__c=4,  Active__c=true));
insert rec.values();

// ---- 7. Recipe_Ingredient junction rows (Quantity_Required per batch) -------
List<Recipe_Ingredient__c> ri = new List<Recipe_Ingredient__c>();
// Sourdough (yield 2 loaves)
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('BREAD-001').Id, Ingredient__c=ing.get('Flour').Id, Quantity_Required__c=1));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('BREAD-001').Id, Ingredient__c=ing.get('Yeast').Id, Quantity_Required__c=10));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('BREAD-001').Id, Ingredient__c=ing.get('Salt').Id,  Quantity_Required__c=0.02));
// Croissant (yield 12)
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-001').Id, Ingredient__c=ing.get('Flour').Id,  Quantity_Required__c=1));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-001').Id, Ingredient__c=ing.get('Butter').Id, Quantity_Required__c=0.5));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-001').Id, Ingredient__c=ing.get('Sugar').Id,  Quantity_Required__c=0.1));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-001').Id, Ingredient__c=ing.get('Yeast').Id,  Quantity_Required__c=10));
// Chocolate Fudge Cake (yield 1)
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('CAKE-001').Id, Ingredient__c=ing.get('Flour').Id,  Quantity_Required__c=0.5));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('CAKE-001').Id, Ingredient__c=ing.get('Butter').Id, Quantity_Required__c=0.25));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('CAKE-001').Id, Ingredient__c=ing.get('Sugar').Id,  Quantity_Required__c=0.4));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('CAKE-001').Id, Ingredient__c=ing.get('Cocoa').Id,  Quantity_Required__c=0.15));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('CAKE-001').Id, Ingredient__c=ing.get('Eggs').Id,   Quantity_Required__c=200));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('CAKE-001').Id, Ingredient__c=ing.get('Milk').Id,   Quantity_Required__c=0.25));
// Blueberry Muffin (yield 12)
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-002').Id, Ingredient__c=ing.get('Flour').Id,       Quantity_Required__c=0.5));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-002').Id, Ingredient__c=ing.get('Sugar').Id,       Quantity_Required__c=0.2));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-002').Id, Ingredient__c=ing.get('Eggs').Id,        Quantity_Required__c=150));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-002').Id, Ingredient__c=ing.get('Milk').Id,        Quantity_Required__c=0.2));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('PASTRY-002').Id, Ingredient__c=ing.get('Blueberries').Id, Quantity_Required__c=0.3));
// Masala Chai (yield 4)
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('BEV-001').Id, Ingredient__c=ing.get('Milk').Id,  Quantity_Required__c=0.5));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('BEV-001').Id, Ingredient__c=ing.get('Sugar').Id, Quantity_Required__c=0.05));
ri.add(new Recipe_Ingredient__c(Recipe__c=rec.get('BEV-001').Id, Ingredient__c=ing.get('Tea').Id,   Quantity_Required__c=20));
insert ri;

System.debug('Seed complete: ' + ing.size() + ' ingredients, ' + prod.size() + ' products, ' + rec.size() + ' recipes, ' + ri.size() + ' recipe-ingredient rows.');
