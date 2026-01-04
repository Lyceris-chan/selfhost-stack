import json
import subprocess
import sys
import os
import time
from datetime import datetime

# Determine the directory where this script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TODO_FILE = os.path.join(SCRIPT_DIR, "deployment_todos.json")
PROGRESS_LOG = os.path.join(SCRIPT_DIR, "progress.log")

def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted_message = f"[{timestamp}] {message}"
    print(formatted_message)
    with open(PROGRESS_LOG, "a") as f:
        f.write(formatted_message + "\n")

def load_todos():
    if not os.path.exists(TODO_FILE):
        log("Error: Todo file not found.")
        sys.exit(1)
    with open(TODO_FILE, "r") as f:
        return json.load(f)

def save_todos(todos):
    with open(TODO_FILE, "w") as f:
        json.dump(todos, f, indent=4)

def execute_task(task):
    log(f"Starting task: {task['description']}")
    
    # Update status to in_progress
    task['status'] = 'in_progress'
    todos = load_todos()
    for t in todos:
        if t['id'] == task['id']:
            t['status'] = 'in_progress'
    save_todos(todos)

    cmd = task['command']
    log_file_path = task['log_file']
    
    log(f"Executing: {cmd} > {log_file_path}")
    
    try:
        with open(log_file_path, "w") as log_f:
            process = subprocess.Popen(
                cmd, 
                shell=True, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.STDOUT,
                text=True
            )
            
            for line in process.stdout:
                print(line, end="")
                log_f.write(line)
                log_f.flush()
                
            process.wait()
            
        if process.returncode == 0:
            log(f"Task {task['id']} completed successfully.")
            task['status'] = 'completed'
        else:
            log(f"Task {task['id']} failed with exit code {process.returncode}. Check {log_file_path} for details.")
            task['status'] = 'failed'
            # We exit on failure to allow manual intervention or inspection
            todos = load_todos()
            for t in todos:
                if t['id'] == task['id']:
                    t['status'] = 'failed'
            save_todos(todos)
            sys.exit(1)

    except Exception as e:
        log(f"Exception during task execution: {e}")
        task['status'] = 'failed'
        todos = load_todos()
        for t in todos:
            if t['id'] == task['id']:
                t['status'] = 'failed'
        save_todos(todos)
        sys.exit(1)

    # Update status to completed
    todos = load_todos()
    for t in todos:
        if t['id'] == task['id']:
            t['status'] = 'completed'
    save_todos(todos)

def main():
    log("Orchestrator started.")
    todos = load_todos()
    
    start_time = time.time()
    TIME_LIMIT = 18 * 60  # 18 minutes in seconds

    for task in todos:
        if task['status'] == 'completed':
            log(f"Skipping completed task: {task['description']}")
            continue
        
        if task['status'] == 'failed':
             log(f"Found failed task: {task['description']}. Retrying...")
             # Optionally reset status or just proceed to execute
        
        # Check time limit
        if time.time() - start_time > TIME_LIMIT:
            log("Time limit approaching (18 minutes elapsed). Stopping execution to ensure clean shutdown state.")
            log("Please run the verification script again to resume from the next stage.")
            break

        execute_task(task)
        
    log("Orchestrator finished cycle.")

if __name__ == "__main__":
    main()
