#!/usr/bin/env python3
"""Management CLI for the Privacy Hub stack.

This script provides an interactive and command-line interface for deploying,
updating, and resetting the Privacy Hub environment.
"""

import argparse
import os
import subprocess
import sys

# ANSI Colors
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
RESET = "\033[0m"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
INSTALL_SCRIPT = os.path.join(PROJECT_ROOT, "zima.sh")


def print_banner():
    """Prints the application banner to the console."""
    print(f"{CYAN}")
    print("==========================================================")
    print(" 🛡️  PRIVACY HUB MANAGER")
    print("==========================================================")
    print(f"{RESET}")


def run_install(args):
    """Executes the zima.sh installation script with provided arguments.

    Args:
        args: Parsed command-line arguments containing deployment options.
    """
    cmd = [INSTALL_SCRIPT]
    if args.auto:
        cmd.append("-y")
    if args.clean:
        cmd.append("-c")
    if args.nuke:
        cmd.append("-x")
    if args.services:
        cmd.append(f"-s {args.services}")

    print(f"{GREEN}Starting deployment...{RESET}")
    # Replace current process with the bash script to handle TTY correctly
    os.execv(INSTALL_SCRIPT, cmd)


def main():
    """Main entry point for the management CLI."""
    parser = argparse.ArgumentParser(description="Privacy Hub Management CLI")
    parser.add_argument("--install", action="store_true", help="Run the installer")
    parser.add_argument("-y", "--auto", action="store_true", help="Auto-confirm")
    parser.add_argument("-c", "--clean", action="store_true", help="Clean environment before install")
    parser.add_argument("-x", "--nuke", action="store_true", help="Factory reset (Data Loss!)")
    parser.add_argument("-s", "--services", help="Comma-separated list of services to deploy")

    if len(sys.argv) == 1:
        # Interactive Mode
        print_banner()
        print("1. Install / Update Stack")
        print("2. Factory Reset (Clean All Data)")
        print("3. Exit")
        print("")
        choice = input("Select an option [1-3]: ").strip()

        if choice == "1":
            run_install(parser.parse_args(["--install"]))
        elif choice == "2":
            confirm = input(f"{RED}WARNING: This will delete ALL data. Are you sure? [y/N]: {RESET}")
            if confirm.lower() in ["y", "yes"]:
                run_install(parser.parse_args(["--nuke"]))
            else:
                print("Aborted.")
        elif choice == "3":
            sys.exit(0)
        else:
            print("Invalid choice.")
    else:
        args = parser.parse_args()
        if args.install or args.nuke:
            run_install(args)
        else:
            parser.print_help()

if __name__ == "__main__":
    main()
