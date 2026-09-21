-- ============================================================================
-- PHARMACY EXPIRY & BATCH-WISE FIFO INVENTORY SYSTEM
-- Database Definition & 3NF Normalized Relational Schema
-- Target Engine: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Storage Engine)
-- Script: 01_schema.sql
-- ============================================================================

-- Create database with full multilingual UTF-8 support
CREATE DATABASE IF NOT EXISTS pharmacy_inventory_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE pharmacy_inventory_db;

-- ----------------------------------------------------------------------------
-- Drop existing tables in reverse dependency order to prevent FK errors
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS inventory_audit_logs;
DROP TABLE IF EXISTS purchase_order_items;
DROP TABLE IF EXISTS purchase_orders;
DROP TABLE IF EXISTS sales_order_items;
DROP TABLE IF EXISTS sales_orders;
DROP TABLE IF EXISTS prescriptions;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS medicine_batches;
DROP TABLE IF EXISTS medicines;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS suppliers;

-- ============================================================================
-- TABLE 1: suppliers
-- Stores verified pharmaceutical manufacturers and authorized distributors
-- ============================================================================
CREATE TABLE suppliers (
    supplier_id INT AUTO_INCREMENT PRIMARY KEY,
    company_name VARCHAR(150) NOT NULL,
    contact_person VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(25) NOT NULL UNIQUE,
    address TEXT NOT NULL,
    rating DECIMAL(2,1) NOT NULL DEFAULT 5.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_supplier_rating CHECK (rating >= 1.0 AND rating <= 5.0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 2: categories
-- Therapeutic & pharmacological classifications of pharmaceutical items
-- ============================================================================
CREATE TABLE categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    requires_prescription BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 3: medicines
-- Master drug formulary catalog (Entity-level definition)
-- ============================================================================
CREATE TABLE medicines (
    medicine_id INT AUTO_INCREMENT PRIMARY KEY,
    brand_name VARCHAR(150) NOT NULL,
    generic_name VARCHAR(150) NOT NULL,
    category_id INT NOT NULL,
    dosage_form ENUM('Tablet', 'Syrup', 'Injection', 'Capsule', 'Ointment') NOT NULL,
    reorder_level INT NOT NULL DEFAULT 50,
    is_controlled_substance BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_medicine_reorder CHECK (reorder_level >= 0),
    CONSTRAINT fk_medicines_category FOREIGN KEY (category_id)
        REFERENCES categories(category_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX idx_medicines_brand (brand_name),
    INDEX idx_medicines_generic (generic_name),
    INDEX idx_medicines_category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 4: medicine_batches
-- Concrete stock entities tracked per production batch & expiration date
-- Core foundation of the FIFO (First-In, First-Expired, First-Out) tracking
-- ============================================================================
CREATE TABLE medicine_batches (
    batch_id INT AUTO_INCREMENT PRIMARY KEY,
    medicine_id INT NOT NULL,
    batch_number VARCHAR(50) NOT NULL,
    manufacturing_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    unit_cost_price DECIMAL(10,2) NOT NULL,
    unit_selling_price DECIMAL(10,2) NOT NULL,
    initial_quantity INT NOT NULL,
    available_quantity INT NOT NULL,
    supplier_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_medicine_batch UNIQUE (medicine_id, batch_number),
    CONSTRAINT chk_batch_prices CHECK (unit_selling_price >= unit_cost_price AND unit_cost_price >= 0),
    CONSTRAINT chk_batch_initial_qty CHECK (initial_quantity > 0),
    CONSTRAINT chk_batch_avail_qty CHECK (available_quantity >= 0 AND available_quantity <= initial_quantity),
    CONSTRAINT chk_batch_dates CHECK (expiry_date > manufacturing_date),
    CONSTRAINT fk_batches_medicine FOREIGN KEY (medicine_id)
        REFERENCES medicines(medicine_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_batches_supplier FOREIGN KEY (supplier_id)
        REFERENCES suppliers(supplier_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    -- Composite index optimized for FIFO cursor traversal
    INDEX idx_fifo_lookup (medicine_id, expiry_date, available_quantity),
    INDEX idx_batches_expiry (expiry_date),
    INDEX idx_batches_supplier (supplier_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 5: customers
-- Retail clients, patient profiles, and loyalty accounting
-- ============================================================================
CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    phone VARCHAR(25) NOT NULL UNIQUE,
    email VARCHAR(100) NULL,
    loyalty_points INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_customer_loyalty CHECK (loyalty_points >= 0),
    INDEX idx_customers_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 6: prescriptions
-- Medical authorization records for Rx and Schedule-controlled medications
-- ============================================================================
CREATE TABLE prescriptions (
    prescription_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    doctor_name VARCHAR(100) NOT NULL,
    hospital_name VARCHAR(150) NOT NULL,
    issued_date DATE NOT NULL,
    verification_status ENUM('Verified', 'Pending', 'Rejected') NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_prescriptions_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX idx_prescriptions_lookup (customer_id, verification_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 7: sales_orders
-- Transaction header representing a retail counter sales invoice
-- ============================================================================
CREATE TABLE sales_orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_number VARCHAR(50) NOT NULL UNIQUE,
    customer_id INT NOT NULL,
    prescription_id INT NULL,
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    final_payable DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    payment_method ENUM('Cash', 'Card', 'DigitalWallet') NOT NULL DEFAULT 'Cash',
    order_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_sales_amounts CHECK (total_amount >= 0 AND discount_amount >= 0 AND final_payable >= 0),
    CONSTRAINT fk_sales_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_sales_prescription FOREIGN KEY (prescription_id)
        REFERENCES prescriptions(prescription_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX idx_sales_customer (customer_id),
    INDEX idx_sales_timestamp (order_timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 8: sales_order_items
-- Granular sales line items explicitly binding an invoice to exact batches
-- Enables granular lot tracking for recalls and FIFO audits
-- ============================================================================
CREATE TABLE sales_order_items (
    item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    batch_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_order_item_qty CHECK (quantity > 0),
    CONSTRAINT chk_order_item_prices CHECK (unit_price >= 0 AND subtotal >= 0),
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id)
        REFERENCES sales_orders(order_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_order_items_batch FOREIGN KEY (batch_id)
        REFERENCES medicine_batches(batch_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX idx_order_items_order (order_id),
    INDEX idx_order_items_batch (batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 9: purchase_orders
-- Inbound procurement orders raised to pharmaceutical suppliers
-- ============================================================================
CREATE TABLE purchase_orders (
    po_id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT NOT NULL,
    po_number VARCHAR(50) NOT NULL UNIQUE,
    po_date DATE NOT NULL,
    total_cost DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    po_status ENUM('Pending', 'Received', 'Cancelled') NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_po_cost CHECK (total_cost >= 0),
    CONSTRAINT fk_po_supplier FOREIGN KEY (supplier_id)
        REFERENCES suppliers(supplier_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX idx_po_supplier (supplier_id),
    INDEX idx_po_status (po_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 10: purchase_order_items
-- Inward shipment receiving manifests documenting new batches
-- ============================================================================
CREATE TABLE purchase_order_items (
    po_item_id INT AUTO_INCREMENT PRIMARY KEY,
    po_id INT NOT NULL,
    medicine_id INT NOT NULL,
    batch_number VARCHAR(50) NOT NULL,
    expiry_date DATE NOT NULL,
    quantity_received INT NOT NULL,
    cost_per_unit DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_po_item_qty CHECK (quantity_received > 0),
    CONSTRAINT chk_po_cost_per_unit CHECK (cost_per_unit >= 0),
    CONSTRAINT fk_po_items_po FOREIGN KEY (po_id)
        REFERENCES purchase_orders(po_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_po_items_medicine FOREIGN KEY (medicine_id)
        REFERENCES medicines(medicine_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX idx_po_items_po (po_id),
    INDEX idx_po_items_medicine (medicine_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 11: inventory_audit_logs
-- Immutable tamper-evident audit ledger recording every inventory modification
-- Essential for regulatory compliance, DEA/FDA audits, and inventory reconciliation
-- ============================================================================
CREATE TABLE inventory_audit_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    batch_id INT NOT NULL,
    medicine_id INT NOT NULL,
    action_type ENUM('SALE', 'RETURN', 'RESTOCK', 'EXPIRED_SCRAP', 'MANUAL_ADJUSTMENT') NOT NULL,
    quantity_changed INT NOT NULL,
    remaining_quantity INT NOT NULL,
    reason VARCHAR(255) NOT NULL,
    logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_audit_remaining CHECK (remaining_quantity >= 0),
    INDEX idx_audit_batch (batch_id),
    INDEX idx_audit_medicine (medicine_id),
    INDEX idx_audit_action (action_type),
    INDEX idx_audit_timestamp (logged_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
