package models

import "time"

// Cart represents a shopping cart
type Cart struct {
	ID            int32     `json:"id"`
	CustomerID    int32     `json:"customerId"`
	CustomerName  string    `json:"customerName"`
	CustomerEmail string    `json:"customerEmail"`
	Status        string    `json:"status"`
	TotalAmount   float64   `json:"totalAmount"`
	Items         []CartItem `json:"items"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

// CartItem represents an item in a shopping cart
type CartItem struct {
	ID              int32     `json:"id"`
	CartID          int32     `json:"cartId"`
	ProductID       int32     `json:"productId"`
	ProductName     string    `json:"productName"`
	ProductDesc     string    `json:"productDescription,omitempty"`
	Quantity        int32     `json:"quantity"`
	PriceAtAddition float64   `json:"priceAtAddition"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

// CreateCartRequest represents the request to create a new cart
type CreateCartRequest struct {
	CustomerID    int32  `json:"customerId"`
	CustomerName  string `json:"customerName"`
	CustomerEmail string `json:"customerEmail"`
}

// AddItemRequest represents the request to add an item to a cart
type AddItemRequest struct {
	ProductID int32 `json:"productId"`
	Quantity  int32 `json:"quantity"`
}