-- ============================================
-- E-commerce Shopping Cart Database Schema
-- ============================================
-- Design Decisions:
-- 1. Separate carts and cart_items tables for normalization
-- 2. Denormalize customer info in carts table for faster cart retrieval
-- 3. Composite index on (cart_id, product_id) for efficient item lookups
-- 4. Indexes on customer_id and created_at for history queries
-- ============================================

CREATE DATABASE IF NOT EXISTS productdb;
USE productdb;

-- Products table (existing from your current implementation)
DROP TABLE IF EXISTS cart_items;
DROP TABLE IF EXISTS carts;
DROP TABLE IF EXISTS products;

CREATE TABLE products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    category VARCHAR(100),
    image_url VARCHAR(512),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT chk_price CHECK (price >= 0),
    CONSTRAINT chk_stock CHECK (stock >= 0),
    
    -- Indexes
    INDEX idx_category (category),
    INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shopping Carts table
CREATE TABLE carts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) NOT NULL,
    status ENUM('active', 'completed', 'abandoned') DEFAULT 'active',
    total_amount DECIMAL(10, 2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Indexes for efficient queries
    INDEX idx_customer_id (customer_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    INDEX idx_customer_status (customer_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cart Items table (junction table)
CREATE TABLE cart_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cart_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price_at_addition DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Foreign keys for referential integrity
    CONSTRAINT fk_cart_items_cart 
        FOREIGN KEY (cart_id) REFERENCES carts(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_cart_items_product 
        FOREIGN KEY (product_id) REFERENCES products(id) 
        ON DELETE RESTRICT,
    
    -- Constraints
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_price_at_addition CHECK (price_at_addition >= 0),
    
    -- Prevent duplicate product entries in same cart
    UNIQUE KEY uk_cart_product (cart_id, product_id),
    
    -- Composite index for efficient cart item lookups
    INDEX idx_cart_id (cart_id),
    INDEX idx_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed initial products for testing
INSERT INTO products (name, description, price, stock, category) VALUES
('Laptop', 'High-performance laptop', 999.99, 10, 'Electronics'),
('Mouse', 'Wireless mouse', 29.99, 50, 'Electronics'),
('Keyboard', 'Mechanical keyboard', 79.99, 30, 'Electronics'),
('Monitor', '27-inch 4K monitor', 399.99, 15, 'Electronics'),
('Headphones', 'Noise-cancelling headphones', 199.99, 25, 'Electronics');