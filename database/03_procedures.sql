-- ============================================================================
-- PHARMACY EXPIRY & BATCH-WISE FIFO INVENTORY SYSTEM
-- Stored Procedures & User-Defined Functions (ACID & FIFO Logic)
-- Target Engine: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Storage Engine)
-- Script: 03_procedures.sql
-- ============================================================================

USE pharmacy_inventory_db;

-- Drop existing routines to guarantee clean rebuild
DROP PROCEDURE IF EXISTS sp_dispense_medicine_fifo;
DROP PROCEDURE IF EXISTS sp_generate_monthly_supplier_statement;
DROP FUNCTION IF EXISTS fn_calculate_batch_gross_margin;

DELIMITER //

-- ============================================================================
-- FUNCTION: fn_calculate_batch_gross_margin
-- Purpose: Computes the gross profit margin percentage for a specific batch.
-- Formula: ((Selling Price - Cost Price) / Selling Price) * 100
-- Attributes: DETERMINISTIC, READS SQL DATA
-- ============================================================================
CREATE FUNCTION fn_calculate_batch_gross_margin(p_batch_id INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_cost DECIMAL(10,2);
    DECLARE v_selling DECIMAL(10,2);
    DECLARE v_margin DECIMAL(5,2);

    -- Retrieve batch cost and selling prices
    SELECT unit_cost_price, unit_selling_price
    INTO v_cost, v_selling
    FROM medicine_batches
    WHERE batch_id = p_batch_id;

    -- Protect against division by zero or invalid batch
    IF v_selling IS NULL OR v_selling <= 0.00 THEN
        RETURN 0.00;
    END IF;

    SET v_margin = ROUND(((v_selling - v_cost) / v_selling) * 100, 2);
    RETURN v_margin;
END //

-- ============================================================================
-- PROCEDURE: sp_dispense_medicine_fifo
-- Purpose: Atomically dispenses a medicine following First-In, First-Expired,
--          First-Out (FIFO) principles.
--          - Evaluates stock availability across non-expired batches.
--          - Applies pessimistic row-locking (FOR UPDATE) to prevent race conditions.
--          - Iteratively splits requested quantities across multiple batches.
--          - Enforces ACID transactional integrity (START TRANSACTION / COMMIT / ROLLBACK).
-- Parameters:
--   IN  p_customer_id     INT          -> Buying customer ID
--   IN  p_medicine_id     INT          -> Medicine to dispense
--   IN  p_requested_qty   INT          -> Total units requested
--   IN  p_prescription_id INT          -> Optional prescription reference (NULL for OTC)
--   OUT p_order_id        INT          -> Generated sales order ID
-- ============================================================================
CREATE PROCEDURE sp_dispense_medicine_fifo(
    IN  p_customer_id     INT,
    IN  p_medicine_id     INT,
    IN  p_requested_qty   INT,
    IN  p_prescription_id INT,
    OUT p_order_id        INT
)
proc_label: BEGIN
    -- Variable declarations
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_batch_id INT;
    DECLARE v_batch_avail INT;
    DECLARE v_unit_price DECIMAL(10,2);
    DECLARE v_remaining_qty INT;
    DECLARE v_deduct_qty INT;
    DECLARE v_subtotal DECIMAL(10,2);
    DECLARE v_order_total DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_invoice_num VARCHAR(50);
    DECLARE v_total_avail_stock INT DEFAULT 0;
    DECLARE v_is_controlled BOOLEAN DEFAULT FALSE;
    DECLARE v_req_rx BOOLEAN DEFAULT FALSE;
    DECLARE v_med_name VARCHAR(150);

    -- FIFO Cursor: Ordered strictly by earliest expiry_date ASC, then batch_id ASC
    -- Uses pessimistic row locking (FOR UPDATE)
    DECLARE cur_fifo_batches CURSOR FOR
        SELECT batch_id, available_quantity, unit_selling_price
        FROM medicine_batches
        WHERE medicine_id = p_medicine_id
          AND expiry_date > CURRENT_DATE()
          AND available_quantity > 0
        ORDER BY expiry_date ASC, batch_id ASC
        FOR UPDATE;

    -- Handlers
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Rollback entire transaction on any failure
        ROLLBACK;
        RESIGNAL;
    END;

    -- Validation 1: Requested quantity must be positive
    IF p_requested_qty <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Input Error: Requested quantity must be greater than zero.';
    END IF;

    -- Validation 2: Customer existence check
    IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = p_customer_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Validation Error: Customer record not found.';
    END IF;

    -- Validation 3: Medicine regulation check (Rx / Controlled substance compliance)
    SELECT m.is_controlled_substance, c.requires_prescription, m.brand_name
    INTO v_is_controlled, v_req_rx, v_med_name
    FROM medicines m
    INNER JOIN categories c ON m.category_id = c.category_id
    WHERE m.medicine_id = p_medicine_id;

    IF v_med_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Validation Error: Medicine not found in formulary.';
    END IF;

    IF (v_is_controlled = TRUE OR v_req_rx = TRUE) AND p_prescription_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Compliance Error: Prescription is strictly mandatory for controlled or Rx medicines.';
    END IF;

    -- Begin ACID Transaction
    START TRANSACTION;

    -- Validation 4: Aggregate non-expired available inventory check
    SELECT COALESCE(SUM(available_quantity), 0)
    INTO v_total_avail_stock
    FROM medicine_batches
    WHERE medicine_id = p_medicine_id
      AND expiry_date > CURRENT_DATE()
      AND available_quantity > 0;

    IF v_total_avail_stock < p_requested_qty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory Error: Insufficient non-expired stock to satisfy requested quantity.';
    END IF;

    -- Generate unique invoice number with microsecond timestamp
    SET v_invoice_num = CONCAT('INV-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), '-', LPAD(FLOOR(RAND() * 999), 3, '0'));

    -- Create Sales Order Header record
    INSERT INTO sales_orders (
        invoice_number,
        customer_id,
        prescription_id,
        total_amount,
        discount_amount,
        final_payable,
        payment_method,
        order_timestamp
    ) VALUES (
        v_invoice_num,
        p_customer_id,
        p_prescription_id,
        0.00,
        0.00,
        0.00,
        'Cash',
        CURRENT_TIMESTAMP
    );

    SET p_order_id = LAST_INSERT_ID();
    SET v_remaining_qty = p_requested_qty;

    -- Open FIFO cursor to allocate inventory across batches
    OPEN cur_fifo_batches;

    fifo_loop: LOOP
        FETCH cur_fifo_batches INTO v_batch_id, v_batch_avail, v_unit_price;

        IF v_done OR v_remaining_qty <= 0 THEN
            LEAVE fifo_loop;
        END IF;

        -- Determine how much quantity to draw from current batch
        IF v_batch_avail >= v_remaining_qty THEN
            SET v_deduct_qty = v_remaining_qty;
        ELSE
            SET v_deduct_qty = v_batch_avail;
        END IF;

        SET v_subtotal = ROUND(v_deduct_qty * v_unit_price, 2);
        SET v_order_total = v_order_total + v_subtotal;

        -- Insert line item (Fires trg_prevent_expired_batch_sale & trg_deduct_batch_quantity_after_sale)
        INSERT INTO sales_order_items (
            order_id,
            batch_id,
            quantity,
            unit_price,
            subtotal
        ) VALUES (
            p_order_id,
            v_batch_id,
            v_deduct_qty,
            v_unit_price,
            v_subtotal
        );

        -- Decrement tracking loop counter
        SET v_remaining_qty = v_remaining_qty - v_deduct_qty;
    END LOOP;

    CLOSE cur_fifo_batches;

    -- Safety check: Ensure entire quantity was successfully distributed
    IF v_remaining_qty > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory Concurrency Error: Could not completely fulfill request from batches.';
    END IF;

    -- Update final sales order summary amounts
    UPDATE sales_orders
    SET total_amount = v_order_total,
        final_payable = v_order_total
    WHERE order_id = p_order_id;

    -- Award loyalty points (1 point per $10 spent)
    UPDATE customers
    SET loyalty_points = loyalty_points + FLOOR(v_order_total / 10)
    WHERE customer_id = p_customer_id;

    -- Commit transaction
    COMMIT;
END //

-- ============================================================================
-- PROCEDURE: sp_generate_monthly_supplier_statement
-- Purpose: Generates a procurement audit summary statement for a supplier over
--          a specified calendar month and year.
-- Parameters:
--   IN p_supplier_id INT -> Targeted supplier ID
--   IN p_year        INT -> Four-digit year (e.g., 2026)
--   IN p_month       INT -> Calendar month (1-12)
-- ============================================================================
CREATE PROCEDURE sp_generate_monthly_supplier_statement(
    IN p_supplier_id INT,
    IN p_year        INT,
    IN p_month       INT
)
BEGIN
    -- Statement Header: Supplier details
    SELECT 
        supplier_id,
        company_name,
        contact_person,
        email,
        phone,
        rating,
        p_year AS report_year,
        p_month AS report_month
    FROM suppliers
    WHERE supplier_id = p_supplier_id;

    -- Statement Summary: Aggregated procurement volumes & financials
    SELECT 
        COUNT(DISTINCT po.po_id) AS total_orders_placed,
        SUM(CASE WHEN po.po_status = 'Received' THEN 1 ELSE 0 END) AS orders_received,
        SUM(CASE WHEN po.po_status = 'Pending' THEN 1 ELSE 0 END) AS orders_pending,
        SUM(CASE WHEN po.po_status = 'Cancelled' THEN 1 ELSE 0 END) AS orders_cancelled,
        COALESCE(SUM(po.total_cost), 0.00) AS total_order_value,
        COALESCE(SUM(CASE WHEN po.po_status = 'Received' THEN po.total_cost ELSE 0.00 END), 0.00) AS total_received_value,
        COALESCE(SUM(poi.quantity_received), 0) AS total_units_procured
    FROM purchase_orders po
    LEFT JOIN purchase_order_items poi ON po.po_id = poi.po_id
    WHERE po.supplier_id = p_supplier_id
      AND YEAR(po.po_date) = p_year
      AND MONTH(po.po_date) = p_month;

    -- Line Item Breakdown: Detailed PO registry for the billing period
    SELECT 
        po.po_id,
        po.po_number,
        po.po_date,
        po.po_status,
        po.total_cost,
        COUNT(poi.po_item_id) AS line_item_count
    FROM purchase_orders po
    LEFT JOIN purchase_order_items poi ON po.po_id = poi.po_id
    WHERE po.supplier_id = p_supplier_id
      AND YEAR(po.po_date) = p_year
      AND MONTH(po.po_date) = p_month
    GROUP BY po.po_id, po.po_number, po.po_date, po.po_status, po.total_cost
    ORDER BY po.po_date DESC;
END //

DELIMITER ;
