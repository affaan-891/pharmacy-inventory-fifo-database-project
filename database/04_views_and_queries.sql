-- ============================================================================
-- PHARMACY EXPIRY & BATCH-WISE FIFO INVENTORY SYSTEM
-- Analytical Views & Complex Viva-Ready Analytical Queries
-- Target Engine: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Storage Engine)
-- Script: 04_views_and_queries.sql
-- ============================================================================

USE pharmacy_inventory_db;

-- ----------------------------------------------------------------------------
-- Drop existing views to allow clean re-creation
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_expiring_batches_30_days;
DROP VIEW IF EXISTS vw_medicine_inventory_health;

-- ============================================================================
-- VIEW 1: vw_expiring_batches_30_days
-- Purpose: Identifies high-risk batches expiring within the next 30 days.
--          Provides stock count, supplier contact info for returns/credit memos,
--          and calculates potential financial losses.
-- ============================================================================
CREATE VIEW vw_expiring_batches_30_days AS
SELECT 
    b.batch_id,
    m.medicine_id,
    m.brand_name,
    m.generic_name,
    c.category_name,
    m.dosage_form,
    b.batch_number,
    b.expiry_date,
    DATEDIFF(b.expiry_date, CURRENT_DATE()) AS days_until_expiry,
    b.available_quantity,
    b.unit_cost_price,
    b.unit_selling_price,
    ROUND(b.available_quantity * b.unit_cost_price, 2) AS potential_financial_loss,
    s.company_name AS supplier_name,
    s.contact_person AS supplier_contact,
    s.phone AS supplier_phone,
    s.email AS supplier_email
FROM medicine_batches b
INNER JOIN medicines m ON b.medicine_id = m.medicine_id
INNER JOIN categories c ON m.category_id = c.category_id
INNER JOIN suppliers s ON b.supplier_id = s.supplier_id
WHERE b.expiry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)
  AND b.available_quantity > 0;

-- ============================================================================
-- VIEW 2: vw_medicine_inventory_health
-- Purpose: Real-time inventory valuation and replenishment status dashboard.
--          Aggregates stock across active batches and classifies health into:
--          - 'OUT OF STOCK' (0 units)
--          - 'REORDER NEEDED' (<= reorder_level)
--          - 'OPTIMAL' (> reorder_level)
-- ============================================================================
CREATE VIEW vw_medicine_inventory_health AS
SELECT 
    m.medicine_id,
    m.brand_name,
    m.generic_name,
    c.category_name,
    m.dosage_form,
    m.reorder_level,
    COALESCE(SUM(CASE WHEN b.expiry_date > CURRENT_DATE() THEN b.available_quantity ELSE 0 END), 0) AS total_usable_stock,
    COUNT(DISTINCT CASE WHEN b.expiry_date > CURRENT_DATE() AND b.available_quantity > 0 THEN b.batch_id END) AS active_batch_count,
    COALESCE(ROUND(SUM(CASE WHEN b.expiry_date > CURRENT_DATE() THEN b.available_quantity * b.unit_cost_price ELSE 0 END), 2), 0.00) AS total_inventory_cost_value,
    COALESCE(ROUND(SUM(CASE WHEN b.expiry_date > CURRENT_DATE() THEN b.available_quantity * b.unit_selling_price ELSE 0 END), 2), 0.00) AS total_potential_retail_value,
    CASE 
        WHEN COALESCE(SUM(CASE WHEN b.expiry_date > CURRENT_DATE() THEN b.available_quantity ELSE 0 END), 0) = 0 THEN 'OUT OF STOCK'
        WHEN COALESCE(SUM(CASE WHEN b.expiry_date > CURRENT_DATE() THEN b.available_quantity ELSE 0 END), 0) <= m.reorder_level THEN 'REORDER NEEDED'
        ELSE 'OPTIMAL'
    END AS inventory_health_status
FROM medicines m
INNER JOIN categories c ON m.category_id = c.category_id
LEFT JOIN medicine_batches b ON m.medicine_id = b.medicine_id
GROUP BY m.medicine_id, m.brand_name, m.generic_name, c.category_name, m.dosage_form, m.reorder_level;

-- ============================================================================
-- VIVA-READY COMPLEX ANALYTICAL QUERIES
-- The following 5 queries illustrate advanced SQL capabilities for technical evaluations.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- QUERY 1: Multi-Table JOIN with GROUP BY & HAVING Filter
-- Concept: Combines INNER JOIN and LEFT JOIN to evaluate sales volume per medicine.
-- Filter: Isolates oral formulations ('Tablet', 'Capsule') generating cumulative
--         revenue >= $50.00, demonstrating post-aggregation filtering via HAVING.
-- ----------------------------------------------------------------------------
SELECT 
    m.medicine_id,
    m.brand_name,
    m.generic_name,
    m.dosage_form,
    c.category_name,
    COUNT(DISTINCT soi.order_id) AS total_orders_involved,
    COALESCE(SUM(soi.quantity), 0) AS units_dispensed,
    COALESCE(SUM(soi.subtotal), 0.00) AS total_revenue_generated
FROM medicines m
INNER JOIN categories c ON m.category_id = c.category_id
LEFT JOIN medicine_batches mb ON m.medicine_id = mb.medicine_id
LEFT JOIN sales_order_items soi ON mb.batch_id = soi.batch_id
WHERE m.dosage_form IN ('Tablet', 'Capsule')
GROUP BY m.medicine_id, m.brand_name, m.generic_name, m.dosage_form, c.category_name
HAVING total_revenue_generated >= 50.00
ORDER BY total_revenue_generated DESC;

-- ----------------------------------------------------------------------------
-- QUERY 2: Anti-Join using NOT EXISTS
-- Concept: Formulates an anti-join to detect formulary medicines with zero active,
--          non-expired stock available. Prevents dead listings in pharmacy dispensing.
-- ----------------------------------------------------------------------------
SELECT 
    m.medicine_id,
    m.brand_name,
    m.generic_name,
    c.category_name,
    m.reorder_level,
    'CRITICAL: NO ACTIVE BATCHES' AS stock_alert
FROM medicines m
INNER JOIN categories c ON m.category_id = c.category_id
WHERE NOT EXISTS (
    SELECT 1 
    FROM medicine_batches mb
    WHERE mb.medicine_id = m.medicine_id
      AND mb.expiry_date > CURRENT_DATE()
      AND mb.available_quantity > 0
)
ORDER BY m.brand_name ASC;

-- ----------------------------------------------------------------------------
-- QUERY 3: Correlated Subquery
-- Concept: Identifies individual batches whose selling price is significantly higher
--          than the average selling price of all active medicines in that category.
-- ----------------------------------------------------------------------------
SELECT 
    mb.batch_id,
    mb.batch_number,
    m.brand_name,
    c.category_name,
    mb.unit_selling_price,
    ROUND((
        SELECT AVG(mb2.unit_selling_price)
        FROM medicine_batches mb2
        INNER JOIN medicines m2 ON mb2.medicine_id = m2.medicine_id
        WHERE m2.category_id = m.category_id
    ), 2) AS category_avg_price,
    ROUND(mb.unit_selling_price - (
        SELECT AVG(mb2.unit_selling_price)
        FROM medicine_batches mb2
        INNER JOIN medicines m2 ON mb2.medicine_id = m2.medicine_id
        WHERE m2.category_id = m.category_id
    ), 2) AS premium_above_average
FROM medicine_batches mb
INNER JOIN medicines m ON mb.medicine_id = m.medicine_id
INNER JOIN categories c ON m.category_id = c.category_id
WHERE mb.unit_selling_price > (
    SELECT AVG(mb2.unit_selling_price)
    FROM medicine_batches mb2
    INNER JOIN medicines m2 ON mb2.medicine_id = m2.medicine_id
    WHERE m2.category_id = m.category_id
)
ORDER BY premium_above_average DESC;

-- ----------------------------------------------------------------------------
-- QUERY 4: Window Function DENSE_RANK() with CTE
-- Concept: Ranks medicines within each therapeutic category based on total units sold.
--          Unlike RANK(), DENSE_RANK() does not skip rank positions upon ties.
-- ----------------------------------------------------------------------------
WITH medicine_sales_summary AS (
    SELECT 
        c.category_name,
        m.medicine_id,
        m.brand_name,
        COALESCE(SUM(soi.quantity), 0) AS total_units_sold,
        COALESCE(SUM(soi.subtotal), 0.00) AS total_sales_volume
    FROM categories c
    INNER JOIN medicines m ON c.category_id = m.category_id
    LEFT JOIN medicine_batches mb ON m.medicine_id = mb.medicine_id
    LEFT JOIN sales_order_items soi ON mb.batch_id = soi.batch_id
    GROUP BY c.category_name, m.medicine_id, m.brand_name
)
SELECT 
    category_name,
    brand_name,
    total_units_sold,
    total_sales_volume,
    DENSE_RANK() OVER (
        PARTITION BY category_name 
        ORDER BY total_units_sold DESC, total_sales_volume DESC
    ) AS category_sales_rank
FROM medicine_sales_summary
ORDER BY category_name ASC, category_sales_rank ASC;

-- ----------------------------------------------------------------------------
-- QUERY 5: Query Execution Plan (EXPLAIN / EXPLAIN ANALYZE) for FIFO Index Optimization
-- Concept: Analyzes how the storage engine utilizes composite index idx_fifo_lookup 
--          (medicine_id, expiry_date, available_quantity) to fetch the earliest
--          expiring batch without full-table scanning or expensive filesort.
-- Note: MySQL 8.0+ supports `EXPLAIN ANALYZE`. MariaDB/Universal supports `EXPLAIN` or `ANALYZE`.
-- ----------------------------------------------------------------------------
EXPLAIN
SELECT batch_id, batch_number, expiry_date, available_quantity, unit_selling_price
FROM medicine_batches
WHERE medicine_id = 1
  AND expiry_date > CURRENT_DATE()
  AND available_quantity > 0
ORDER BY expiry_date ASC, batch_id ASC
LIMIT 1;

-- For MySQL 8.0+ interactive terminals, execute:
-- EXPLAIN ANALYZE SELECT batch_id, batch_number, expiry_date, available_quantity, unit_selling_price FROM medicine_batches WHERE medicine_id = 1 AND expiry_date > CURRENT_DATE() AND available_quantity > 0 ORDER BY expiry_date ASC, batch_id ASC LIMIT 1;

