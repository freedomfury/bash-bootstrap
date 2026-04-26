# Bashunit Cheat Sheet for bash-bootstrap Project

**AI Reference:** Quick guide for writing unit tests for this Bash 5.3+ monolithic project.

---

## Quick Start

```bash
# Run tests (vendored bashunit)
vendor/bin/dev/bashunit

# Run specific test file
vendor/bin/dev/bashunit tests/unit/logger_test.sh
```

---

## Test File Template

```bash
#!/usr/bin/env bash
# tests/unit/logger_test.sh

function set_up() {
  # Source the library under test
  source "lib/std/logger.sh"
  # Set up test environment
  export TEST_LOG="/tmp/test_$$_$RANDOM.log"
}

function tear_down() {
  # Clean up
  rm -f "$TEST_LOG"
}

function test_descriptive_name() {
  # Arrange, Act, Assert
  lib::std::logger -l info -m "test message"
  
  assert_file_contains "test message" "$TEST_LOG"
}
```

---

## Essential Assertions

### String/Value Assertions
```bash
assert_same "expected" "actual"              # Exact match including special chars
assert_equals "expected" "actual"            # Ignores ANSI colors, tabs, newlines
assert_contains "needle" "haystack"          # Substring check
assert_matches "^pattern$" "value"           # Regex match
assert_empty ""                              # Empty string
assert_not_empty "value"                     # Non-empty string
```

### Boolean/Exit Code Assertions
```bash
assert_true true                             # Success (exit 0)
assert_false false                            # Failure (non-zero)
assert_successful_code                       # Last command exited 0
assert_general_error                         # Last command exited 1
assert_exit_code "127"                       # Specific exit code
```

### File System Assertions
```bash
assert_file_exists "/path/to/file"           # File exists and is not a directory
assert_file_contains "/path" "search"        # File contains string
assert_is_file "/path"                       # Is a file (not directory)
assert_is_file_empty "/path"                 # File is empty
assert_directory_exists "/path"              # Directory exists
assert_is_directory "/path"                  # Is a directory
assert_is_directory_empty "/path"            # Directory is empty
assert_files_equals "/expected" "/actual"    # File contents match
```

### Array Assertions
```bash
local arr=(foo bar baz)
assert_array_contains "bar" "${arr[@]}"      # Array contains element
```

### JSON Assertions (requires jq)
```bash
assert_json_key_exists ".name" '{"name":"test"}'
assert_json_contains ".count" "42" '{"count":42}'
assert_json_equals '{"a":1}' '{"a":1}'      # Ignores key order
```

---

## Mocking External Commands

### Mock with Simple Output
```bash
function test_with_mocked_command() {
  # Mock 'date' to return fixed value
  bashunit::mock date <<< "2024-01-01"
  
  local result
  result=$(date)
  assert_same "2024-01-01" "$result"
}
```

### Mock with Multi-line Output
```bash
function test_with_multi_line_mock() {
  bashunit::mock ps <<EOF
PID TTY          TIME CMD
13525 pts/7    00:00:01 bash
24162 pts/7    00:00:00 ps
EOF

  local output
  output=$(ps)
  assert_contains "bash" "$output"
}
```

### Mock with Function Behavior
```bash
function test_with_conditional_mock() {
  # Define mock function that behaves differently based on args
  function mock_age() {
    if [[ "$1" == "--version" ]]; then
      echo "age 1.1.1"
      return 0
    fi
    echo "age: unknown option" >&2
    return 1
  }

  bashunit::mock age mock_age

  age --version
  assert_successful_code
  assert_contains "1.1.1" "$(age --version)"
}
```

---

## Spies - Verify Function Calls

```bash
function test_spy_usage() {
  # Create spy on function
  bashunit::spy docker
  
  # Call code that uses docker
  deploy_image "myapp:latest"
  
  # Assert it was called
  assert_have_been_called docker
  
  # Assert called with specific args
  assert_have_been_called_with docker "push myapp:latest"
  
  # Assert called N times
  assert_have_been_called_times 2 docker
  
  # Assert specific invocation
  assert_have_been_called_nth_with 1 docker "pull myapp:latest"
}

function test_spy_not_called() {
  bashunit::spy age
  
  # Should not have called age
  assert_not_called age
}
```

---

## Testing Exit Codes

```bash
function test_exit_code_pattern() {
  # Method 1: assert_exec (all-in-one)
  assert_exec "lib::std::logger -l info -m test" --exit 0
  
  # Method 2: Run then check
  lib::std::logger -l info -m test
  assert_successful_code
  
  # Method 3: Capture then check
  local exit_code=0
  lib::std::logger -l invalid-option || exit_code=$?
  assert_not_equals "0" "$exit_code"
}
```

---

## Testing with stdout/stderr

```bash
function test_output_captured() {
  local output
  output=$(lib::std::logger -l info -m "test message" 2>&1)
  
  assert_contains "INFO" "$output"
  assert_contains "test message" "$output"
}

function test_error_message() {
  local output
  output=$(lib::std::secrets::encrypt -s /missing -t /out 2>&1 || true)
  
  assert_contains "source file not found" "$output"
}
```

---

## Data Providers - Parameterized Tests

```bash
# Define data provider
function data_provider_valid_log_levels() {
  echo "debug"
  echo "info"
  echo "warn"
  echo "error"
}

# Test function receives each line as $1
function test_logger_accepts_valid_levels() {
  local level="$1"
  
  # Should not fail
  lib::std::logger -l "$level" -m "test"
  assert_successful_code
}
```

---

## Project-Specific Patterns

### Testing lib::std::* Namespaced Functions

```bash
function test_namespaced_function() {
  source "lib/std/logger.sh"
  
  # Call namespaced function
  lib::std::logger -l info -m "test"
  
  assert_successful_code
}
```

### Testing with MKS_ROOT Environment

```bash
function set_up() {
  # Ensure environment is set
  [[ -n "${MKS_ROOT:-}" ]] || { echo "MKS_ROOT not set" >&2; return 3; }
  
  source "${MKS_ROOT}/lib/std/logger.sh"
}
```

### Testing Secrets (with age mock)

```bash
function test_encrypt_with_mocked_age() {
  source "lib/std/secrets.sh"
  
  # Mock age to avoid actual encryption
  bashunit::mock age <<'EOF'
AGE_ENCRYPTED_CONTENT
EOF

  local test_file="/tmp/test_secret_$$_$RANDOM.txt"
  echo "secret data" > "$test_file"
  local output="/tmp/test_output_$$_$RANDOM.age"
  
  lib::std::secrets::encrypt -s "$test_file" -t "$output"
  
  assert_successful_code
  assert_file_exists "$output"
  
  rm -f "$test_file" "$output"
}
```

### Testing Error Conditions

```bash
function test_logger_handles_unknown_level() {
  local output
  output=$(lib::std::logger -l "invalid" -m "test" 2>&1 || true)
  
  # Should still work (defaults to INFO)
  assert_contains "INFO" "$output"
}
```

---

## Lifecycle Hooks

```bash
# Runs once before all tests in file
function set_up_before_script() {
  export COMMON_FIXTURE="/tmp/shared_$$"
  mkdir -p "$COMMON_FIXTURE"
}

# Runs before each test
function set_up() {
  export TEST_FILE="/tmp/test_$$_$RANDOM"
  touch "$TEST_FILE"
}

# Runs after each test
function tear_down() {
  rm -f "$TEST_FILE"
}

# Runs once after all tests in file
function tear_down_after_script() {
  rm -rf "$COMMON_FIXTURE"
}
```

---

## Test Naming Conventions

```bash
# File naming: <module>_test.sh
tests/unit/logger_test.sh
tests/integration/secrets_test.sh

# Function naming: test_* prefix, descriptive
function test_logger_outputs_to_stderr() { }        # Good
function testLogger() { }                            # Avoid (no prefix)
function test() { }                                  # Avoid (not descriptive)

# Custom test titles
function test_verbose_output() {
  set_test_title "verbose mode includes timestamp and caller"
  # ...
}
```

---

## Common Patterns

### Testing Function That Uses Environment Variables

```bash
function test_function_with_env_var() {
  export MKS_TMP="/tmp/custom_tmp"
  
  source "lib/std/secrets.sh"
  
  # Function uses MKS_TMP
  lib::std::secrets::decrypt -s "file.age"
  
  assert_successful_code
}
```

### Testing with Temporary Files/Directories

```bash
function set_up() {
  export TEST_DIR="/tmp/bashunit_test_$$"
  mkdir -p "$TEST_DIR"
}

function tear_down() {
  rm -rf "$TEST_DIR"
}

function test_file_operations() {
  touch "$TEST_DIR/test.txt"
  echo "content" > "$TEST_DIR/test.txt"
  
  assert_file_exists "$TEST_DIR/test.txt"
  assert_file_contains "content" "$TEST_DIR/test.txt"
}
```

---

## Running Specific Tests

```bash
# Run all tests
vendor/bin/dev/bashunit

# Run specific directory
vendor/bin/dev/bashunit tests/unit/

# Run specific file
vendor/bin/dev/bashunit tests/unit/logger_test.sh

# Run with filter
vendor/bin/dev/bashunit --filter "logger" tests/

# Run with parallel execution
BASHUNIT_PARALLEL_RUN=true vendor/bin/dev/bashunit tests/
```

---

## Key bashunit Features for This Project

| Feature | Usage |
|---------|-------|
| `assert_same` | Exact string matching (including ANSI codes) |
| `assert_equals` | String matching ignoring colors/formatting |
| `bashunit::mock` | Mock external commands (age, git, etc.) |
| `bashunit::spy` | Verify functions called correctly |
| `assert_exec` | Run command + check exit/stdout/stderr together |
| `assert_json_*` | Test JSON output (requires jq) |
| Data providers | Parameterized tests for multiple inputs |

---

## Project Test File Structure

```
tests/
├── unit/                    # Tests for individual lib/* files
│   ├── logger_test.sh
│   ├── secrets_test.sh
│   └── rmrf_test.sh
├── integration/             # End-to-end tests for bin/ executables
│   └── (future)
└── fixtures/                # Static test data
    ├── input/
    └── expected/
```
