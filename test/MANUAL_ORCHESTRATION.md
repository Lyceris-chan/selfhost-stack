# Manual Orchestration Instructions

Due to environment restrictions preventing script execution, the automated deployment must be started manually. 

I have prepared a complete batch processing system that meets your requirements:
- **Small Batches**: Deployment is split into 4 batches/stages.
- **State Tracking**: `test/deployment_todos.json` tracks the status of each batch.
- **Crash Recovery**: If the system stops, running the orchestrator again will resume from the last pending task.
- **Logging**: Detailed logs are written to `test/progress.log` and individual `test/stage_X.log` files.

## Steps to Run

1.  **Make Scripts Executable**
    Run the following command to ensure all scripts have execution permissions:
    ```bash
    chmod +x zima.sh test/manual_verification.sh test/orchestrator.py lib/*.sh
    ```

2.  **Start the Orchestrator**
    Run the manual verification script:
    ```bash
    test/manual_verification.sh
    ```
    Or run the Python orchestrator script directly from the project root:
    ```bash
    python3 test/orchestrator.py
    ```

3.  **Monitor Progress**
    - The script will print progress to the console.
    - Check `test/progress.log` for a summary.
    - Check `test/deployment_todos.json` to see the current state of tasks.

## Batches

- **Stage 1**: Core Infrastructure (Hub, AdGuard, Unbound).
- **Stage 2**: Redlib & Privacy Frontends A.
- **Stage 3**: Invidious Stack.
- **Stage 4**: Management Tools.

## Configuration
All configuration has been pre-loaded into `test/test_config.env` matching the `details` file provided.