package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	
	// Use "store" as the base (from go.mod)
	"store/database"
	"store/models"
	"store/repository"
)

// Product represents the product model based on OpenAPI schema
type Product struct {
	ID          int32   `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	Stock       int32   `json:"stock"`
	Category    string  `json:"category,omitempty"`
	ImageURL    string  `json:"imageUrl,omitempty"`
}

// ProductDetailsUpdate supports partial updates for product details
type ProductDetailsUpdate struct {
	Name        *string  `json:"name,omitempty"`
	Description *string  `json:"description,omitempty"`
	Price       *float64 `json:"price,omitempty"`
	Stock       *int32   `json:"stock,omitempty"`
	Category    *string  `json:"category,omitempty"`
	ImageURL    *string  `json:"imageUrl,omitempty"`
}

// Error represents the error response model
type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// ProductStore handles in-memory storage with thread safety
// NOTE: This is kept for backwards compatibility, but products should eventually move to DB
type ProductStore struct {
	mu       sync.RWMutex
	products map[int32]*Product
	nextID   int32
}

// NewProductStore creates a new product store
func NewProductStore() *ProductStore {
	return &ProductStore{
		products: make(map[int32]*Product),
		nextID:   1,
	}
}

// GetProduct retrieves a product by ID (thread-safe read)
func (s *ProductStore) GetProduct(id int32) (*Product, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	product, exists := s.products[id]
	return product, exists
}

// AddOrUpdateProduct adds or updates product details (thread-safe write)
func (s *ProductStore) AddOrUpdateProduct(id int32, product *Product) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Check if product exists
	if _, exists := s.products[id]; !exists {
		return false
	}

	// Update the product, preserving the ID
	product.ID = id
	s.products[id] = product
	return true
}

// CreateProduct creates a new product (for initial data seeding)
func (s *ProductStore) CreateProduct(product *Product) *Product {
	s.mu.Lock()
	defer s.mu.Unlock()

	product.ID = s.nextID
	s.products[s.nextID] = product
	s.nextID++
	return product
}

// Server represents the HTTP server
type Server struct {
	productStore *ProductStore
	cartRepo     *repository.CartRepository
	db           *database.DB
}

// NewServer creates a new server instance
func NewServer(db *database.DB) *Server {
	server := &Server{
		productStore: NewProductStore(),
		cartRepo:     repository.NewCartRepository(db),
		db:           db,
	}
	// Seed some initial products for testing
	server.seedData()
	return server
}

// seedData adds initial products for testing
func (s *Server) seedData() {
	products := []*Product{
		{Name: "Laptop", Description: "High-performance laptop", Price: 999.99, Stock: 10, Category: "Electronics"},
		{Name: "Mouse", Description: "Wireless mouse", Price: 29.99, Stock: 50, Category: "Electronics"},
		{Name: "Keyboard", Description: "Mechanical keyboard", Price: 79.99, Stock: 30, Category: "Electronics"},
	}

	for _, p := range products {
		s.productStore.CreateProduct(p)
	}
}

// ============================================
// Product Handlers (Existing)
// ============================================

// HandleGetProduct handles GET /products/{productId}
func (s *Server) HandleGetProduct(w http.ResponseWriter, r *http.Request) {
	// Extract productId from path
	vars := mux.Vars(r)
	productIDStr := vars["productId"]

	// Parse and validate productId
	productID64, err := strconv.ParseInt(productIDStr, 10, 32)
	if err != nil || productID64 < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid product ID format")
		return
	}
	productID := int32(productID64)

	// Retrieve product from store
	product, exists := s.productStore.GetProduct(productID)
	if !exists {
		writeErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Product with ID %d not found", productID))
		return
	}

	// Return successful response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(product); err != nil {
		log.Printf("Error encoding product response: %v", err)
	}
}

// HandleAddProductDetails handles POST /products/{productId}/details
func (s *Server) HandleAddProductDetails(w http.ResponseWriter, r *http.Request) {
	// Extract productId from path
	vars := mux.Vars(r)
	productIDStr := vars["productId"]

	// Parse and validate productId
	productID64, err := strconv.ParseInt(productIDStr, 10, 32)
	if err != nil || productID64 < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid product ID format")
		return
	}
	productID := int32(productID64)

	// Retrieve current product
	existing, exists := s.productStore.GetProduct(productID)
	if !exists {
		writeErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Product with ID %d not found", productID))
		return
	}

	// Parse request body as partial update
	var upd ProductDetailsUpdate
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields() // Strict parsing
	if err := decoder.Decode(&upd); err != nil {
		writeErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	// Validate provided fields only
	if upd.Price != nil && *upd.Price < 0 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid product data: price must be non-negative")
		return
	}
	if upd.Stock != nil && *upd.Stock < 0 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid product data: stock must be non-negative")
		return
	}
	if upd.Name != nil && *upd.Name == "" {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid product data: name cannot be empty when provided")
		return
	}

	// Apply only provided fields
	if upd.Name != nil {
		existing.Name = *upd.Name
	}
	if upd.Description != nil {
		existing.Description = *upd.Description
	}
	if upd.Price != nil {
		existing.Price = *upd.Price
	}
	if upd.Stock != nil {
		existing.Stock = *upd.Stock
	}
	if upd.Category != nil {
		existing.Category = *upd.Category
	}
	if upd.ImageURL != nil {
		existing.ImageURL = *upd.ImageURL
	}

	// Persist the update (ID preserved by AddOrUpdateProduct)
	if !s.productStore.AddOrUpdateProduct(productID, existing) {
		// This should not happen since we confirmed existence earlier, but handle defensively
		writeErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Product with ID %d not found", productID))
		return
	}

	// Return 204 No Content on success
	w.WriteHeader(http.StatusNoContent)
}

// ============================================
// Shopping Cart Handlers (New)
// ============================================

// HandleCreateCart handles POST /shopping-carts
func (s *Server) HandleCreateCart(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	// Parse request body
	var req models.CreateCartRequest
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		writeErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	// Validate required fields
	if req.CustomerID < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid customer ID")
		return
	}
	if req.CustomerName == "" {
		writeErrorResponse(w, http.StatusBadRequest, "Customer name is required")
		return
	}
	if req.CustomerEmail == "" {
		writeErrorResponse(w, http.StatusBadRequest, "Customer email is required")
		return
	}

	// Create cart
	cart, err := s.cartRepo.CreateCart(ctx, req)
	if err != nil {
		log.Printf("Error creating cart: %v", err)
		writeErrorResponse(w, http.StatusInternalServerError, "Failed to create cart")
		return
	}

	// Return created cart
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(w).Encode(cart); err != nil {
		log.Printf("Error encoding cart response: %v", err)
	}
}

// HandleGetCart handles GET /shopping-carts/{id}
func (s *Server) HandleGetCart(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	// Extract cart ID from path
	vars := mux.Vars(r)
	cartIDStr := vars["id"]

	// Parse and validate cart ID
	cartID64, err := strconv.ParseInt(cartIDStr, 10, 32)
	if err != nil || cartID64 < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid cart ID format")
		return
	}
	cartID := int32(cartID64)

	// Retrieve cart from repository
	cart, err := s.cartRepo.GetCartByID(ctx, cartID)
	if err != nil {
		if err == sql.ErrNoRows {
			writeErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Cart with ID %d not found", cartID))
			return
		}
		log.Printf("Error retrieving cart: %v", err)
		writeErrorResponse(w, http.StatusInternalServerError, "Failed to retrieve cart")
		return
	}

	// Return cart with items
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(cart); err != nil {
		log.Printf("Error encoding cart response: %v", err)
	}
}

// HandleAddItemToCart handles POST /shopping-carts/{id}/items
func (s *Server) HandleAddItemToCart(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	// Extract cart ID from path
	vars := mux.Vars(r)
	cartIDStr := vars["id"]

	// Parse and validate cart ID
	cartID64, err := strconv.ParseInt(cartIDStr, 10, 32)
	if err != nil || cartID64 < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid cart ID format")
		return
	}
	cartID := int32(cartID64)

	// Parse request body
	var req models.AddItemRequest
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		writeErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	// Validate request
	if req.ProductID < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid product ID")
		return
	}
	if req.Quantity < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Quantity must be at least 1")
		return
	}

	// Add item to cart
	err = s.cartRepo.AddItemToCart(ctx, cartID, req)
	if err != nil {
		if err == sql.ErrNoRows {
			writeErrorResponse(w, http.StatusNotFound, "Cart or product not found")
			return
		}
		log.Printf("Error adding item to cart: %v", err)
		writeErrorResponse(w, http.StatusInternalServerError, "Failed to add item to cart")
		return
	}

	// Return 204 No Content on success
	w.WriteHeader(http.StatusNoContent)
}

// HandleGetCustomerCarts handles GET /customers/{customerId}/carts
func (s *Server) HandleGetCustomerCarts(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	// Extract customer ID from path
	vars := mux.Vars(r)
	customerIDStr := vars["customerId"]

	// Parse and validate customer ID
	customerID64, err := strconv.ParseInt(customerIDStr, 10, 32)
	if err != nil || customerID64 < 1 {
		writeErrorResponse(w, http.StatusBadRequest, "Invalid customer ID format")
		return
	}
	customerID := int32(customerID64)

	// Retrieve customer carts
	carts, err := s.cartRepo.GetCartsByCustomer(ctx, customerID)
	if err != nil {
		log.Printf("Error retrieving customer carts: %v", err)
		writeErrorResponse(w, http.StatusInternalServerError, "Failed to retrieve customer carts")
		return
	}

	// Return carts
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(carts); err != nil {
		log.Printf("Error encoding carts response: %v", err)
	}
}

// ============================================
// Utility Functions
// ============================================

// writeErrorResponse writes an error response
func writeErrorResponse(w http.ResponseWriter, statusCode int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	errorResponse := Error{
		Code:    statusCode,
		Message: message,
	}

	if err := json.NewEncoder(w).Encode(errorResponse); err != nil {
		log.Printf("Error encoding error response: %v", err)
	}
}

// LoggingMiddleware logs all incoming requests
func LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("[%s] %s %s", r.Method, r.RequestURI, r.RemoteAddr)
		next.ServeHTTP(w, r)
		log.Printf("[%s] %s completed in %v", r.Method, r.RequestURI, time.Since(start))
	})
}

// RecoveryMiddleware handles panics gracefully
func RecoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				log.Printf("Panic recovered: %v", err)
				writeErrorResponse(w, http.StatusInternalServerError, "Internal server error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// getEnv gets environment variable with fallback
func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func main() {
	// Load database configuration from environment
	dbConfig := database.Config{
		Host:     getEnv("DB_HOST", "localhost"),
		Port:     getEnv("DB_PORT", "3306"),
		User:     getEnv("DB_USER", "root"),
		Password: getEnv("DB_PASSWORD", "password"),
		DBName:   getEnv("DB_NAME", "productdb"),
	}

	// Connect to database
	log.Println("Connecting to database...")
	db, err := database.NewDB(dbConfig)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Create server
	server := NewServer(db)

	// Setup routes
	router := mux.NewRouter()

	// Apply middleware
	router.Use(LoggingMiddleware)
	router.Use(RecoveryMiddleware)

	// Product endpoints (existing)
	router.HandleFunc("/products/{productId:[0-9]+}", server.HandleGetProduct).Methods("GET")
	router.HandleFunc("/products/{productId:[0-9]+}/details", server.HandleAddProductDetails).Methods("POST")

	// Shopping cart endpoints (new)
	router.HandleFunc("/shopping-carts", server.HandleCreateCart).Methods("POST")
	router.HandleFunc("/shopping-carts/{id:[0-9]+}", server.HandleGetCart).Methods("GET")
	router.HandleFunc("/shopping-carts/{id:[0-9]+}/items", server.HandleAddItemToCart).Methods("POST")
	
	// Customer cart history endpoint
	router.HandleFunc("/customers/{customerId:[0-9]+}/carts", server.HandleGetCustomerCarts).Methods("GET")

	// Health check endpoint
	router.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		// Check database connectivity
		if err := db.HealthCheck(); err != nil {
			log.Printf("Health check failed: %v", err)
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("Database unavailable"))
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	}).Methods("GET")

	// Start server
	port := getEnv("PORT", "8080")
	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		log.Printf("Starting server on port %s", port)
		log.Printf("Initial products seeded: 3 products available (IDs: 1, 2, 3)")
		log.Printf("Database: %s@%s:%s/%s", dbConfig.User, dbConfig.Host, dbConfig.Port, dbConfig.DBName)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	<-done
	log.Println("Server stopping...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited gracefully")
}