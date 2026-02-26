import subprocess
import threading
import time

NUM_CONCURRENT = 20
results = {}

def execute_transaction(tx_id):
    start = time.time()
    # Execute a transaction that locks the row, sleeps for 0.5 sec, then updates.
    sql = """
    BEGIN;
    SELECT * FROM operational.loans WHERE loan_id = 1 FOR UPDATE;
    SELECT pg_sleep(0.5);
    UPDATE operational.loans SET outstanding_balance = outstanding_balance - 1 WHERE loan_id = 1;
    COMMIT;
    """
    cmd = [
        "docker", "exec", "-i", "eds_postgres_primary", "psql", "-U", "postgres", "-d", "loans_db", "-c", sql
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    results[tx_id] = time.time() - start

print(f"Starting {NUM_CONCURRENT} concurrent transactions competing for the SAME row lock...")
threads = []
for i in range(NUM_CONCURRENT):
    t = threading.Thread(target=execute_transaction, args=(i+1,))
    threads.append(t)

for t in threads:
    t.start()

for t in threads:
    t.join()

print("\nAll 20 transactions completed.")
print("Because they all updated the SAME row, PostgreSQL forced them to wait in a queue (Row-level Locking).")
print("\n--- Concurrency Lock Wait Times Graph ---")

sorted_tx = sorted(results.items(), key=lambda x: x[1])
max_time = max(results.values()) if results else 1

for rank, (tx_id, duration) in enumerate(sorted_tx):
    bar_len = int((duration / max_time) * 50)
    bar = '█' * bar_len
    print(f"Finish #{rank+1:02d} (Tx {tx_id:02d}) | {bar} {duration:.2f}s")
