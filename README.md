# Pharmacy Expiry & Batch-Wise FIFO Inventory Database System

[![MySQL 8.0+](https://img.shields.io/badge/MySQL-8.0%2B-00758F?style=for-the-badge&logo=mysql&logoColor=white)](https://www.mysql.com/)
[![MariaDB Compatible](https://img.shields.io/badge/MariaDB-10.4%2B-003545?style=for-the-badge&logo=mariadb&logoColor=white)](https://mariadb.org/)
[![Database Engine](https://img.shields.io/badge/Engine-InnoDB-f29111?style=for-the-badge)](https://dev.mysql.com/doc/refman/8.0/en/innodb-storage-engine.html)
[![Normalization](https://img.shields.io/badge/Standard-3NF%20Normalized-success?style=for-the-badge)](#relational-architecture--3nf-normalization)
[![Academic Evaluation](https://img.shields.io/badge/Academic%20Grade-A%2B%20Rubric-blueviolet?style=for-the-badge)](#viva-voce--academic-defense-kit)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

> A production-grade, enterprise-ready relational database management project designed for university computer science students, DBMS semester submissions, and technical viva defense. Implements First-In, First-Expired, First-Out (FIFO) stock allocation with pessimistic row-locking, ACID transaction safety, regulatory compliance triggers, and analytical views.

---

## Repository Overview

- **Repository**: `pharmacy-inventory-fifo-database-project`
- **GitHub URL**: [https://github.com/affaan-891/pharmacy-inventory-fifo-database-project](https://github.com/affaan-891/pharmacy-inventory-fifo-database-project)
- **Target Audience**: University CS/SE students, DBMS course evaluators, database engineers.
- **Domain**: Pharmaceutical Retail Supply Chain & Expiry Management.

### Why This Domain?
In standard commercial retail, simple quantity deductions (`stock = stock - qty`) are common. In healthcare and pharmaceuticals, dispensing expired medication is a critical safety and legal violation. Medications arrive in discrete manufacturing batches with distinct expiration dates and acquisition costs. When an order is placed:
1. Stock must be deducted strictly from the **earliest-expiring available batch** (FIFO / FEFO).
2. Large orders spanning multiple batches must be split transparently across those batches.
3. Schedule-controlled narcotics require verified physician prescriptions before dispensing.
4. An immutable audit trail must log every stock increment and decrement.

---

## Directory Structure

```text
pharmacy-inventory-fifo-database-project/
├── database/
│   ├── 01_schema.sql             # 3NF DDL: 11 tables, constraints, foreign keys, indexes
│   ├── 02_triggers.sql           # Integrity & safety triggers (expiry prevention, audit, Rx validation)
│   ├── 03_procedures.sql         # FIFO cursor procedure (ACID), supplier statements, profit margin function
│   ├── 04_views_and_queries.sql  # Analytical views & 5 complex viva evaluation queries
│   └── 05_seed_data.sql          # Realistic pharmaceutical formulary, batches, customers, scripts, orders
├── docs/
│   ├── ERD.md                    # Crow's Foot Mermaid ERD & comprehensive Data Dictionary
│   └── VIVA_QUESTIONS.md         # 10 deep-dive DBMS viva voce Q&As with full examiner model answers
└── README.md                     # Comprehensive project documentation
```

---

## Relational Architecture & 3NF Normalization

The schema consists of **11 normalized tables** engineered to satisfy Third Normal Form (3NF) requirements:

```
[suppliers] ──< [purchase_orders] ──< [purchase_order_items] >── [medicines] >── [categories]
     │                                                               │
     └─────────< [medicine_batches] >────────────────────────────────┘
                         │
                         ├────< [sales_order_items] >──── [sales_orders] ──< [prescriptions] >── [customers]
                         │                                      │
                         └────< [inventory_audit_logs]          └───────────────────────────────┘
```

### Table Summary

| Table Name | Primary Key | Description | Key Integrity Rules |
| :--- | :--- | :--- | :--- |
| `suppliers` | `supplier_id` | Wholesale drug distributors | `rating BETWEEN 1.0 AND 5.0`, Unique phone/email |
| `categories` | `category_id` | Pharmacological classes | Unique name, `requires_prescription` flag |
| `medicines` | `medicine_id` | Formulary master entities | `dosage_form ENUM`, non-negative reorder level |
| `medicine_batches`| `batch_id` | Physical stock lots | `UNIQUE(medicine_id, batch_number)`, `expiry > mfg` |
| `customers` | `customer_id` | Retail clients & patients | Unique phone, non-negative loyalty points |
| `prescriptions` | `prescription_id`| Medical authorizations | Status ENUM (`Verified`, `Pending`, `Rejected`) |
| `sales_orders` | `order_id` | Invoice headers | Unique invoice number, non-negative amounts |
| `sales_order_items`| `item_id` | Batch-level dispensing lines | Foreign keys to order & batch, non-negative prices |
| `purchase_orders` | `po_id` | Inbound procurement headers | Unique PO number, status ENUM |
| `purchase_order_items`| `po_item_id` | Inward batch intake manifests | Linked to PO and drug formulary |
| `inventory_audit_logs`| `log_id` | Immutable compliance ledger | Non-negative remaining stock, action type ENUM |

*For complete attribute data types, foreign key actions, and Mermaid diagram, refer to [docs/ERD.md](docs/ERD.md).*

---

## Key Features & Business Logic

### 1. FIFO Dispensing Stored Procedure (`sp_dispense_medicine_fifo`)
- **ACID Transaction**: Enclosed within `START TRANSACTION`, `COMMIT`, and `ROLLBACK` on `SQLEXCEPTION`.
- **Pessimistic Row-Locking**: Uses `SELECT ... FOR UPDATE` on candidate batches ordered by `expiry_date ASC, batch_id ASC` to prevent race conditions during high-concurrency checkout.
- **Dynamic Multi-Batch Splitting**: If a patient requests 100 tablets and the earliest batch has only 40, the procedure dispenses all 40 from Batch 1 and allocates the remaining 60 from Batch 2 in a single atomic transaction.

### 2. Business Safety Triggers
- `trg_prevent_expired_batch_sale`: Prevents inserting any sales order item where `medicine_batches.expiry_date <= CURRENT_DATE()`, raising `SQLSTATE '45000'`.
- `trg_validate_controlled_drug_prescription`: Prohibits dispensing controlled narcotics or Rx-mandatory drugs without a verified prescription.
- `trg_validate_prescription_on_order`: Verifies that attached prescriptions are verified and belong to the purchasing customer.
- `trg_deduct_batch_quantity_after_sale`: Automatically decrements `available_quantity` in `medicine_batches` and writes an immutable audit record to `inventory_audit_logs`.

### 3. Real-Time Analytical Views
- `vw_expiring_batches_30_days`: Exposes batches expiring within 30 days, calculating current stock, supplier contacts, and potential financial loss.
- `vw_medicine_inventory_health`: Aggregates active usable inventory, active lot count, inventory valuation, and stock health status (`OPTIMAL`, `REORDER NEEDED`, `OUT OF STOCK`).

---

## Quick-Start Setup Guide

### Prerequisites
- MySQL 8.0+ or MariaDB 10.4+ (Included with XAMPP, WAMP, or standalone)
- MySQL Command Line Client or GUI (DBeaver, MySQL Workbench, phpMyAdmin)

### Step 1: Clone the Repository
```bash
git clone https://github.com/affaan-891/pharmacy-inventory-fifo-database-project.git
cd pharmacy-inventory-fifo-database-project
```

### Step 2: Execute SQL Scripts Sequentially
Execute the files in order using the MySQL CLI:

```bash
# Windows (PowerShell or CMD)
mysql -u root -p < database/01_schema.sql
mysql -u root -p < database/02_triggers.sql
mysql -u root -p < database/03_procedures.sql
mysql -u root -p < database/04_views_and_queries.sql
mysql -u root -p < database/05_seed_data.sql

# macOS / Linux
mysql -u root -p < database/01_schema.sql
mysql -u root -p < database/02_triggers.sql
mysql -u root -p < database/03_procedures.sql
mysql -u root -p < database/04_views_and_queries.sql
mysql -u root -p < database/05_seed_data.sql
```

*Tip for XAMPP users on Windows*: If `mysql` is not in your global system `PATH`, run:
```powershell
& "C:\xampp\mysql\bin\mysql.exe" -u root < database/01_schema.sql
```

---

## Live Verification & Testing

### 1. Execute FIFO Multi-Batch Dispensing
Call the stored procedure to purchase 300 units of Amoxicillin (`medicine_id = 1`) for Customer 1 with Prescription 1:

```sql
USE pharmacy_inventory_db;

-- Call procedure
CALL sp_dispense_medicine_fifo(1, 1, 300, 1, @new_order_id);

-- Inspect generated order header
SELECT * FROM sales_orders WHERE order_id = @new_order_id;

-- Inspect multi-batch allocation breakdown
SELECT * FROM sales_order_items WHERE order_id = @new_order_id;

-- Verify batch inventory deductions
SELECT batch_id, batch_number, expiry_date, available_quantity 
FROM medicine_batches 
WHERE medicine_id = 1 
ORDER BY expiry_date ASC;
```

**Output Demonstration**:
- Batch 1 (earlier expiry date) is completely exhausted from 280 units to 0.
- Batch 2 (later expiry date) satisfies the remaining 20 units (500 down to 480).
- Batch 3 (expired batch) is ignored by the cursor.

---

### 2. Verify Expiry Prevention Trigger
Attempting to sell an expired batch (`batch_id = 3`):

```sql
INSERT INTO sales_order_items (order_id, batch_id, quantity, unit_price, subtotal)
VALUES (1, 3, 5, 11.50, 57.50);
```

**Result**:
```text
ERROR 1644 (45000): Compliance Violation: Expired medicine batch cannot be dispensed.
```

---

### 3. Verify Controlled Substance Regulation Trigger
Attempting to sell Tramadol (`batch_id = 11`) on an Over-The-Counter order without a prescription:

```sql
INSERT INTO sales_order_items (order_id, batch_id, quantity, unit_price, subtotal)
VALUES (5, 11, 2, 28.00, 56.00);
```

**Result**:
```text
ERROR 1644 (45000): Compliance Violation: Controlled substance or Rx medicine requires a verified prescription on file.
```

---

## Viva Voce & Academic Defense Kit

Prepare for lab defense and academic viva voce with our comprehensive question-and-answer guide:

| # | Topic | Key Concepts Covered |
| :- | :--- | :--- |
| **Q1** | **Cursor vs Set-Based Update** | Running balance state machines, line-item traceability, pessimistic locking |
| **Q2** | **ACID & Concurrency** | 2PL, MVCC, dirty/phantom reads, row-level locks (`FOR UPDATE`) |
| **Q3** | **3NF Normalization** | 1NF/2NF/3NF progression, eliminating transitive dependencies |
| **Q4** | **Multi-Batch Order Splitting** | Splitting orders across lots while maintaining single invoice headers |
| **Q5** | **Trigger Cascading** | BEFORE vs AFTER event separation, avoiding mutating table deadlocks |
| **Q6** | **Surrogate vs Natural Keys** | Clustered index leaf size, memory footprint in InnoDB Buffer Pool |
| **Q7** | **Anti-Joins (`NOT EXISTS`)** | Three-valued boolean logic (`UNKNOWN`), Anti-Semi-Join optimization |
| **Q8** | **Window Functions** | `DENSE_RANK()` vs `RANK()`, `PARTITION BY`, non-collapsing queries |
| **Q9** | **Composite Indexing** | Leftmost prefix rule, B+ tree traversal, eliminating filesorts |
| **Q10**| **Regulatory Audit Logging** | Append-only architecture, FDA 21 CFR Part 11, mathematical reconciliation |

*Read the full answers in [docs/VIVA_QUESTIONS.md](docs/VIVA_QUESTIONS.md).*

---

## Git Workflow & Push Instructions

Follow these commands to push the project to your GitHub repository:

```powershell
# Navigate to project root
cd c:\xampp\htdocs\pharmacy-inventory-fifo-database-project

# Initialize Git repository
git init

# Link remote repository
git remote add origin https://github.com/affaan-891/pharmacy-inventory-fifo-database-project.git

# Pull remote files (e.g. LICENSE, if initialized on GitHub)
git pull origin main --allow-unrelated-histories

# Stage and commit all files
git add .
git commit -m "feat: complete pharmacy FIFO inventory DBMS project with 3NF schema, triggers, procedures, views and ERD"

# Rename branch to main and push
git branch -M main
git push -u origin main
```

---

## License

This project is licensed under the [MIT License](LICENSE) - open for university coursework, student learning, and academic development.
