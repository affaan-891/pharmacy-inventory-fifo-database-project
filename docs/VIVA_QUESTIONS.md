# Database Management Systems (DBMS) Technical Viva Voce Guide

**Project**: Pharmacy Expiry & Batch-Wise FIFO Inventory Database System  
**Engine**: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Storage Engine)  
**Target Audience**: CS / SE University Students, DBMS Lab Examiners, and Technical Interviewees  
**Repository**: [pharmacy-inventory-fifo-database-project](https://github.com/affaan-891/pharmacy-inventory-fifo-database-project)

---

## Question 1: FIFO Cursor vs. Single Set-Based UPDATE
**Examiner**: *"Why did you use a Cursor with a procedural loop in `sp_dispense_medicine_fifo` instead of a single set-based `UPDATE` statement?"*

### Model Answer:
In relational algebra, SQL is declarative and optimized for set-based operations. However, fulfilling an arbitrary requested quantity ($Q$) by drawing partial or whole quantities across multiple ordered discrete rows ($R_1, R_2, \dots, R_n$) requires **running balance state tracking**:
1. **Running Balance State Machine**: When an order requires 50 units, and Batch 1 holds 20 units while Batch 2 holds 60 units, the system must exhaust Batch 1 (deduct 20) and deduct only the remaining 30 units from Batch 2, leaving Batch 2 with 30 units. A standard set-based `UPDATE medicine_batches SET available_quantity = available_quantity - ?` cannot conditionally clamp deductions to zero on earlier rows and stop deductions on subsequent rows without complex window functions and multi-table joins.
2. **Granular Line-Item Traceability**: Regulatory compliance (FDA / Good Distribution Practice) mandates that each portion of the order be linked to its exact physical batch via `sales_order_items`. The cursor allows inserting an individual line item for each batch consumed during the loop.
3. **Pessimistic Concurrency Control**: The cursor query incorporates `FOR UPDATE`, placing exclusive row-level locks on the candidate batches in `expiry_date ASC` order. This prevents concurrent transactions from overselling the same stock.

---

## Question 2: ACID Properties and Isolation Levels in Retail Checkout
**Examiner**: *"Explain how your system enforces ACID properties. What happens if two cashiers attempt to sell the last 10 units of Amoxicillin simultaneously?"*

### Model Answer:
The system wraps multi-batch deductions inside explicit `START TRANSACTION` and `COMMIT` blocks:
- **Atomicity**: If an error occurs midway (e.g., system failure, negative inventory, or trigger violation), the `DECLARE EXIT HANDLER FOR SQLEXCEPTION` executes a `ROLLBACK`, reverting all changes so no orphaned sales orders or partial deductions remain.
- **Consistency**: All schema constraints (`CHECK (available_quantity >= 0)`, foreign key references, and trigger validation rules) are validated before commit.
- **Isolation**: InnoDB uses **Two-Phase Locking (2PL)** and **Multi-Version Concurrency Control (MVCC)**. When Transaction A opens `cur_fifo_batches` with `FOR UPDATE`, InnoDB acquires an exclusive row lock (`X-lock`) on those specific batch rows. When Transaction B attempts to read the same rows `FOR UPDATE`, it is forced into a lock-wait state until Transaction A commits or rolls back. Once Transaction A commits, Transaction B reads the updated `available_quantity = 0` and is safely aborted with an `Insufficient stock` exception.
- **Durability**: Once `COMMIT` is executed, the transaction changes are written to InnoDB's Write-Ahead Redo Log (`ib_logfile`) and flushed to non-volatile disk storage.

---

## Question 3: 3NF Normalization Breakdown and Dependency Analysis
**Examiner**: *"Walk me through the normalization process for this database from 1NF to 3NF. Identify one transitive dependency you eliminated."*

### Model Answer:
- **1NF (Atomicity & Repeating Groups)**: Every column holds atomic, indivisible values. In an un-normalized spreadsheet, an invoice would contain multiple medicines listed in a single comma-separated cell. We eliminated repeating groups by creating `sales_order_items` with an atomic row for each item.
- **2NF (Elimination of Partial Dependencies)**: In 2NF, every non-key attribute must depend on the *entire* primary key, not a proper subset. In `sales_order_items`, the primary key is `item_id` (or composite `(order_id, batch_id)`). If we had stored `customer_name` or `hospital_name` inside `sales_order_items`, those attributes would depend only on `order_id`, not on `batch_id`. Moving customer data to `customers` and prescription details to `prescriptions` eliminates partial dependencies.
- **3NF (Elimination of Transitive Dependencies)**: In 3NF, non-key attributes must not depend on other non-key attributes ($X \to Y$ and $Y \to Z$).
  - *Example in this schema*: If `medicines` contained `category_name` and `requires_prescription`, the functional dependencies would be:
    $$\text{medicine\_id} \to \text{category\_id} \quad \text{and} \quad \text{category\_id} \to (\text{category\_name}, \text{requires\_prescription})$$
    Here, `category_name` transitively depends on `medicine_id` through `category_id`. We decomposed this by extracting `categories` into its own table with `category_id` as the primary key.

---

## Question 4: Multi-Batch Order Splitting Mechanics
**Examiner**: *"Suppose a patient requests 100 tablets of Ciprofloxacin. Batch A (expiring next month) has 40 tablets, and Batch B (expiring in 6 months) has 150 tablets. How does the database record this transaction?"*

### Model Answer:
1. The procedure `sp_dispense_medicine_fifo` verifies total active stock ($40 + 150 = 190 \ge 100$).
2. A single `sales_orders` header is created with `invoice_number = 'INV-...'`.
3. In Iteration 1 of the FIFO loop:
   - Batch A is fetched ($40 \le 100$).
   - A line item is inserted into `sales_order_items`: `(order_id, batch_id = A, quantity = 40, unit_price, subtotal)`.
   - `trg_deduct_batch_quantity_after_sale` decrements Batch A's `available_quantity` from 40 to 0 and records an audit log entry.
   - Remaining needed quantity is updated: $100 - 40 = 60$.
4. In Iteration 2 of the FIFO loop:
   - Batch B is fetched ($150 > 60$).
   - A second line item is inserted into `sales_order_items`: `(order_id, batch_id = B, quantity = 60, unit_price, subtotal)`.
   - The trigger decrements Batch B's `available_quantity` from 150 to 90 and records an audit log entry.
   - Remaining needed quantity becomes 0; loop terminates.
5. The invoice summary in `sales_orders` is updated with the combined total amount, and the transaction commits. One invoice contains two transparent batch line items for complete drug lot traceability.

---

## Question 5: Trigger Cascading and the "Mutating Table" Phenomenon
**Examiner**: *"Why did you separate the safety check into a BEFORE trigger and the inventory decrement into an AFTER trigger? Could this cause recursive trigger cascading?"*

### Model Answer:
- **Separation of Concerns**:
  - `BEFORE INSERT` (`trg_prevent_expired_batch_sale`): Fires before row persistence. If `expiry_date <= CURRENT_DATE()` or `quantity > available_quantity`, it raises `SIGNAL SQLSTATE '45000'`. Raising the signal in `BEFORE INSERT` prevents disk writes and ensures zero undo overhead.
  - `AFTER INSERT` (`trg_deduct_batch_quantity_after_sale`): Fires only after the sales line item successfully passes all checks and constraint validations. It then safely modifies the parent `medicine_batches` row and inserts an immutable audit log.
- **Mutating Table Prevention**:
  - In relational databases (such as Oracle or MySQL), attempting to read or modify the *same* table that is currently undergoing an `INSERT`/`UPDATE` within a row-level trigger causes a "Mutating Table Error" (or unpredictable reads).
  - Our `AFTER INSERT` trigger on `sales_order_items` modifies a *different* table (`medicine_batches`) and writes to `inventory_audit_logs`. Because neither of these target tables has an `AFTER UPDATE` trigger pointing back to `sales_order_items`, the dependency graph is an **Acyclic Directed Graph (DAG)**. Recursive cascading is mathematically impossible.

---

## Question 6: Natural vs. Surrogate Primary Keys
**Examiner**: *"Why did you use surrogate integer keys (`batch_id`, `medicine_id`) instead of natural composite keys like `(medicine_id, batch_number)` as the primary key?"*

### Model Answer:
1. **Index B-Tree Footprint & Buffer Pool Efficiency**: In InnoDB, every secondary index stores a copy of the table's clustered index (Primary Key). A compact 4-byte `INT` primary key keeps secondary index nodes small, maximizing the number of index pages that can fit in InnoDB's buffer pool memory. Using a composite primary key like `(INT, VARCHAR(50))` would inflate secondary index leaf nodes by over 50 bytes per entry.
2. **Foreign Key Performance & Joins**: Joining on a single 32-bit integer (`item.batch_id = batch.batch_id`) requires a single CPU register cycle comparison. Joining on composite string keys involves byte-by-byte collation lookups.
3. **Data Integrity Preservation**: We preserved domain uniqueness by adding an explicit `UNIQUE KEY uq_medicine_batch (medicine_id, batch_number)`. This combines the lookup performance of surrogate keys with the strict business uniqueness of natural candidate keys.

---

## Question 7: Anti-Join Strategies: NOT EXISTS vs. NOT IN vs. LEFT JOIN
**Examiner**: *"In Query 2 of file 04, you used `NOT EXISTS` to find medicines with zero active batches. Why is `NOT EXISTS` preferred over `NOT IN` in SQL?"*

### Model Answer:
1. **Three-Valued Logic and NULL Hazards**: In standard SQL, comparison with `NULL` yields `UNKNOWN`. If a subquery evaluated by `NOT IN` returns even a single `NULL` row, the expression `x NOT IN (val1, NULL)` evaluates to `UNKNOWN` for all outer rows, causing the entire query to return zero results (silent logical failure). `NOT EXISTS` uses two-valued existential quantification (`TRUE` or `FALSE`) and is completely unaffected by `NULL` values.
2. **Query Optimizer Execution Plan**: The MySQL query optimizer converts a correlated `NOT EXISTS` subquery into an **Anti-Semi-Join**. As soon as the storage engine finds a single matching row in `medicine_batches` satisfying the index conditions (`expiry_date > CURRENT_DATE() AND available_quantity > 0`), it halts scanning for that medicine immediately (early exit). `NOT IN` often forces the engine to materialize the entire subquery result set in a temporary table.

---

## Question 8: Window Functions vs. GROUP BY Aggregations
**Examiner**: *"In Query 4, what is the fundamental difference between using `DENSE_RANK() OVER (PARTITION BY ...)` and a standard `GROUP BY` clause?"*

### Model Answer:
- **`GROUP BY` (Collapsing Transformation)**: `GROUP BY` collapses multiple input rows sharing the same grouping keys into a single summary row. Once rows are grouped, individual row identity is lost; you can only select grouping columns or aggregate functions (`SUM`, `AVG`, `MAX`).
- **Window Functions (Non-Collapsing Context Preservation)**: Window functions perform calculations across a defined subset of rows (the window frame defined by `PARTITION BY`) while **retaining the identity and attributes of each individual row**.
- **`DENSE_RANK()` vs `RANK()`**:
  - `RANK()` leaves gaps in rank numbering after ties (e.g., 1, 2, 2, 4).
  - `DENSE_RANK()` assigns consecutive integers without gaps (e.g., 1, 2, 2, 3). In retail sales rankings, `DENSE_RANK()` prevents missing rank tiers when multiple medicines tie in sales volume.

---

## Question 9: Composite Index Ordering and the Leftmost Prefix Rule
**Examiner**: *"Explain why you defined the composite index as `(medicine_id, expiry_date, available_quantity)`. What happens if a query filters by `available_quantity` without filtering by `medicine_id`?"*

### Model Answer:
1. **B+ Tree Hierarchical Sorting**: A composite B+ Tree index is sorted lexicographically: first by the leftmost column (`medicine_id`), then by the second column (`expiry_date`) within identical `medicine_id` values, and finally by `available_quantity`.
2. **The Leftmost Prefix Rule**:
   - The query planner can use an index if the query's `WHERE` clause filters on a prefix of the index columns.
   - For FIFO lookups (`WHERE medicine_id = ? AND expiry_date > ?`), the engine performs an exact point-lookup on `medicine_id`, followed by a high-speed range scan along the B-tree leaf pages on `expiry_date`.
   - Because rows in that leaf branch are already physically sorted by `expiry_date ASC`, the engine reads rows in FIFO order directly, completely eliminating the need for a temporary filesort (`Using filesort`).
3. **Skipping the Prefix**: If a query filters *only* on `available_quantity`, the B+ tree's root and branch nodes cannot be navigated because values are scattered across the tree based on the preceding columns. The optimizer will discard the index and perform a Full Table Scan (`ALL`).

---

## Question 10: Regulatory Compliance and Audit Ledger Immutability
**Examiner**: *"How does `inventory_audit_logs` guarantee compliance with pharmaceutical regulatory standards (like FDA 21 CFR Part 11)? How would you prevent tampering?"*

### Model Answer:
1. **Append-Only Architecture**:
   - The `inventory_audit_logs` table contains only `INSERT` operations initiated automatically by database triggers (`trg_deduct_batch_quantity_after_sale`) or inward procurement routines.
   - In production environments, strict Role-Based Access Control (RBAC) is enforced at the database privilege level:
     ```sql
     REVOKE UPDATE, DELETE ON pharmacy_inventory_db.inventory_audit_logs FROM 'pharmacy_app'@'%';
     GRANT INSERT, SELECT ON pharmacy_inventory_db.inventory_audit_logs TO 'pharmacy_app'@'%';
     ```
   - Even database administrators and application software cannot mutate historical log entries without administrative trigger alteration.
2. **Bidirectional Ledger Reconciliation**:
   - Each log entry captures `quantity_changed` (delta) and `remaining_quantity` (running balance snapshot).
   - An auditor can run a mathematical verification query verifying that for every batch:
     $$\text{initial\_quantity} + \sum (\text{quantity\_changed}) = \text{available\_quantity}$$
   - Any unauthorized direct update to `medicine_batches` will immediately produce a discrepancy when compared against the sum of the immutable audit trail.
