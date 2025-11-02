"""
Locust Load Test for Shopping Cart API
CS6650 - MySQL Performance Testing

Run with:
    locust -f locustfile.py --host=http://localhost:8080 --headless --users=100 --spawn-rate=10 --run-time=2m
"""

from locust import HttpUser, task, between, events
import json
import random
import time
from datetime import datetime, timezone
import threading

# Results storage
results_lock = threading.Lock()
test_results = []

# Operation counters
operation_counts = {
    "create_cart": 0,
    "add_items": 0,
    "get_cart": 0
}
MAX_OPERATIONS = 50  # 50 of each type

# Shared cart IDs
cart_ids = []
cart_ids_lock = threading.Lock()


def save_result(operation, response_time, success, status_code):
    """Save a test result in the required format"""
    with results_lock:
        result = {
            "operation": operation,
            "response_time": round(response_time, 2),
            "success": success,
            "status_code": status_code,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        test_results.append(result)


class ShoppingCartUser(HttpUser):
    """
    Simulates a user performing shopping cart operations
    Tasks weighted to achieve 50 of each operation type
    """
    wait_time = between(0.1, 0.5)
    
    @task(3)
    def create_cart(self):
        """Create a new shopping cart"""
        with results_lock:
            if operation_counts["create_cart"] >= MAX_OPERATIONS:
                return
            operation_counts["create_cart"] += 1
        
        customer_id = random.randint(1, 100000)
        start_time = time.time()
        
        try:
            with self.client.post(
                "/shopping-carts",
                json={
                    "customerId": customer_id,
                    "customerName": f"Customer {customer_id}",
                    "customerEmail": f"customer{customer_id}@example.com"
                },
                name="POST /shopping-carts",
                catch_response=True
            ) as response:
                response_time = (time.time() - start_time) * 1000
                success = response.status_code == 201
                
                if success:
                    cart_data = response.json()
                    cart_id = cart_data["id"]
                    with cart_ids_lock:
                        cart_ids.append(cart_id)
                    response.success()
                else:
                    response.failure(f"Expected 201, got {response.status_code}")
                
                save_result("create_cart", response_time, success, response.status_code)
                
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            save_result("create_cart", response_time, False, 0)
            print(f"Error creating cart: {e}")
    
    @task(3)
    def add_item_to_cart(self):
        """Add an item to an existing cart"""
        with results_lock:
            if operation_counts["add_items"] >= MAX_OPERATIONS:
                return
            operation_counts["add_items"] += 1
        
        # Wait until we have at least one cart
        with cart_ids_lock:
            if not cart_ids:
                with results_lock:
                    operation_counts["add_items"] -= 1
                return
            cart_id = random.choice(cart_ids)
        
        product_id = random.randint(1, 5)
        quantity = random.randint(1, 10)
        start_time = time.time()
        
        try:
            with self.client.post(
                f"/shopping-carts/{cart_id}/items",
                json={
                    "productId": product_id,
                    "quantity": quantity
                },
                name="POST /shopping-carts/{id}/items",
                catch_response=True
            ) as response:
                response_time = (time.time() - start_time) * 1000
                success = response.status_code == 204
                
                if success:
                    response.success()
                else:
                    response.failure(f"Expected 204, got {response.status_code}")
                
                save_result("add_items", response_time, success, response.status_code)
                
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            save_result("add_items", response_time, False, 0)
            print(f"Error adding item: {e}")
    
    @task(3)
    def get_cart(self):
        """Retrieve a cart with all items"""
        with results_lock:
            if operation_counts["get_cart"] >= MAX_OPERATIONS:
                return
            operation_counts["get_cart"] += 1
        
        # Wait until we have at least one cart
        with cart_ids_lock:
            if not cart_ids:
                with results_lock:
                    operation_counts["get_cart"] -= 1
                return
            cart_id = random.choice(cart_ids)
        
        start_time = time.time()
        
        try:
            with self.client.get(
                f"/shopping-carts/{cart_id}",
                name="GET /shopping-carts/{id}",
                catch_response=True
            ) as response:
                response_time = (time.time() - start_time) * 1000
                success = response.status_code == 200
                
                if success:
                    # Check if meets <50ms requirement
                    if response_time >= 50:
                        print(f"Warning: GET cart response time {response_time:.2f}ms exceeds 50ms target")
                    response.success()
                else:
                    response.failure(f"Expected 200, got {response.status_code}")
                
                save_result("get_cart", response_time, success, response.status_code)
                
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            save_result("get_cart", response_time, False, 0)
            print(f"Error getting cart: {e}")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Called when test starts"""
    print("=" * 60)
    print("MySQL Shopping Cart Performance Test")
    print("=" * 60)
    print(f"Target: {environment.host}")
    print(f"Start Time: {datetime.now().isoformat()}")
    print(f"Target: 150 operations (50 create, 50 add items, 50 get cart)")
    print("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Called when test stops - save results to JSON file"""
    print("\n" + "=" * 60)
    print("Saving results to mysql_test_results.json...")
    print("=" * 60)
    
    # Save to JSON file
    with open("mysql_test_results.json", "w") as f:
        json.dump(test_results, f, indent=2)
    
    # Print summary
    print(f"\nTotal operations recorded: {len(test_results)}")
    
    for op_type in ["create_cart", "add_items", "get_cart"]:
        ops = [r for r in test_results if r["operation"] == op_type]
        if ops:
            successful = [r for r in ops if r["success"]]
            avg_time = sum(r["response_time"] for r in ops) / len(ops)
            min_time = min(r["response_time"] for r in ops)
            max_time = max(r["response_time"] for r in ops)
            
            print(f"\n{op_type}:")
            print(f"  Count: {len(ops)}")
            print(f"  Successful: {len(successful)}")
            print(f"  Avg Response Time: {avg_time:.2f}ms")
            print(f"  Min: {min_time:.2f}ms")
            print(f"  Max: {max_time:.2f}ms")
            
            if op_type == "get_cart" and avg_time < 50:
                print(f"  ✓ Meets <50ms requirement")
            elif op_type == "get_cart":
                print(f"  ✗ Exceeds 50ms requirement")
    
    print("\n" + "=" * 60)
    print("Results saved to: mysql_test_results.json")
    print("=" * 60)


@events.quitting.add_listener
def on_quitting(environment, **kwargs):
    """Ensure results are saved even if test is interrupted"""
    if test_results:
        with open("mysql_test_results.json", "w") as f:
            json.dump(test_results, f, indent=2)
        print(f"\nResults saved: {len(test_results)} operations")