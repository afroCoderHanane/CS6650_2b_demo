package repository

import (
	"context"
	"database/sql"
	"fmt"

	"store/database" //nolint: it is imported
	"store/models"
)

// CartRepository handles database operations for shopping carts
type CartRepository struct {
	db *database.DB
}

// NewCartRepository creates a new cart repository
func NewCartRepository(db *database.DB) *CartRepository {
	return &CartRepository{db: db}
}

// CreateCart creates a new shopping cart
func (r *CartRepository) CreateCart(ctx context.Context, req models.CreateCartRequest) (*models.Cart, error) {
	query := `
		INSERT INTO carts (customer_id, customer_name, customer_email, status, total_amount)
		VALUES (?, ?, ?, 'active', 0.00)
	`

	result, err := r.db.ExecContext(ctx, query, req.CustomerID, req.CustomerName, req.CustomerEmail)
	if err != nil {
		return nil, fmt.Errorf("failed to create cart: %w", err)
	}

	cartID, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("failed to get cart ID: %w", err)
	}

	// Retrieve the created cart
	return r.GetCartByID(ctx, int32(cartID))
}

// GetCartByID retrieves a cart with all its items
func (r *CartRepository) GetCartByID(ctx context.Context, cartID int32) (*models.Cart, error) {
	// Use LEFT JOIN to handle empty carts
	query := `
		SELECT 
			c.id, c.customer_id, c.customer_name, c.customer_email,
			c.status, c.total_amount, c.created_at, c.updated_at,
			COALESCE(ci.id, 0), COALESCE(ci.product_id, 0), COALESCE(ci.quantity, 0), 
			COALESCE(ci.price_at_addition, 0.00), COALESCE(ci.created_at, c.created_at), 
			COALESCE(ci.updated_at, c.updated_at),
			COALESCE(p.name, ''), COALESCE(p.description, '')
		FROM carts c
		LEFT JOIN cart_items ci ON c.id = ci.cart_id
		LEFT JOIN products p ON ci.product_id = p.id
		WHERE c.id = ?
	`

	rows, err := r.db.QueryContext(ctx, query, cartID)
	if err != nil {
		return nil, fmt.Errorf("failed to query cart: %w", err)
	}
	defer rows.Close()

	var cart *models.Cart
	items := make([]models.CartItem, 0)

	for rows.Next() {
		if cart == nil {
			cart = &models.Cart{}
		}

		var item models.CartItem
		err := rows.Scan(
			&cart.ID, &cart.CustomerID, &cart.CustomerName, &cart.CustomerEmail,
			&cart.Status, &cart.TotalAmount, &cart.CreatedAt, &cart.UpdatedAt,
			&item.ID, &item.ProductID, &item.Quantity, &item.PriceAtAddition,
			&item.CreatedAt, &item.UpdatedAt, &item.ProductName, &item.ProductDesc,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan cart row: %w", err)
		}

		// Only add item if it exists (item.ID > 0)
		if item.ID > 0 {
			item.CartID = cart.ID
			items = append(items, item)
		}
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating cart rows: %w", err)
	}

	if cart == nil {
		return nil, sql.ErrNoRows
	}

	cart.Items = items
	return cart, nil
}

// AddItemToCart adds or updates an item in a cart
func (r *CartRepository) AddItemToCart(ctx context.Context, cartID int32, req models.AddItemRequest) error {
	// Start transaction for consistency
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Lock the cart row to prevent concurrent modifications
	var exists bool
	err = tx.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM carts WHERE id = ? FOR UPDATE)", cartID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("failed to lock cart: %w", err)
	}
	if !exists {
		return sql.ErrNoRows
	}

	// Get current product price
	var price float64
	err = tx.QueryRowContext(ctx, "SELECT price FROM products WHERE id = ?", req.ProductID).Scan(&price)
	if err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("product not found: %w", err)
		}
		return fmt.Errorf("failed to get product price: %w", err)
	}

	// Insert or update cart item
	query := `
		INSERT INTO cart_items (cart_id, product_id, quantity, price_at_addition)
		VALUES (?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE 
			quantity = quantity + VALUES(quantity),
			updated_at = CURRENT_TIMESTAMP
	`
	_, err = tx.ExecContext(ctx, query, cartID, req.ProductID, req.Quantity, price)
	if err != nil {
		return fmt.Errorf("failed to add item to cart: %w", err)
	}

	// Recalculate cart total
	err = r.recalculateCartTotal(ctx, tx, cartID)
	if err != nil {
		return fmt.Errorf("failed to recalculate cart total: %w", err)
	}

	// Commit transaction
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// recalculateCartTotal updates the total amount for a cart
func (r *CartRepository) recalculateCartTotal(ctx context.Context, tx *sql.Tx, cartID int32) error {
	query := `
		UPDATE carts 
		SET total_amount = (
			SELECT COALESCE(SUM(quantity * price_at_addition), 0.00)
			FROM cart_items 
			WHERE cart_id = ?
		)
		WHERE id = ?
	`
	_, err := tx.ExecContext(ctx, query, cartID, cartID)
	return err
}

// GetCartsByCustomer retrieves all carts for a customer
func (r *CartRepository) GetCartsByCustomer(ctx context.Context, customerID int32) ([]models.Cart, error) {
	query := `
		SELECT id, customer_id, customer_name, customer_email, status, total_amount, created_at, updated_at
		FROM carts
		WHERE customer_id = ?
		ORDER BY created_at DESC
	`

	rows, err := r.db.QueryContext(ctx, query, customerID)
	if err != nil {
		return nil, fmt.Errorf("failed to query customer carts: %w", err)
	}
	defer rows.Close()

	carts := make([]models.Cart, 0)
	for rows.Next() {
		var cart models.Cart
		err := rows.Scan(
			&cart.ID, &cart.CustomerID, &cart.CustomerName, &cart.CustomerEmail,
			&cart.Status, &cart.TotalAmount, &cart.CreatedAt, &cart.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan cart: %w", err)
		}
		carts = append(carts, cart)
	}

	return carts, rows.Err()
}