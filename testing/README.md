# Testing Commands

This folder contains all testing commands for the Shared GraphQL API system. All commands accept tier and environment parameters to test any of the three GraphQL tiers (admin, operator, member) in either development or production environments.

## Command Structure

All test commands follow the pattern:
```bash
./command.sh <tier> <environment> [options]
```

Where:
- `tier` = `admin`, `operator`, or `member`
- `environment` = `development` or `production`
- `[options]` = Command-specific options

## Available Test Commands

### Connection Testing
- **test-connection.sh** - Basic connectivity test
  ```bash
  ./test-connection.sh admin development
  ```

- **test-connections.sh** - Comprehensive connection test with performance metrics
  ```bash
  ./test-connections.sh operator production --verbose
  ```

### Data Testing
- **test-comprehensive-dataset.sh** - Full dataset validation and relationship testing
  ```bash
  ./test-comprehensive-dataset.sh member development --quick
  ```

- **test-graphql.sh** - Complete 4-step test workflow (purge → load → verify → purge)
  ```bash
  ./test-graphql.sh admin development
  ```

### Performance Testing
- **speed-test-graphql.sh** - Performance benchmarking and speed tests
  ```bash
  ./speed-test-graphql.sh operator compare  # Compare dev vs prod
  ```

### Test Data Management
- **load-test-data.sh** - Load test data into database
  ```bash
  ./load-test-data.sh member development
  ```

- **purge-test-data.sh** - Remove test data from database
  ```bash
  ./purge-test-data.sh admin production --force
  ```

## Test Workflow

The standard test workflow is:
1. **Purge** - Clean existing test data
2. **Load** - Insert fresh test data
3. **Verify** - Run comprehensive tests
4. **Purge** - Clean up after testing

This workflow is automated in `test-graphql.sh`:
```bash
./test-graphql.sh operator development  # Runs all 4 steps
```

## Configuration Source

All test commands load configuration from the child repositories:
- `admin-graqhql-api/config/`
- `operator-graqhql-api/config/`
- `member-graqhql-api/config/`

Test data is loaded from:
- `admin-graqhql-api/testing/data/`
- `operator-graqhql-api/testing/data/`
- `member-graqhql-api/testing/data/`

## Performance Targets

- Connection tests: < 2 seconds
- Data loading: < 30 seconds
- Comprehensive tests: < 60 seconds
- Speed benchmarks: < 5 seconds per test

## Safety Features

- Production operations require confirmation
- `--force` flag skips confirmations
- Purge operations show clear warnings
- All tests are read-only except data management commands