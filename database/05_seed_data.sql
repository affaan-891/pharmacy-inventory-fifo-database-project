-- ============================================================================
-- PHARMACY EXPIRY & BATCH-WISE FIFO INVENTORY SYSTEM
-- Comprehensive Realistic Pharmaceutical Seed Data (DML)
-- Target Engine: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Storage Engine)
-- Script: 05_seed_data.sql
-- ============================================================================

USE pharmacy_inventory_db;

-- Clear previous data in correct dependency sequence
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE inventory_audit_logs;
TRUNCATE TABLE purchase_order_items;
TRUNCATE TABLE purchase_orders;
TRUNCATE TABLE sales_order_items;
TRUNCATE TABLE sales_orders;
TRUNCATE TABLE prescriptions;
TRUNCATE TABLE customers;
TRUNCATE TABLE medicine_batches;
TRUNCATE TABLE medicines;
TRUNCATE TABLE categories;
TRUNCATE TABLE suppliers;
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- 1. SEED SUPPLIERS (5 Global Pharmaceutical Manufacturers)
-- ============================================================================
INSERT INTO suppliers (supplier_id, company_name, contact_person, email, phone, address, rating) VALUES
(1, 'Pfizer Global Distribution', 'Marcus Sterling', 'distribution@pfizer-supply.com', '+1-800-555-0191', '235 E 42nd St, New York, NY 10017', 4.9),
(2, 'Novartis Healthcare Corp', 'Dr. Elena Rostova', 'procurement@novartis-pharma.com', '+1-800-555-0192', 'One Health Plaza, East Hanover, NJ 07936', 4.8),
(3, 'GlaxoSmithKline (GSK) Logistics', 'Arthur Pendelton', 'orders@gsk-logistics.com', '+1-800-555-0193', '980 Great West Road, Brentford, UK', 4.7),
(4, 'Sanofi MedSupply International', 'Claire Dubois', 'contact@sanofi-supply.com', '+1-800-555-0194', '54 Rue La Boétie, 75008 Paris, France', 4.6),
(5, 'Sun Pharmaceutical Industries', 'Rajesh K. Verma', 'commercial@sunpharma-intl.com', '+1-800-555-0195', 'Goregaon East, Mumbai, Maharashtra 400063', 4.5);

-- ============================================================================
-- 2. SEED CATEGORIES (6 Therapeutic Classes)
-- ============================================================================
INSERT INTO categories (category_id, category_name, requires_prescription) VALUES
(1, 'Antibiotics & Antimicrobials', TRUE),
(2, 'Analgesics & Antipyretics (OTC)', FALSE),
(3, 'Cardiovascular Agents', TRUE),
(4, 'Antidiabetic Agents', TRUE),
(5, 'Schedule II-IV Controlled Narcotics', TRUE),
(6, 'Respiratory & Antihistamines', FALSE);

-- ============================================================================
-- 3. SEED MEDICINES (12 Formulary Drug Entities)
-- ============================================================================
INSERT INTO medicines (medicine_id, brand_name, generic_name, category_id, dosage_form, reorder_level, is_controlled_substance) VALUES
(1,  'Amoxil 500mg',           'Amoxicillin Trihydrate',      1, 'Tablet',    100, FALSE),
(2,  'Zithromax 250mg',        'Azithromycin Dihydrate',      1, 'Capsule',    60, FALSE),
(3,  'Cipro 500mg',            'Ciprofloxacin HCl',           1, 'Tablet',     50, FALSE),
(4,  'Panadol Extra 500mg',    'Paracetamol / Caffeine',      2, 'Tablet',    200, FALSE),
(5,  'Advil 400mg',            'Ibuprofen',                   2, 'Tablet',    150, FALSE),
(6,  'Ultram 50mg',            'Tramadol Hydrochloride',      5, 'Capsule',    40, TRUE),
(7,  'Duramorph 10mg/mL',      'Morphine Sulfate',            5, 'Injection',  20, TRUE),
(8,  'Lipitor 20mg',           'Atorvastatin Calcium',        3, 'Tablet',     80, FALSE),
(9,  'Glucophage 500mg',       'Metformin Hydrochloride',     4, 'Tablet',    120, FALSE),
(10, 'Zyrtec 10mg',            'Cetirizine Hydrochloride',    6, 'Tablet',    100, FALSE),
(11, 'Benylin Expectorant',    'Guaifenesin / Menthol',       6, 'Syrup',      40, FALSE),
(12, 'Betnovate 0.1% Cream',   'Betamethasone Valerate',      2, 'Ointment',   30, FALSE);

-- ============================================================================
-- 4. SEED MEDICINE BATCHES (18 Batches: Healthy, Near-Expiry, and Expired)
-- Uses dynamic date intervals relative to CURRENT_DATE for perpetual validity
-- ============================================================================
INSERT INTO medicine_batches (batch_id, medicine_id, batch_number, manufacturing_date, expiry_date, unit_cost_price, unit_selling_price, initial_quantity, available_quantity, supplier_id) VALUES
-- Amoxicillin (3 batches: FIFO test candidate with earlier and later expiry dates, plus expired batch)
(1,  1, 'AMX-2025-001', DATE_SUB(CURRENT_DATE(), INTERVAL 200 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 60 DAY),   6.50, 12.00, 300, 300, 1),
(2,  1, 'AMX-2025-002', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 240 DAY),  6.50, 12.00, 500, 500, 1),
(3,  1, 'AMX-2024-EXP', DATE_SUB(CURRENT_DATE(), INTERVAL 400 DAY), DATE_SUB(CURRENT_DATE(), INTERVAL 15 DAY),   5.80, 11.50, 100, 45,  1), -- Expired batch!

-- Azithromycin (2 batches: 1 near-expiry within 30 days, 1 fresh batch)
(4,  2, 'AZM-2025-N1',  DATE_SUB(CURRENT_DATE(), INTERVAL 300 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 18 DAY),  14.00, 24.50, 150, 85,  3), -- Near expiry (18 days left)
(5,  2, 'AZM-2026-F1',  DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 420 DAY), 14.50, 25.00, 350, 350, 3),

-- Ciprofloxacin (1 healthy batch)
(6,  3, 'CIP-2025-X1',  DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 300 DAY),  8.00, 16.00, 200, 200, 2),

-- Panadol (2 healthy batches)
(7,  4, 'PCM-2025-A1',  DATE_SUB(CURRENT_DATE(), INTERVAL 150 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 365 DAY),  2.00,  5.00, 600, 600, 5),
(8,  4, 'PCM-2025-A2',  DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 540 DAY),  2.10,  5.25, 800, 800, 5),

-- Advil (2 batches: 1 near expiry within 30 days, 1 healthy)
(9,  5, 'IBU-2025-D1',  DATE_SUB(CURRENT_DATE(), INTERVAL 320 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 22 DAY),   3.50,  7.50, 250, 110, 4), -- Near expiry (22 days left)
(10, 5, 'IBU-2026-D2',  DATE_SUB(CURRENT_DATE(), INTERVAL 45 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 400 DAY),  3.80,  8.00, 400, 400, 4),

-- Controlled Substance: Tramadol (1 healthy batch)
(11, 6, 'TRM-2025-C1',  DATE_SUB(CURRENT_DATE(), INTERVAL 100 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 280 DAY), 12.00, 28.00, 120, 120, 2),

-- Controlled Substance: Morphine Sulfate (1 healthy batch)
(12, 7, 'MOR-2025-M1',  DATE_SUB(CURRENT_DATE(), INTERVAL 80 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 320 DAY), 22.00, 55.00,  80,  80, 1),

-- Atorvastatin (2 batches: 1 near expiry, 1 healthy)
(13, 8, 'ATV-2025-L1',  DATE_SUB(CURRENT_DATE(), INTERVAL 340 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 27 DAY),  10.50, 22.00, 200,  90, 4), -- Near expiry (27 days left)
(14, 8, 'ATV-2026-L2',  DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 450 DAY), 11.00, 23.00, 500, 500, 4),

-- Metformin (1 healthy batch)
(15, 9, 'MET-2025-G1',  DATE_SUB(CURRENT_DATE(), INTERVAL 110 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 360 DAY),  4.20,  9.50, 450, 450, 5),

-- Cetirizine (1 healthy batch)
(16, 10, 'CTZ-2025-Z1', DATE_SUB(CURRENT_DATE(), INTERVAL 95 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 300 DAY),  3.00,  6.50, 300, 300, 3),

-- Benylin Expectorant (1 near expiry batch)
(17, 11, 'CGH-2025-B1', DATE_SUB(CURRENT_DATE(), INTERVAL 280 DAY), DATE_ADD(CURRENT_DATE(), INTERVAL 29 DAY),   5.00, 11.00, 180,  65, 3), -- Near expiry (29 days left)

-- Betnovate Cream (1 healthy batch)
(18, 12, 'BTM-2025-K1', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY),  DATE_ADD(CURRENT_DATE(), INTERVAL 250 DAY),  6.00, 14.00, 150, 150, 2);

-- ============================================================================
-- 5. SEED INITIAL RESTOCK AUDIT LOGS
-- Documents the original receiving audit trail for all 18 batches
-- ============================================================================
INSERT INTO inventory_audit_logs (batch_id, medicine_id, action_type, quantity_changed, remaining_quantity, reason, logged_at)
SELECT 
    batch_id, 
    medicine_id, 
    'RESTOCK', 
    initial_quantity, 
    initial_quantity, 
    CONCAT('Initial inbound batch intake PO receipt #', batch_number),
    DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 45 DAY)
FROM medicine_batches;

-- ============================================================================
-- 6. SEED CUSTOMERS (10 Retail Clients)
-- ============================================================================
INSERT INTO customers (customer_id, customer_name, phone, email, loyalty_points) VALUES
(1,  'Jonathan Miller',    '+1-555-0101', 'j.miller@cloudmail.com',   45),
(2,  'Sophia Martinez',    '+1-555-0102', 'smartinez@healthcare.org', 120),
(3,  'Alexander Chen',     '+1-555-0103', 'achen@techcorp.io',        80),
(4,  'Emily Richardson',   '+1-555-0104', 'emily.rich@domain.net',     15),
(5,  'David K. Williams',  '+1-555-0105', 'dwilliams@service.com',     95),
(6,  'Beatrice Thorne',    '+1-555-0106', 'bthorne@heritage.edu',      30),
(7,  'Tariq Al-Mansoor',   '+1-555-0107', 'tariq.m@globalnet.com',    60),
(8,  'Rachel Green-Geller','+1-555-0108', 'rachel.g@fashionline.com', 200),
(9,  'Lucas Sterling',     '+1-555-0109', 'l.sterling@investments.co', 10),
(10, 'Hannah Montgomery',  '+1-555-0110', 'hmontgomery@library.org',   75);

-- ============================================================================
-- 7. SEED PRESCRIPTIONS (6 Verified, Pending, & Rejected Physician Scripts)
-- ============================================================================
INSERT INTO prescriptions (prescription_id, customer_id, doctor_name, hospital_name, issued_date, verification_status) VALUES
(1, 1, 'Dr. Robert Vance, MD',      'Metro General Hospital',         DATE_SUB(CURRENT_DATE(), INTERVAL 10 DAY), 'Verified'),
(2, 2, 'Dr. Sarah Jenkins, MD',     'Apex Heart & Vascular Institute', DATE_SUB(CURRENT_DATE(), INTERVAL 5 DAY),  'Verified'),
(3, 3, 'Dr. Linda Meyers, MD',      'St. Jude Comprehensive Care',    DATE_SUB(CURRENT_DATE(), INTERVAL 2 DAY),  'Verified'),
(4, 4, 'Dr. Gregory House, MD',     'Princeton Teaching Hospital',     DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY),  'Pending'),
(5, 5, 'Dr. Marcus Welby, MD',      'University Hospital Center',      DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY),  'Verified'),
(6, 6, 'Dr. John Michael Dorian',   'Sacred Heart Medical Center',     DATE_SUB(CURRENT_DATE(), INTERVAL 15 DAY), 'Rejected');

-- ============================================================================
-- 8. SEED PURCHASE ORDERS (Inbound Supplier Orders)
-- ============================================================================
INSERT INTO purchase_orders (po_id, supplier_id, po_number, po_date, total_cost, po_status) VALUES
(1, 1, 'PO-2025-001', DATE_SUB(CURRENT_DATE(), INTERVAL 205 DAY),  5200.00, 'Received'),
(2, 1, 'PO-2025-002', DATE_SUB(CURRENT_DATE(), INTERVAL 95 DAY),   3250.00, 'Received'),
(3, 3, 'PO-2025-003', DATE_SUB(CURRENT_DATE(), INTERVAL 65 DAY),   5075.00, 'Received'),
(4, 4, 'PO-2025-004', DATE_SUB(CURRENT_DATE(), INTERVAL 50 DAY),   6375.00, 'Received'),
(5, 5, 'PO-2025-005', DATE_SUB(CURRENT_DATE(), INTERVAL 65 DAY),   3570.00, 'Received'),
(6, 2, 'PO-2026-006', DATE_SUB(CURRENT_DATE(), INTERVAL 5 DAY),    4200.00, 'Pending');

-- ============================================================================
-- 9. SEED PURCHASE ORDER ITEMS
-- ============================================================================
INSERT INTO purchase_order_items (po_item_id, po_id, medicine_id, batch_number, expiry_date, quantity_received, cost_per_unit) VALUES
(1, 1, 1, 'AMX-2025-001', DATE_ADD(CURRENT_DATE(), INTERVAL 60 DAY),   300,  6.50),
(2, 1, 7, 'MOR-2025-M1',  DATE_ADD(CURRENT_DATE(), INTERVAL 320 DAY),   80, 22.00),
(3, 2, 1, 'AMX-2025-002', DATE_ADD(CURRENT_DATE(), INTERVAL 240 DAY),  500,  6.50),
(4, 3, 2, 'AZM-2026-F1',  DATE_ADD(CURRENT_DATE(), INTERVAL 420 DAY),  350, 14.50),
(5, 4, 5, 'IBU-2026-D2',  DATE_ADD(CURRENT_DATE(), INTERVAL 400 DAY),  400,  3.80),
(6, 4, 8, 'ATV-2026-L2',  DATE_ADD(CURRENT_DATE(), INTERVAL 450 DAY),  500, 11.00),
(7, 5, 4, 'PCM-2025-A2',  DATE_ADD(CURRENT_DATE(), INTERVAL 540 DAY),  800,  2.10),
(8, 5, 9, 'MET-2025-G1',  DATE_ADD(CURRENT_DATE(), INTERVAL 360 DAY),  450,  4.20);

-- ============================================================================
-- 10. SEED HISTORICAL SALES ORDERS & ITEMS
-- Notice: Triggers trg_prevent_expired_batch_sale, trg_validate_controlled_drug_prescription,
-- and trg_deduct_batch_quantity_after_sale will fire automatically, decrementing
-- batch inventory and appending live entries to inventory_audit_logs!
-- ============================================================================

-- Order 1: Jonathan Miller (Rx Order - Amoxicillin Batch 1)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (1, 'INV-2026-0001', 1, 1, 240.00, 0.00, 240.00, 'Card', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 9 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (1, 1, 1, 20, 12.00, 240.00);

-- Order 2: Sophia Martinez (Rx Order - Atorvastatin Batch 13)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (2, 'INV-2026-0002', 2, 2, 220.00, 10.00, 210.00, 'Card', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 5 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (2, 2, 13, 10, 22.00, 220.00);

-- Order 3: Alexander Chen (Controlled Substance Rx Order - Tramadol Batch 11)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (3, 'INV-2026-0003', 3, 3, 280.00, 0.00, 280.00, 'DigitalWallet', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 2 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (3, 3, 11, 10, 28.00, 280.00);

-- Order 4: David K. Williams (Controlled Substance Rx Order - Morphine Batch 12)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (4, 'INV-2026-0004', 5, 5, 275.00, 0.00, 275.00, 'Card', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 7 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (4, 4, 12, 5, 55.00, 275.00);

-- Order 5: Beatrice Thorne (OTC Order - Panadol & Advil)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (5, 'INV-2026-0005', 6, NULL, 65.00, 5.00, 60.00, 'Cash', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 6 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES 
(5, 5, 7, 4, 5.00, 20.00),
(6, 5, 9, 6, 7.50, 45.00);

-- Order 6: Tariq Al-Mansoor (OTC Order - Cetirizine & Cough Expectorant)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (6, 'INV-2026-0006', 7, NULL, 58.50, 0.00, 58.50, 'DigitalWallet', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 4 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES 
(7, 6, 16, 4, 6.50, 26.00),
(8, 6, 17, 3, 11.00, 33.00);

-- Order 7: Rachel Green-Geller (OTC Order - Betnovate & Panadol)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (7, 'INV-2026-0007', 8, NULL, 58.00, 0.00, 58.00, 'Card', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 3 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES 
(9,  7, 18, 2, 14.00, 28.00),
(10, 7, 7,  6,  5.00, 30.00);

-- Order 8: Lucas Sterling (OTC Order - Advil)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (8, 'INV-2026-0008', 9, NULL, 64.00, 0.00, 64.00, 'Cash', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 2 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (11, 8, 10, 8, 8.00, 64.00);

-- Order 9: Hannah Montgomery (OTC Order - Panadol & Advil)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (9, 'INV-2026-0009', 10, NULL, 62.50, 0.00, 62.50, 'Card', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES 
(12, 9, 8,  5, 5.25, 26.25),
(13, 9, 10, 4, 8.00, 32.00);

-- Order 10: Jonathan Miller (Repeat OTC purchase)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (10, 'INV-2026-0010', 1, NULL, 45.00, 0.00, 45.00, 'Cash', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (14, 10, 7, 9, 5.00, 45.00);

-- Order 11: Sophia Martinez (OTC purchase)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (11, 'INV-2026-0011', 2, NULL, 39.00, 0.00, 39.00, 'Cash', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 12 HOUR));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (15, 11, 16, 6, 6.50, 39.00);

-- Order 12: Alexander Chen (Rx Order - Azithromycin Batch 4)
INSERT INTO sales_orders (order_id, invoice_number, customer_id, prescription_id, total_amount, discount_amount, final_payable, payment_method, order_timestamp)
VALUES (12, 'INV-2026-0012', 3, 3, 147.00, 0.00, 147.00, 'Card', DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 4 HOUR));
INSERT INTO sales_order_items (item_id, order_id, batch_id, quantity, unit_price, subtotal)
VALUES (16, 12, 4, 6, 24.50, 147.00);
