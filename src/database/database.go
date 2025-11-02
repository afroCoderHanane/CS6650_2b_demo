package database

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	_"github.com/go-sql-driver/mysql"
)

// Config holds database configuration
type Config struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
}

// DB wraps sql.DB with additional functionality
type DB struct {
	*sql.DB
}

// NewDB creates a new database connection with connection pooling
func NewDB(config Config) (*DB, error) {
	// Build DSN (Data Source Name)
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&charset=utf8mb4",
		config.User,
		config.Password,
		config.Host,
		config.Port,
		config.DBName,
	)

	// Open database connection
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Configure connection pool for 100 concurrent sessions
	db.SetMaxOpenConns(25)                 // Maximum open connections
	db.SetMaxIdleConns(10)                 // Keep idle connections ready
	db.SetConnMaxLifetime(5 * time.Minute) // Recycle connections periodically
	db.SetConnMaxIdleTime(2 * time.Minute) // Close idle connections

	// Verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Printf("Database connected successfully: %s:%s/%s", config.Host, config.Port, config.DBName)
	return &DB{db}, nil
}

// Close closes the database connection
func (db *DB) Close() error {
	log.Println("Closing database connection")
	return db.DB.Close()
}

// HealthCheck verifies database connectivity
func (db *DB) HealthCheck() error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return db.PingContext(ctx)
}
