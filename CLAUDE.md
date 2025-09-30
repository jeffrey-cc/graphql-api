# GraphQL API - Testing Commands

## Testing Methodology - CRITICAL

**⚠️ NEVER USE MANUAL CURL COMMANDS FOR TESTING**

Always use the provided test scripts. They are:
- **Repeatable**: Anyone can run the exact same commands
- **Documented**: Scripts have `--help` flags and are version controlled
- **Comprehensive**: Test multiple aspects of the system
- **Maintainable**: Update automatically when schema changes
- **Source of Truth**: Define what "working" means

Manual curl commands are one-off, undocumented tests that aren't repeatable or maintainable.

## Testing GraphQL Services

The GraphQL API has comprehensive testing scripts located in `./testing/`:

### Available Test Commands

```bash
# Test GraphQL connection (quick verification)
./testing/test-connection.sh <tier> <environment>

# Run complete test workflow (PURGE � LOAD � VERIFY � PURGE)
./testing/test-graphql.sh <tier> <environment>

# Load test data without purging
./testing/load-test-data.sh <tier> <environment>

# Purge all data (keeps schema)
./testing/purge-test-data.sh <tier> <environment>
```

### Examples

```bash
# Test admin GraphQL connection
./testing/test-connection.sh admin development

# Run full admin GraphQL test suite
./testing/test-graphql.sh admin development

# Test without data cleanup (for debugging)
./testing/test-graphql.sh admin development --keep-data
```

### Important Notes

1. **Scripts work from any directory** - All paths are resolved automatically using absolute paths
2. **GraphQL must be running** - Start with `./commands/docker-start.sh <tier> development`
3. **Database must be accessible** - Ensure database is running first
4. **Admin secret is required** - Configured automatically from tier config files

### Testing Workflow

**Proper testing sequence:**

```bash
# 1. Database Layer
cd ~/Desktop/v3/database-sql/commands
./test-connection.sh admin development      # Verify database is running
./report-database.sh admin development      # Check data is present

# 2. GraphQL Layer - Connection Only
cd ~/Desktop/v3/graphql-api/testing
./test-connection.sh admin development      # 5 connection tests (health, version, endpoints)

# 3. GraphQL Layer - Full Test Suite
./test-graphql.sh admin development         # Complete PURGE → LOAD → VERIFY → PURGE workflow
# OR for debugging without cleanup:
./test-graphql.sh admin development --skip-purge --keep-data
```

**What Each Test Validates:**

1. **test-connection.sh**: Quick smoke test (health, version, GraphQL endpoint, metadata, database)
2. **test-graphql.sh**: **COMPREHENSIVE** integration test including:
   - GraphQL introspection (schema structure)
   - Tier-specific table queries
   - Mutations capability
   - Subscriptions capability
   - **Relationship verification across ALL schemas**
   - Total relationship count and health check
3. **report-database.sh**: Data verification (record counts, schema structure)

**Test Coverage:**

The `test-graphql.sh` script now verifies relationships for ALL schemas in the tier:
- **Admin**: admin, operators, system, financial, sales, support, compliance, integration (8 schemas)
- **Operator**: identity, operations, access, assets, financial, sales, communications, documents, integration, support, memberships (11 schemas)
- **Member**: member, profile, membership, payments, bookings, usage, communications, integration (8 schemas)

For detailed relationship inspection of a single schema, use:
```bash
cd ~/Desktop/v3/graphql-api/commands
./verify-schema.sh <tier> <environment> <schema> --detailed
```

## Recent Fixes

**2025-09-29**: Fixed comprehensive path resolution and naming issues across the testing system:

### Core Path Fixes
- **`_shared_functions.sh`**: Changed `TIER_REPOSITORY_PATH` from relative `./${tier}-graphql-api` to absolute `$SHARED_ROOT/${tier}-graphql-api`
- **`test-graphql.sh`**: Added missing `configure_endpoint()` call to properly set `GRAPHQL_TIER_ENDPOINT`
- **`load-test-data.sh`**:
  - Changed from using local `TIER_REPO_PATH` to shared `TIER_REPOSITORY_PATH`
  - Fixed database directory path calculation to use absolute path
  - Changed loader from SQL-based to CSV-based (`load-test-data-csv.sh`)
  - Fixed invocation to call CSV loader instead of SQL loader
- **`purge-test-data.sh`**: Changed from relative `../shared-database-sql` to absolute path calculation

### Naming Convention Fixes
- **Database Directories**: Fixed inconsistent naming from `database-{tier}-sql` to `{tier}-database-sql`
  - `load-test-data.sh` (database): Line 93-97
  - `load-test-data-csv.sh` (database): Line 155
  - `load-test-data.sh` (graphql): Line 153 (symlink path)
- **Repository References**: Updated all scripts to use correct `admin-database-sql`, `operator-database-sql`, `member-database-sql` format

### CSV Data Loading Enhancement
- **`load-test-data-csv.sh`**: Added logic to check for GraphQL symlinked test data (`test-data-graphql-temp`) before falling back to regular `test-data`

### Results
- Scripts now work from any directory
- Test data loads successfully via GraphQL testing framework
- All path resolution is deterministic and absolute
- Zero "Environment file not found" or "Cannot connect" errors
- Data purge and reload works end-to-end