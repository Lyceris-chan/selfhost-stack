import subprocess
from typing import List, Optional
import shlex
from .logging import log_structured

def run_command(cmd: List[str], timeout: int = 30, cwd: Optional[str] = None, check: bool = False, capture_output: bool = True):
    """
    Safe wrapper for subprocess.run.
    """
    try:
        # Sanity check: Ensure cmd is a list of strings
        if isinstance(cmd, str):
            # If a string is passed, we shouldn't use shell=True blindly.
            # But strictly split it if it's meant to be a list.
            # Ideally callers should pass a list.
            cmd = shlex.split(cmd)

        res = subprocess.run(
            cmd,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
            cwd=cwd,
            check=check
        )
        return res
    except subprocess.CalledProcessError as e:
        log_structured("ERROR", f"Command failed: {cmd} - {e.stderr}", "SYSTEM")
        raise e
    except subprocess.TimeoutExpired as e:
        log_structured("ERROR", f"Command timed out: {cmd}", "SYSTEM")
        raise e
    except Exception as e:
        log_structured("ERROR", f"Command execution error: {cmd} - {str(e)}", "SYSTEM")
        raise e

def sanitize_service_name(name: str) -> Optional[str]:
    """Sanitize service name to prevent command injection."""
    if not name or not isinstance(name, str):
        return None
    sanitized = "".join([c for c in name if c.isalnum() or c in ('-', '_')])
    return sanitized if sanitized else None
