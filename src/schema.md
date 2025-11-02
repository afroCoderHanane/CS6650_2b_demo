# E-commerce Shopping Cart Database Design Analysis

## 1. Schema Design

### Table Structure (3 tables)

**Products Table**
- Core product catalog with pricing and inventory
- Fields: id, name, description, price, stock, category, image_url, timestamps
- Represents the source of truth for product information

**Carts Table**
- Represents shopping sessions for customers
- Fields: id, customer_id, customer_name, customer_email, status, total_amount, timestamps
- Denormalizes customer info for performance (avoids joins to users table)
- Status tracking enables cart lifecycle management (active → completed/abandoned)

**Cart_Items Table**
- Junction table implementing many-to-many relationship between carts and products
- Fields: id, cart_id, product_id, quantity, price_at_addition, timestamps
- **Key Decision**: `price_at_addition` captures historical pricing - crucial for price consistency during checkout

### Why This Structure?

**Normalization Balance**: The design is mostly 3NF (Third Normal Form) with strategic denormalization:
- Customer info in `carts` table avoids constant joins to a separate `users` table
- `price_at_addition` in `cart_items` preserves transactional integrity when product prices change
- `total_amount` in `carts` is denormalized for quick access (can be recalculated from cart_items)

**Scalability**: Separating cart_items allows:
- Independent scaling of cart metadata vs. line items
- Efficient queries for "what products are in this cart?" without full table scans
- Easy purging of old carts without orphaning product data

## 2. Key Strategy

### Primary Keys
```sql
id INT AUTO_INCREMENT PRIMARY KEY
```
- Auto-incrementing integers for all tables
- Simple, efficient for MySQL InnoDB (clustered index on PK)
- **Trade-off**: Sequential IDs can expose business metrics; UUIDs would hide this but sacrifice performance

### Foreign Keys
```sql
CONSTRAINT fk_cart_items_cart 
    FOREIGN KEY (cart_id) REFERENCES carts(id) ON DELETE CASCADE

CONSTRAINT fk_cart_items_product 
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
```

**Design Rationale**:
- **CASCADE on cart deletion**: When a cart is deleted, all items should go with it (orphaned cart items are meaningless)
- **RESTRICT on product deletion**: Prevents deleting products that exist in active carts (data integrity protection)
- Alternative approach: Soft deletes on products (add `deleted_at` column) to preserve historical data

### Constraints

**Check Constraints**:
```sql
CONSTRAINT chk_price CHECK (price >= 0)
CONSTRAINT chk_stock CHECK (stock >= 0)
CONSTRAINT chk_quantity CHECK (quantity > 0)
```
- Prevent negative prices/quantities/stock (business logic enforcement at DB level)
- **Benefit**: Catches bugs even if application validation fails

**Unique Constraint**:
```sql
UNIQUE KEY uk_cart_product (cart_id, product_id)
```
- Prevents duplicate products in the same cart
- Forces application to UPDATE quantity rather than INSERT duplicate rows
- **Critical for consistency**: Without this, you could have multiple rows for the same product

## 3. Index Strategy

### Indexes Added and Why

**Products Table**:
```sql
INDEX idx_category (category)  -- Product listing pages filtered by category
INDEX idx_name (name)          -- Search functionality
```
- `category` index: Supports "SELECT * FROM products WHERE category = 'Electronics'" (common query)
- `name` index: Enables efficient product search/autocomplete
- **Not indexed**: `price` (range queries less common than exact category matches)

**Carts Table**:
```sql
INDEX idx_customer_id (customer_id)              -- "Show me this customer's carts"
INDEX idx_status (status)                         -- Admin queries for abandoned carts
INDEX idx_created_at (created_at)                 -- Time-based analytics
INDEX idx_customer_status (customer_id, status)   -- Composite for "customer's active cart"
```

**Critical Composite Index**:
```sql
INDEX idx_customer_status (customer_id, status)
```
This supports the most common query pattern:
```sql
SELECT * FROM carts WHERE customer_id = ? AND status = 'active'
```
- **Why composite?**: MySQL can use this for customer_id alone, customer_id + status, or status alone (leftmost prefix rule)
- **Query optimizer wins**: Avoids table scans when finding a user's active cart

**Cart_Items Table**:
```sql
INDEX idx_cart_id (cart_id)      -- "Get all items in this cart" (most frequent query)
INDEX idx_product_id (product_id) -- "Which carts contain this product?"
```
- `cart_id` index is essential for the primary use case: displaying cart contents
- `product_id` supports inventory management queries ("who has this product in their cart?")

### What's NOT Indexed?

- **timestamps** (except `carts.created_at`): Updated frequently, indexing would slow writes
- **description, image_url**: TEXT/VARCHAR fields rarely queried for exact matches
- **total_amount**: Usually queried as a calculation, not a filter

## 4. Transaction Design

### Concurrent Cart Modification Strategy

**Problem**: Two requests trying to modify the same cart simultaneously:
- User adds item A in browser tab 1
- User adds item B in browser tab 2
- Risk: Lost updates, incorrect totals, race conditions

### Solution: Pessimistic Locking with Row-Level Locks

```sql
START TRANSACTION;

-- Acquire exclusive lock on the cart row
SELECT * FROM carts WHERE id = ? FOR UPDATE;

-- Check if product already exists in cart
SELECT * FROM cart_items 
WHERE cart_id = ? AND product_id = ? 
FOR UPDATE;

-- Either INSERT new item or UPDATE quantity
INSERT INTO cart_items (cart_id, product_id, quantity, price_at_addition)
VALUES (?, ?, ?, ?)
ON DUPLICATE KEY UPDATE 
    quantity = quantity + VALUES(quantity),
    updated_at = CURRENT_TIMESTAMP;

-- Recalculate cart total
UPDATE carts 
SET total_amount = (
    SELECT SUM(quantity * price_at_addition) 
    FROM cart_items 
    WHERE cart_id = ?
),
updated_at = CURRENT_TIMESTAMP
WHERE id = ?;

COMMIT;
```

### Key Transaction Principles

**1. FOR UPDATE Locking**:
- Prevents concurrent modifications to the same cart
- Other transactions wait until the first COMMIT/ROLLBACK
- **Trade-off**: Slightly slower under high contention, but prevents data corruption

**2. ON DUPLICATE KEY UPDATE**:
```sql
INSERT ... ON DUPLICATE KEY UPDATE quantity = quantity + VALUES(quantity)
```
- Leverages the `UNIQUE KEY uk_cart_product (cart_id, product_id)` constraint
- Atomic operation: no race condition between checking existence and inserting
- **Alternative**: Application-level "SELECT then INSERT/UPDATE" is vulnerable to race conditions

**3. Total Amount Recalculation**:
- Calculated from cart_items (source of truth) rather than incrementing
- Prevents drift from concurrent updates
- **Trade-off**: Slower than `total_amount = total_amount + new_price`, but always accurate

### Alternative: Optimistic Locking

```sql
-- Add version column to carts table
ALTER TABLE carts ADD COLUMN version INT DEFAULT 0;

-- In application code:
UPDATE carts 
SET total_amount = ?, version = version + 1, updated_at = NOW()
WHERE id = ? AND version = ?;

-- If affected_rows = 0, retry transaction
```

**When to use**:
- High read-to-write ratio
- Low contention on same cart
- Mobile apps with offline support

**Trade-offs**:
- More complex retry logic in application
- Better throughput under low contention
- Worse UX under high contention (users see "please try again" errors)

## 5. Critical Trade-offs Considered

### Denormalization vs. Normalization

**Decision**: Denormalize customer info in `carts` table

**Why?**:
- Avoids JOIN to users table on every cart fetch
- Shopping cart queries are extremely frequent (every page load)
- Customer info rarely changes mid-session

**Cost**: 
- Data duplication if customer updates profile
- **Mitigation**: Only store immutable identifiers (customer_id) + snapshot of name/email at cart creation

### Price History

**Decision**: Store `price_at_addition` in cart_items

**Why?**:
- Product prices change frequently (sales, promotions)
- Customers expect checkout price to match the price when they added item
- Legal requirement in some jurisdictions (price consistency)

**Alternative Rejected**: Always use current `products.price`
- **Problem**: User adds item at $10, price changes to $15, checkout surprises user with higher price
- **Problem**: Flash sale ends, user loses sale price they qualified for

### Total Amount Calculation

**Decision**: Store denormalized `total_amount` in carts but recalculate it transactionally

**Why?**:
- Fast reads for "show cart summary" queries (no aggregation needed)
- Recalculation prevents drift from concurrent updates
- **Alternative**: Always calculate on-the-fly
  - Pros: Guaranteed accuracy, no denormalization
  - Cons: SUM query on every cart display (slower, more DB load)

### Index on (customer_id, status) vs. Separate Indexes

**Decision**: Composite index on both columns

**Why?**:
- The query `WHERE customer_id = ? AND status = 'active'` is the most common access pattern
- MySQL can use leftmost prefix for `WHERE customer_id = ?` queries too
- Covers 90% of cart access patterns with one index

**Cost**:
- Slightly larger index size
- More expensive on writes (but carts aren't written that frequently)

## 6. Additional Considerations for Production

### Missing Features in Current Schema

1. **Soft Deletes**: Add `deleted_at` to products for historical preservation
2. **Audit Trail**: Separate `cart_history` table for debugging/analytics
3. **Inventory Reservation**: Temporary stock hold during checkout
4. **Concurrency Control**: Add `version` column for optimistic locking option

### Monitoring Queries

```sql
-- Find abandoned carts (retention marketing)
SELECT * FROM carts 
WHERE status = 'active' 
AND updated_at < NOW() - INTERVAL 24 HOUR;

-- Low stock alerts
SELECT * FROM products WHERE stock < 10;

-- Popular products in carts (not yet purchased)
SELECT p.name, SUM(ci.quantity) as total_in_carts
FROM cart_items ci
JOIN products p ON ci.product_id = p.id
JOIN carts c ON ci.cart_id = c.id
WHERE c.status = 'active'
GROUP BY p.id
ORDER BY total_in_carts DESC;
```

This schema balances performance, data integrity, and scalability for a production e-commerce system, with careful consideration of concurrent access patterns and real-world business requirements.