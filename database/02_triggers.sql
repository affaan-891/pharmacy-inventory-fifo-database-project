-- ============================================================================
-- PHARMACY EXPIRY & BATCH-WISE FIFO INVENTORY SYSTEM
-- Automated Business Integrity & Safety Triggers
-- Target Engine: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Storage Engine)
-- Script: 02_triggers.sql
-- ============================================================================

USE pharmacy_inventory_db;

-- Drop existing triggers to ensure idempotent execution
DROP TRIGGER IF EXISTS trg_validate_prescription_on_order;
DROP TRIGGER IF EXISTS trg_prevent_expired_batch_sale;
DROP TRIGGER IF EXISTS trg_validate_controlled_drug_prescription;
DROP TRIGGER IF EXISTS trg_deduct_batch_quantity_after_sale;

DELIMITER //

-- ============================================================================
-- TRIGGER 1: trg_validate_prescription_on_order
-- Event: BEFORE INSERT ON sales_orders
-- Purpose: Validates that if an order references a prescription, the prescription
--          must exist, belong to the same customer, and be in 'Verified' status.
-- ============================================================================
CREATE TRIGGER trg_validate_prescription_on_order
BEFORE INSERT ON sales_orders
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_presc_cust_id INT;

    IF NEW.prescription_id IS NOT NULL THEN
        SELECT verification_status, customer_id 
        INTO v_status, v_presc_cust_id
        FROM prescriptions
        WHERE prescription_id = NEW.prescription_id;

        -- Check if prescription was found
        IF v_status IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Prescription Error: Referenced prescription does not exist.';
        END IF;

        -- Verify customer ownership of prescription
        IF v_presc_cust_id <> NEW.customer_id THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Compliance Violation: Prescription customer does not match sales order customer.';
        END IF;

        -- Ensure verification status is 'Verified'
        IF v_status <> 'Verified' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Compliance Violation: Prescription must have Verified status before dispensing.';
        END IF;
    END IF;
END //

-- ============================================================================
-- TRIGGER 2: trg_prevent_expired_batch_sale
-- Event: BEFORE INSERT ON sales_order_items
-- Purpose: Strictly prohibits dispensing any batch where expiry_date <= CURRENT_DATE().
--          Also validates available stock levels prior to order placement.
-- ============================================================================
CREATE TRIGGER trg_prevent_expired_batch_sale
BEFORE INSERT ON sales_order_items
FOR EACH ROW
BEGIN
    DECLARE v_expiry_date DATE;
    DECLARE v_avail_qty INT;
    DECLARE v_batch_num VARCHAR(50);
    DECLARE v_medicine_name VARCHAR(150);

    -- Retrieve batch details and expiration date
    SELECT b.expiry_date, b.available_quantity, b.batch_number, m.brand_name
    INTO v_expiry_date, v_avail_qty, v_batch_num, v_medicine_name
    FROM medicine_batches b
    INNER JOIN medicines m ON b.medicine_id = m.medicine_id
    WHERE b.batch_id = NEW.batch_id;

    -- Strict expiration check against CURRENT_DATE
    IF v_expiry_date <= CURRENT_DATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Compliance Violation: Expired medicine batch cannot be dispensed.';
    END IF;

    -- Insufficient stock validation
    IF NEW.quantity > v_avail_qty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory Violation: Requested quantity exceeds available batch inventory.';
    END IF;
END //

-- ============================================================================
-- TRIGGER 3: trg_validate_controlled_drug_prescription
-- Event: BEFORE INSERT ON sales_order_items
-- Purpose: Enforces regulatory compliance (FDA/DEA Schedule II-V). If the medicine
--          is a controlled substance or category requires prescription, the parent
--          sales order MUST have a verified prescription attached.
-- ============================================================================
CREATE TRIGGER trg_validate_controlled_drug_prescription
BEFORE INSERT ON sales_order_items
FOR EACH ROW
BEGIN
    DECLARE v_is_controlled BOOLEAN;
    DECLARE v_category_requires_rx BOOLEAN;
    DECLARE v_order_prescription_id INT;
    DECLARE v_brand_name VARCHAR(150);

    -- Query medicine regulation flags and parent order prescription
    SELECT m.is_controlled_substance, c.requires_prescription, m.brand_name, o.prescription_id
    INTO v_is_controlled, v_category_requires_rx, v_brand_name, v_order_prescription_id
    FROM medicine_batches b
    INNER JOIN medicines m ON b.medicine_id = m.medicine_id
    INNER JOIN categories c ON m.category_id = c.category_id
    INNER JOIN sales_orders o ON o.order_id = NEW.order_id
    WHERE b.batch_id = NEW.batch_id;

    -- Abort if controlled substance or Rx-required drug is sold without verified prescription
    IF (v_is_controlled = TRUE OR v_category_requires_rx = TRUE) AND v_order_prescription_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Compliance Violation: Controlled substance or Rx medicine requires a verified prescription on file.';
    END IF;
END //

-- ============================================================================
-- TRIGGER 4: trg_deduct_batch_quantity_after_sale
-- Event: AFTER INSERT ON sales_order_items
-- Purpose: Decrements available_quantity in medicine_batches and writes an
--          immutable entry to inventory_audit_logs for audit trails.
-- ============================================================================
CREATE TRIGGER trg_deduct_batch_quantity_after_sale
AFTER INSERT ON sales_order_items
FOR EACH ROW
BEGIN
    DECLARE v_remaining INT;
    DECLARE v_med_id INT;

    -- Decrement inventory from the specific batch
    UPDATE medicine_batches
    SET available_quantity = available_quantity - NEW.quantity
    WHERE batch_id = NEW.batch_id;

    -- Fetch current remaining quantity and medicine ID
    SELECT available_quantity, medicine_id
    INTO v_remaining, v_med_id
    FROM medicine_batches
    WHERE batch_id = NEW.batch_id;

    -- Write immutable audit ledger entry
    INSERT INTO inventory_audit_logs (
        batch_id,
        medicine_id,
        action_type,
        quantity_changed,
        remaining_quantity,
        reason,
        logged_at
    ) VALUES (
        NEW.batch_id,
        v_med_id,
        'SALE',
        -NEW.quantity,
        v_remaining,
        CONCAT('Dispensed in Sales Order #', NEW.order_id, ' (Item ID: ', NEW.item_id, ')'),
        CURRENT_TIMESTAMP
    );
END //

DELIMITER ;
