# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Shared GraphQL API** repository - a unified command framework that manages GraphQL operations across three tiers (admin, operator, member) in the Community Connect Tech multi-tenant system. It provides parameterized commands that eliminate 95%+ code duplication and ensure consistency across all GraphQL API tiers.

## Hierarchical Context

### Position in System Architecture
- **Parent Directory**: `/Users/cc/Desktop/v3/` (Master orchestration folder for 12-repository system)
- **Current Location**: `/Users/cc/Desktop/v3/shared-graphql-api/` (Shared GraphQL command center)
- **Child Repositories**: 
  - `../admin-graqhql-api/` (Admin tier GraphQL API)
  - `../operator-graqhql-api/` (Operator tier GraphQL API)
  - `../member-graqhql-api/` (Member tier GraphQL API)
- **Sibling System**: `../shared-database-sql/` (Centralized database management)

### Role in Three-Tier Architecture
This repository serves as the **central nervous system** for all GraphQL operations across the platform:
- **Centralized Commands**: Single source of truth for GraphQL operations
- **Tier Abstraction**: Parameterized commands work across admin, operator, and member tiers
- **Integration Hub**: Coordinates with both database and portal layers
- **Standards Enforcement**: Ensures consistency in deployment, testing, and management

## Architecture

### Tier Configuration
The system manages three separate Hasura GraphQL APIs with clear sequential port numbering:

| Tier     | GraphQL Port | Container Name          | PostgreSQL Port | Admin Secret        |
|----------|--------------|-------------------------|-----------------|---------------------|
| admin    | 8101         | admin-graphql-server    | 7101           | CCTech2024Admin     |
| operator | 8102         | operator-graphql-server | 7102           | CCTech2024Operator  |
| member   | 8103         | member-graphql-server   | 7103           | CCTech2024Member    |

**Port Strategy**: 
- GraphQL APIs use sequential ports 8101-8103 for easy identification
- PostgreSQL databases use ports 7101-7103 to avoid conflicts with standard port 5432
- Consistent numbering makes it clear which services belong together

### Integration with Child Repositories
Each tier has its own repository (`admin-graqhql-api`, `operator-graqhql-api`, `member-graqhql-api`) that:
- Contains tier-specific metadata in `metadata/` directory (Hasura GraphQL metadata)
- Stores environment configs in `config/` directory (development.env, production.env)
- Includes testing data and scripts in `testing/` directory
- Maintains version information in `version/` directory with automated versioning system
- Uses wrapper commands that delegate to this shared repository
- Maintains their own CLAUDE.md with tier-specific business context
- No actions servers - pure Hasura GraphQL APIs using metadata-defined actions only

### Child Repository Command Pattern
Child repositories use wrapper commands that:
1. Load their local `config/shared-settings.env` configuration
2. Validate the shared system path exists (`../shared-graphql-api`)
3. Execute the shared command with their tier parameter
4. Example: `admin-graqhql-api/commands/deploy-graphql-shared.sh` → calls → `shared-graphql-api/commands/deploy-graphql.sh admin development`

## Deployment Process

### ⚠️ CRITICAL: Always Use Docker Compose
**GraphQL APIs MUST be deployed using docker-compose, NEVER standalone Docker containers.**

Hasura Cloud deployments use containerized deployments, not docker-compose apps. To maintain consistency between development and production, always use docker-compose locally.

### Local Development Deployment
```bash
# Deploy admin GraphQL API
cd admin-graqhql-api && docker-compose up -d

# Deploy operator GraphQL API  
cd operator-graqhql-api && docker-compose up -d

# Deploy member GraphQL API
cd member-graqhql-api && docker-compose up -d

# Stop any GraphQL API
docker-compose down

# Complete cleanup (removes volumes)
docker-compose down -v
```

Each tier repository contains a `docker-compose.yml` that properly configures:
- Network isolation per tier
- Volume management for metadata persistence
- Health checks and restart policies
- Proper database connectivity via host.docker.internal
- Consistent environment variables

## Complete Command Reference

All shared commands follow the pattern: `./command.sh <tier> <environment> [options]`
Where tier = `admin`, `operator`, or `member` and environment = `development` or `production`

### 📚 Complete Command Index (31 Commands + 4 Testing)

#### Core Operations (Most Used)
- `fast-refresh.sh` - Reload metadata only (1-3 seconds) ⚡
- `rebuild-docker.sh` - Complete container rebuild (dev only, 30-45s) 🔨
- `full-rebuild.sh` - Smart rebuild (Docker in dev, refresh in prod)
- `deploy-graphql.sh` - Full deployment with metadata
- `test-health.sh` - Check GraphQL health status

#### Comparison & Analysis
- `compare-schema-deep.sh` - Deep schema introspection comparison 🔍
- `compare-environments.sh` - Basic environment comparison
- `compare-tables.sh` - Compare tracked tables
- `count-records.sh` - Count all records per table

#### Test Data Management (Tier-Specific)
- `test-all-comprehensive.sh` - Run all tier tests with report 📊
- `test-all-tiers-graphql.sh` - Test all tiers in sequence
- `test-graphql-data-workflow.sh` - Complete test workflow
- `purge-admin-test-data-via-graphql.sh` - Purge admin tier data
- `purge-operator-test-data-via-graphql.sh` - Purge operator tier data
- `purge-member-test-data-via-graphql.sh` - Purge member tier data
- `purge-test-data-via-graphql.sh` - Generic purge command
- `load-admin-test-data-via-graphql.sh` - Load admin tier data
- `load-operator-test-data-via-graphql.sh` - Load operator tier data
- `load-member-test-data-via-graphql.sh` - Load member tier data
- `load-test-data-via-graphql.sh` - Generic load command

#### Docker Management
- `docker-start.sh` - Start containers
- `docker-stop.sh` - Stop containers
- `docker-status.sh` - Check container status
- `restart-graphql.sh` - Restart with health check

#### Schema Management
- `track-all-tables.sh` - Auto-track all tables
- `track-relationships.sh` - Track foreign keys
- `verify-tables-tracked.sh` - Verify tracking
- `verify-complete-setup.sh` - Full setup verification

#### System Status & Production
- `status-all.sh` - System-wide status check
- `setup-production.sh` - Configure production environment

## GraphQL Test Data Management

### Test Data Structure
The shared GraphQL API includes a comprehensive test data framework that mirrors the database structure from `../shared-database-sql/admin-database-sql/test-data/`:

```
test-data/
├── 01_admin/          # Admin schema test data
│   ├── 01_admin_users.csv
│   └── 02_admin_permissions.csv
├── 02_system/         # System schema test data
├── 03_operators/      # Operators schema test data
├── 04_financial/      # Financial schema test data
├── 05_sales/          # Sales schema test data
├── 06_support/        # Support schema test data
├── 07_compliance/     # Compliance schema test data
└── 08_integration/    # Integration schema test data
```

### GraphQL Test Data Commands

#### Data Management Commands
```bash
# Purge all test data via GraphQL mutations
./commands/purge-test-data-via-graphql.sh <tier> <environment>

# Load test data from CSV files via GraphQL mutations
./commands/load-test-data-via-graphql.sh <tier> <environment>

# Complete test workflow: purge → load → verify → report
./commands/test-graphql-data-workflow.sh <tier> <environment>
```

#### Features
- **Schema-Aware**: Automatically uses correct GraphQL table names with schema prefixes (e.g., `admin_admin_users`)
- **Dependency-Aware**: Respects foreign key constraints during purge and load operations
- **CSV Parsing**: Uses Python for robust CSV parsing with proper data type handling
- **JSON Generation**: Creates properly formatted GraphQL mutation payloads
- **Row Count Verification**: Ensures CSV row counts match database row counts
- **Error Handling**: Comprehensive error reporting and rollback capabilities

#### Data Loading Process
1. **CSV Parsing**: Converts CSV files to JSON objects with proper data types
2. **GraphQL Mutations**: Uses parameterized mutations with variables for safety
3. **Foreign Key Handling**: Loads data in correct dependency order
4. **Verification**: Compares loaded row counts with CSV row counts
5. **Reporting**: Provides detailed success/failure reporting

### Usage Examples

```bash
# Test data workflow for admin development environment
./commands/test-graphql-data-workflow.sh admin development

# Manual purge and load
./commands/purge-test-data-via-graphql.sh admin development
./commands/load-test-data-via-graphql.sh admin development

# Verify data counts match CSV files
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-Hasura-Admin-Secret: CCTech2024Admin" \
  -d '{"query": "{ admin_admin_users_aggregate { aggregate { count } } }"}' \
  http://localhost:8101/v1/graphql
```

### Core Deployment & Management Commands (commands/)

#### Primary Operations
```bash
# Full GraphQL API deployment with metadata and table tracking
./commands/deploy-graphql.sh <tier> <environment>

# Lightning-fast metadata refresh without container restart (1-3 seconds)
./commands/fast-refresh.sh <tier> <environment>

# Complete Docker container rebuild (nuclear option, 30-45 seconds)
./commands/rebuild-docker.sh <tier> <environment>
```

#### Docker Container Management
```bash
# Start GraphQL container using docker-compose
./commands/docker-start.sh <tier> <environment>

# Stop GraphQL container
./commands/docker-stop.sh <tier> <environment>

# Check Docker container status
./commands/docker-status.sh <tier> <environment>

# Restart GraphQL service with health check
./commands/restart-graphql.sh <tier> [environment]
```

#### Schema & Table Management
```bash
# Auto-discover and track all database tables
./commands/track-all-tables.sh <tier> <environment>

# Track foreign key relationships for nested queries
./commands/track-relationships.sh <tier> <environment>
```

#### Verification & Health Checks
```bash
# Comprehensive setup verification
./commands/verify-complete-setup.sh <tier> <environment>

# Verify all tables are properly tracked
./commands/verify-tables-tracked.sh <tier> <environment>

# Test GraphQL health endpoints
./commands/test-health.sh [tier|all] [environment]

# Check status of all services (databases + GraphQL)
./commands/status-all.sh [simple|detailed|json]
```

#### Environment Management & Comparison
```bash
# Compare development vs production environments (basic)
./commands/compare-environments.sh <tier>

# Deep schema comparison with full introspection
./commands/compare-schema-deep.sh <tier> [--detailed]

# Compare tracked tables between environments
./commands/compare-tables.sh <tier>

# Count records in all tables for any environment
./commands/count-records.sh <tier> <environment>
```

#### Test Data Management
```bash
# Purge test data for specific tier
./commands/purge-admin-test-data-via-graphql.sh <environment>
./commands/purge-operator-test-data-via-graphql.sh <environment>
./commands/purge-member-test-data-via-graphql.sh <environment>

# Load test data for specific tier
./commands/load-admin-test-data-via-graphql.sh <environment>
./commands/load-operator-test-data-via-graphql.sh <environment>
./commands/load-member-test-data-via-graphql.sh <environment>

# Run complete test workflow (purge → load → verify)
./commands/test-graphql-data-workflow.sh <tier> <environment>

# Test all tiers comprehensively
./commands/test-all-tiers-graphql.sh
./commands/test-all-comprehensive.sh
```

#### Production Setup & Management
```bash
# Setup production environment
./commands/setup-production.sh <tier>

# Full rebuild (Docker in dev, refresh in prod)
./commands/full-rebuild.sh <tier> <environment>
```

#### New Testing Commands (Added)
```bash
# Test all tiers in sequence
./commands/test-all-tiers-graphql.sh

# Comprehensive testing with detailed reporting
./commands/test-all-comprehensive.sh
```

### Testing Commands (testing/)

#### Complete Test Workflow
```bash
# Run complete 4-step test (purge → load → verify → purge)
./testing/test-graphql.sh <tier> <environment>

# Test basic GraphQL connectivity
./testing/test-connection.sh <tier> <environment>
```

#### Test Data Management
```bash
# Load test data into database
./testing/load-test-data.sh <tier> <environment>

# Purge all test data from database
./testing/purge-test-data.sh <tier> <environment>
```

## Code Architecture

### Directory Structure
```
shared-graphql-api/
├── commands/                           # Main GraphQL operations (31 commands)
│   ├── _shared_functions.sh           # Core library with tier configuration
│   ├── deploy-graphql.sh              # Full deployment with metadata
│   ├── fast-refresh.sh                # Quick metadata refresh
│   ├── rebuild-docker.sh              # Complete Docker rebuild
│   ├── full-rebuild.sh                # Smart rebuild (Docker in dev, refresh in prod)
│   ├── docker-start.sh                # Start containers
│   ├── docker-stop.sh                 # Stop containers
│   ├── docker-status.sh               # Check container status
│   ├── restart-graphql.sh             # Restart with health check
│   ├── track-all-tables.sh            # Auto-track database tables
│   ├── track-relationships.sh         # Track foreign keys
│   ├── verify-complete-setup.sh       # Full setup validation
│   ├── verify-tables-tracked.sh       # Verify table tracking
│   ├── test-health.sh                 # Health endpoint testing
│   ├── status-all.sh                  # System-wide status check
│   ├── compare-environments.sh        # Basic dev vs prod comparison
│   ├── compare-schema-deep.sh         # Deep schema introspection comparison
│   ├── compare-tables.sh              # Compare tracked tables
│   ├── count-records.sh               # Count records in all tables
│   ├── setup-production.sh            # Configure production environment
│   ├── test-all-comprehensive.sh      # Run all tier tests with report
│   ├── test-all-tiers-graphql.sh      # Test all tiers in sequence
│   ├── test-graphql-data-workflow.sh  # Complete test workflow
│   ├── purge-admin-test-data-via-graphql.sh    # Purge admin tier data
│   ├── purge-operator-test-data-via-graphql.sh # Purge operator tier data
│   ├── purge-member-test-data-via-graphql.sh   # Purge member tier data
│   ├── purge-test-data-via-graphql.sh          # Generic purge command
│   ├── load-admin-test-data-via-graphql.sh     # Load admin tier data
│   ├── load-operator-test-data-via-graphql.sh  # Load operator tier data
│   ├── load-member-test-data-via-graphql.sh    # Load member tier data
│   └── load-test-data-via-graphql.sh           # Generic load command
├── testing/                            # Testing framework (4 commands)
│   ├── test-graphql.sh                # Complete test workflow
│   ├── test-connection.sh             # Basic connectivity test
│   ├── load-test-data.sh              # Load test fixtures
│   └── purge-test-data.sh             # Clean test data
├── test-data/                          # Test data for all schemas
├── version/                            # Version management
└── Tier repositories (../)            # Individual tier repos
    ├── admin-graqhql-api/
    ├── operator-graqhql-api/
    └── member-graqhql-api/
```

### Key Functions in _shared_functions.sh
- `configure_tier()` - Sets all tier-specific variables (ports, containers, credentials)
- `load_environment()` - Loads development/production configurations
- `execute_graphql_query()` - Runs GraphQL queries with proper authentication
- `track_database_tables()` - Auto-discovers and tracks database objects
- `track_foreign_keys()` - Analyzes and tracks relationship metadata

### Command Workflow Pattern
1. Source `_shared_functions.sh`
2. Parse arguments (tier, environment)
3. Call `configure_tier()` to set variables
4. Load environment configuration
5. Execute tier-specific operations
6. Return standardized output with color coding

## Important Notes

### Production Safety
- All production operations require explicit confirmation
- Destructive operations show clear warnings
- Commands support `--force` flag to skip confirmations

### Performance Targets
- Fast refresh: < 3 seconds
- Table tracking: < 10 seconds  
- Docker rebuild: < 45 seconds
- Complete test workflow: < 60 seconds

### Error Handling
- Comprehensive error tracking with `COMMAND_ERRORS` counter
- Colored output (RED for errors, GREEN for success, YELLOW for warnings)
- Command duration tracking with performance reporting
- Detailed logging with `--verbose` flag support

### Resource Discovery
Commands automatically discover:
- Database tables, views, and functions via introspection
- Foreign key relationships for nested GraphQL queries
- Metadata from tier repository `metadata/` directories
- Environment configs from tier repository `config/` directories

## Command Usage Examples

### Deploy GraphQL API for development
```bash
./commands/deploy-graphql.sh admin development
```

### Quick refresh after database changes
```bash
./commands/fast-refresh.sh operator development
```

### Check health of all services
```bash
./commands/test-health.sh all development
```

### View system-wide status
```bash
./commands/status-all.sh simple
```

### Restart a specific tier
```bash
./commands/restart-graphql.sh member development
```

### Run complete test suite
```bash
./testing/test-graphql.sh admin development
```

### Compare dev vs production
```bash
./commands/compare-environments.sh operator
```

## Tier-Specific Commands Not Yet Migrated

These commands exist in individual tier repositories but could be candidates for shared implementation:

### Common Across Multiple Tiers
- `drop-graphql.sh` - Clean GraphQL shutdown (all tiers)
- `fast-rebuild.sh` - Fast rebuild from metadata (all tiers)
- `report-graphql.sh` - Status reporting (all tiers)
- `speed-test-graphql.sh` - Performance benchmarking (all tiers)
- `track-relationships-smart.sh` - Smart relationship naming (admin, operator)
- `audit-database.sh` - Database auditing (admin, operator)

### Tier-Specific Commands
- **Admin**: `setup-jwt-permissions.sh`, `track-array-relationships.sh`
- **Operator**: `enable-rls.sh`, `configure-hasura-permissions.sh`, `configure-departmental-permissions.sh`
- **Member**: Various data loading commands for comprehensive testing

## System Relationships

### Upstream Dependencies (Parent System)
- **Master Orchestrator** (`/Users/cc/Desktop/v3/`): Coordinates cross-repository operations
- **Shared Database SQL** (`../shared-database-sql/`): Database schemas that GraphQL APIs expose
  - Changes in database schemas require GraphQL metadata refresh
  - Table and relationship tracking must match database structure
  - Testing data loaded via database commands before GraphQL testing

### Downstream Consumers (Child Repositories)
- **Admin GraphQL API** (`../admin-graqhql-api/`): Franchisor operations
- **Operator GraphQL API** (`../operator-graqhql-api/`): Facility management
- **Member GraphQL API** (`../member-graqhql-api/`): Member operations
  - Each maintains tier-specific business logic and metadata
  - All delegate command execution to this shared system
  - Each has specialized CLAUDE.md for their domain context

### Sibling Systems (Parallel Layers)
- **React Portals** (`../*-portal-react/`): Consume GraphQL APIs
- **Seed Data** (`../*-seed-data/`): Populate databases for testing
  - Portal testing depends on GraphQL API availability
  - Seed data must be loaded after GraphQL deployment

## ⚠️ CRITICAL COMMAND DISTINCTIONS - NO AMBIGUITY

### REBUILD vs REFRESH - Precise Definitions

#### 🔴 **REBUILD** Command
When the user says **"rebuild"**, this means:

**In Development**:
```bash
docker-compose down -v   # Completely destroy container and volumes
docker-compose up -d     # Create brand new container from scratch
```
- **Deletes the entire Docker container**
- **Removes all volumes and metadata**
- **Creates fresh instance with zero state**
- **Takes 30-45 seconds**
- **Nuclear option - complete destruction and recreation**

**In Production**:
- **CANNOT be done** - no Docker containers exist
- **Automatically falls back to REFRESH** (see below)
- Should acknowledge: "Cannot rebuild production (no Docker), performing refresh instead..."

#### 🟢 **REFRESH** Command  
When the user says **"refresh"**, this means:

**In Both Development AND Production**:
```bash
./commands/fast-refresh.sh <tier> <environment>
```
- **Reloads metadata only**
- **Clears schema cache**
- **Re-tracks tables and relationships**
- **Container/instance keeps running**
- **Takes 1-3 seconds**
- **Lightweight operation - no destruction**

### Command Matrix - ABSOLUTE CLARITY

| User Says | Environment | What I Do | Duration |
|-----------|------------|-----------|----------|
| "rebuild" | Development | `docker-compose down -v && docker-compose up -d` | 30-45s |
| "rebuild" | Production | `fast-refresh.sh` (fallback - cannot truly rebuild) | 1-3s |
| "refresh" | Development | `fast-refresh.sh` | 1-3s |
| "refresh" | Production | `fast-refresh.sh` | 1-3s |

### Key Understanding
- **REBUILD = Destroy and recreate** (dev only)
- **REFRESH = Reload configuration** (both envs)
- **Production limitation**: Can NEVER truly rebuild (managed service)
- **No ambiguity**: These are distinct, non-interchangeable operations

## Dependencies

- Hasura CLI for metadata management
- Docker and Docker Compose for development
- PostgreSQL client tools (`psql`)
- curl for API interactions
- jq for JSON processing (optional but recommended)
- Access to child tier repositories (`../*-graqhql-api/`)