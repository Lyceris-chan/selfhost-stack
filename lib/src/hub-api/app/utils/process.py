"""Shell command execution and input sanitization utilities for the Privacy Hub API.

This module provides safe wrappers around subprocess and helper functions
to sanitize service names before processing.
"""

import shlex
import subprocess
from typing import List, Optional

from .logging import log_structured


def run_command(cmd: List[str],
                timeout: int = 30,
                cwd: Optional[str] = None,
                check: bool = False,
                capture_output: bool = True):
    """Executes a shell command safely using subprocess.run.

    Args:
        cmd: The command to execute as a list of strings.
        timeout: Maximum execution time in seconds.
        cwd: The directory to execute the command in.
        check: If True, raises CalledProcessError on non-zero exit.
        capture_output: If True, captures stdout and stderr.

    Returns:
        A completed process object.

    Raises:
        subprocess.CalledProcessError: If the command fails and check=True.
        subprocess.TimeoutExpired: If the command times out.
    """
    try:
        # Sanity check: Ensure cmd is a list of strings
        if isinstance(cmd, str):
            cmd = shlex.split(cmd)

        res = subprocess.run(
            cmd,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
            cwd=cwd,
            check=check)
        return res
    except subprocess.CalledProcessError as err:
        log_structured("ERROR", f"Command failed: {cmd} - {err.stderr}", "SYSTEM")
        raise err
    except subprocess.TimeoutExpired as err:
        log_structured("ERROR", f"Command timed out: {cmd}", "SYSTEM")
        raise err
    except Exception as err:
        log_structured("ERROR",
                       f"Command execution error: {cmd} - {str(err)}", "SYSTEM")
        raise err


def sanitize_service_name(name: str) -> Optional[str]:
    """Sanitizes a service name to prevent command injection.

    Args:
        name: The raw service name string.

    Returns:
        A sanitized alphanumeric name, or None if invalid.
    """
    if not name or not isinstance(name, str):
        return None
    sanitized = "".join([c for c in name if c.isalnum() or c in ('-', '_')])
    return sanitized if sanitized else None
