# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Shared GraphQL API** repository - the central command hub that manages ALL GraphQL operations across three tiers (admin, operator, member) in the Community Connect Tech multi-tenant system. This repository contains the complete command infrastructure, while tier-specific configurations and metadata live in child repositories within this folder structure.

## 🏗️ Repository Structure

```
shared-graphql-api/                # This repository (command hub)
├── commands/                       # Operational commands (17 files)
│   ├── _shared_functions.sh       # Core library with tier configuration
│   ├── deploy-graphql.sh          # Deployment operations
│   ├── docker-*.sh                # Docker management
│   ├── track-*.sh                 # Table and relationship tracking
│   ├── verify-*.sh                # Verification operations
│   └── ...                        # Other operational commands
├── testing/                        # Test and validation commands (7 files)
│   ├── test-*.sh                  # Various test commands
│   ├── load-test-data.sh         # Test data loading
│   ├── purge-test-data.sh        # Test data cleanup
│   └── speed-test-graphql.sh     # Performance testing
├── admin-graqhql-api/             # Admin tier child repository
│   ├── config/                    # Environment configurations
│   │   ├── development.env       # Local development settings
│   │   └── production.env        # Production settings
│   ├── metadata/                  # Hasura metadata
│   └── commands/                  # EMPTY (all commands migrated to parent)
├── operator-graqhql-api/          # Operator tier child repository
│   ├── config/                    # Environment configurations
│   ├── metadata/                  # Hasura metadata
│   └── commands/                  # EMPTY (all commands migrated to parent)
└── member-graqhql-api/            # Member tier child repository
    ├── config/                    # Environment configurations
    ├── metadata/                  # Hasura metadata
    └── commands/                  # EMPTY (all commands migrated to parent)
```

## 🎯 How It Works

### Command Execution Pattern

**ALL commands are executed from this shared repository**, not from child repos:

```bash
# ✅ CORRECT - Run from shared-graphql-api
./commands/deploy-graphql.sh admin development
./testing/test-graphql.sh operator production

# ❌ WRONG - Do NOT run from child repos
cd admin-graqhql-api && ./commands/some-command.sh  # NO COMMANDS HERE!
```

### Parameter Structure

Every command follows this pattern:
```bash
./[commands|testing]/command.sh <tier> <environment> [options]
```

Where:
- **tier**: `admin`, `operator`, or `member` (required)
- **environment**: `development` or `production` (optional, defaults to development)
- **options**: Command-specific flags like `--force`, `--verbose`, etc.

### Configuration Flow

1. **Command executed** from shared-graphql-api with tier parameter
2. **`configure_tier()`** sets tier-specific variables and paths
3. **`load_environment()`** loads config from child repo's `config/` folder
4. **Command runs** using configurations from child repository
5. **Metadata accessed** from child repo's `metadata/` folder if needed

## 📋 Command Categories

### Infrastructure & Docker Management
```bash
./commands/docker-start.sh admin development       # Start containers
./commands/docker-stop.sh operator production      # Stop containers
./commands/docker-status.sh member development     # Check status
./commands/rebuild-docker.sh admin development     # Full rebuild
```

### Deployment & Metadata Management
```bash
./commands/deploy-graphql.sh admin production      # Full deployment
./commands/fast-refresh.sh operator development    # Quick refresh (< 3s)
./commands/refresh-graphql.sh member development   # Metadata refresh
./commands/fast-rebuild.sh admin development       # Rebuild from metadata
./commands/drop-graphql.sh operator development    # Clean shutdown
```

### Table & Relationship Tracking
```bash
./commands/track-all-tables.sh admin development   # Track all tables
./commands/track-relationships.sh operator production  # Track FKs
./commands/track-relationships-smart.sh member development  # Smart naming
```

### Verification & Reporting
```bash
./commands/verify-complete-setup.sh admin development  # Full verification
./commands/verify-tables-tracked.sh operator production  # Table check
./commands/audit-database.sh member development    # Database audit
./commands/report-graphql.sh admin production      # Status report
./commands/compare-environments.sh operator        # Compare dev vs prod
```

### Testing & Validation
```bash
./testing/test-graphql.sh admin development        # Complete test suite
./testing/test-connection.sh operator production   # Basic connectivity
./testing/test-connections.sh member development   # Comprehensive test
./testing/test-comprehensive-dataset.sh admin development  # Full validation
./testing/speed-test-graphql.sh operator compare   # Performance test
./testing/load-test-data.sh member development     # Load test data
./testing/purge-test-data.sh admin production      # Clean test data
```

## 🔧 Technical Implementation

### Tier Configuration System

The `_shared_functions.sh` library provides `configure_tier()` which sets:

```bash
# For tier = "admin"
DB_TIER_PORT="5433"
DB_TIER_CONTAINER="admin-postgres"
DB_TIER_DATABASE="admin"
GRAPHQL_TIER_PORT="8100"
GRAPHQL_TIER_CONTAINER="admin-graphql-server"
GRAPHQL_TIER_ADMIN_SECRET="CCTech2024Admin"

# Path configuration (points to child repos)
TIER_REPOSITORY_PATH="${SHARED_ROOT}/admin-graqhql-api"
TIER_CONFIG_DIR="$TIER_REPOSITORY_PATH/config"
TIER_METADATA_DIR="$TIER_REPOSITORY_PATH/metadata"
```

### Environment Configuration Loading

The `load_environment()` function:
1. Loads from `$TIER_CONFIG_DIR/${environment}.env`
2. Sources all environment variables
3. Sets up database and GraphQL endpoints
4. Configures Hasura admin secrets

### Command Workflow

1. **Parse Arguments**: Extract tier, environment, and options
2. **Configure Tier**: Call `configure_tier()` to set tier-specific variables
3. **Load Environment**: Call `load_environment()` to load configs from child repo
4. **Execute Operation**: Run the command logic using loaded configurations
5. **Access Metadata**: Read/write metadata from child repo's `metadata/` folder
6. **Return Status**: Provide colored output with success/error status

## 📊 Tier Configuration Reference

| Tier     | Port | Container Name          | Database Port | Database | Admin Secret        |
|----------|------|-------------------------|---------------|----------|---------------------|
| admin    | 8100 | admin-graphql-server    | 5433         | admin    | CCTech2024Admin     |
| operator | 8101 | operator-graphql-server | 5434         | operator | CCTech2024Operator  |
| member   | 8102 | member-graphql-server   | 5435         | member   | CCTech2024Member    |

## 🚀 Deployment Workflow

### Development Deployment
```bash
# 1. Start Docker containers
./commands/docker-start.sh admin development

# 2. Deploy GraphQL with table tracking
./commands/deploy-graphql.sh admin development

# 3. Verify setup
./commands/verify-complete-setup.sh admin development

# 4. Run tests
./testing/test-graphql.sh admin development
```

### Production Deployment
```bash
# 1. Compare environments first
./commands/compare-environments.sh operator

# 2. Deploy to production (requires confirmation)
./commands/deploy-graphql.sh operator production

# 3. Verify deployment
./commands/verify-complete-setup.sh operator production

# 4. Generate report
./commands/report-graphql.sh operator production
```

## ⚠️ Important Notes

### No Commands in Child Repositories
- **ALL commands removed** from child repos (`admin-graqhql-api`, `operator-graqhql-api`, `member-graqhql-api`)
- **Child repos only contain**: `config/`, `metadata/`, and other tier-specific resources
- **100% command consolidation** achieved in this shared repository

### Production Safety
- All production operations require explicit confirmation
- Use `--force` flag to skip confirmations in scripts
- Destructive operations show clear warnings

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

## 🔍 Resource Discovery

Commands automatically discover:
- Database tables, views, and functions via introspection
- Foreign key relationships for nested GraphQL queries
- Metadata from tier repository `metadata/` directories
- Environment configs from tier repository `config/` directories

## 📦 Dependencies

- Hasura CLI for metadata management
- Docker and Docker Compose for development
- PostgreSQL client tools (`psql`)
- curl for API interactions
- jq for JSON processing (optional but recommended)
- bash 4.0+ for advanced scripting features

## 🎯 Key Benefits of This Architecture

1. **Single Source of Truth**: All commands in one place
2. **Zero Duplication**: No repeated code across tiers
3. **Consistent Behavior**: Same command works for all tiers
4. **Easy Maintenance**: Update once, works everywhere
5. **Clear Separation**: Commands vs configurations
6. **Tier Independence**: Each tier maintains its own configs/metadata
7. **Simplified Testing**: One test suite for all tiers

## 🚦 Quick Start

```bash
# Check status of all tiers
for tier in admin operator member; do
  ./commands/docker-status.sh $tier development
done

# Deploy all tiers
for tier in admin operator member; do
  ./commands/deploy-graphql.sh $tier development
done

# Test all tiers
for tier in admin operator member; do
  ./testing/test-graphql.sh $tier development
done
```

This architecture ensures maximum code reuse, consistency, and maintainability across the entire multi-tenant GraphQL system.