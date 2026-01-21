#!/bin/bash
#
# Static verification module for ZimaOS Privacy Hub.
# Performs code integrity checks, syntax validation, and configuration presence checks.
#
# Globals:
#   PROJECT_ROOT

set -euo pipefail

# Check for duplicates in specific files
# Arguments:
#   File path
#   Search string
#   Max allowed occurrences
check_duplicate_strings() {
  local file_path="$1"
  local search_string="$2"
  local max_count="$3"
  local count

  if [[ -f "${file_path}" ]]; then
    count=$(grep -c "${search_string}" "${file_path}" || true)
    if (( count > max_count )); then
      echo "❌ Duplicate '${search_string}' found in $(basename "${file_path}") (Count: ${count})" >&2
      return 1
    fi
  fi
  return 0
}

# Validate shell script syntax
# Arguments:
#   Directory to scan
validate_shell_syntax() {
  local dir_path="$1"
  local failed=0

  echo "  Checking syntax in ${dir_path}..."
  
  while IFS= read -r script; do
    if ! bash -n "${script}" 2>/dev/null; then
      echo "  ❌ Syntax error in $(basename "${script}")" >&2
      failed=1
    else
      echo "    ✓ $(basename "${script}")"
    fi
  done < <(find "${dir_path}" -maxdepth 1 -name "*.sh")

  return "${failed}"
}

# Main static verification logic
main() {
  local project_root="${1:-.}"
  local exit_code=0

  echo "Running static verification..."

  # 1. Essential File Checks
  local files_to_check=(
    "zima.sh"
    "README.md"
    "lib/core/core.sh"
    "lib/templates/dashboard.html"
    "lib/templates/wg_control.sh"
  )

  for file in "${files_to_check[@]}"; do
    if [[ ! -f "${project_root}/${file}" ]]; then
      echo "❌ Missing file: ${file}" >&2
      exit_code=1
    else
      echo "  ✓ Found ${file}"
    fi
  done

  # 2. Logic/Content Checks
  # Check for duplicate "Pre-Pulling" logs in images.sh (regression test)
  if ! check_duplicate_strings "${project_root}/lib/services/images.sh" "Pre-Pulling" 1; then
    exit_code=1
  fi

  # Check for critical functions in service scripts
  if ! grep -q "deploy_stack" "${project_root}/lib/services/deploy.sh"; then
    echo "❌ Missing 'deploy_stack' in lib/services/deploy.sh" >&2
    exit_code=1
  else
    echo "  ✓ Found 'deploy_stack' in deploy.sh"
  fi

  if ! grep -q "generate_compose" "${project_root}/lib/services/compose.sh"; then
    echo "❌ Missing 'generate_compose' in lib/services/compose.sh" >&2
    exit_code=1
  else
    echo "  ✓ Found 'generate_compose' in compose.sh"
  fi

  # 3. Syntax Validation
  if ! validate_shell_syntax "${project_root}/lib/core"; then
    exit_code=1
  fi
  if ! validate_shell_syntax "${project_root}/lib/services"; then
    exit_code=1
  fi

  if (( exit_code == 0 )); then
    echo "✅ Static verification passed"
  else
    echo "❌ Static verification failed"
  fi

  return "${exit_code}"
}

# Allow sourcing or execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$(pwd)"
fi
