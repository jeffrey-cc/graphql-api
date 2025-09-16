# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Shared GraphQL API** repository - a unified command framework that manages GraphQL operations across three tiers (admin, operator, member) in the Community Connect Tech multi-tenant system. It provides parameterized commands that eliminate 95%+ code duplication and ensure consistency across all GraphQL API tiers.

## Architecture

### Tier Configuration
The system manages three separate Hasura GraphQL APIs:

| Tier     | Port | Container Name          | Database Port | Admin Secret        |
|----------|------|-------------------------|---------------|---------------------|
| admin    | 8100 | admin-graphql-server    | 5433         | CCTech2024Admin     |
| operator | 8101 | operator-graphql-server | 5434         | CCTech2024Operator  |
| member   | 8102 | member-graphql-server   | 5435         | CCTech2024Member    |

### Integration with Tier Repositories
Each tier has its own repository (`admin-graqhql-api`, `operator-graqhql-api`, `member-graqhql-api`) that:
- Contains tier-specific metadata in `metadata/` directory
- Stores environment configs in `config/` directory
- Uses lightweight wrapper scripts that delegate to this shared system
- Maintains `config/shared-settings.env` pointing to this repository

## Common Development Commands

All commands follow the pattern: `./command.sh <tier> <environment> [options]`
Where tier = `admin`, `operator`, or `member` and environment = `development` or `production`

### Core Operations
```bash
# Deploy GraphQL API with full introspection
./commands/deploy-graphql.sh member development

# Fast metadata refresh (1-3 seconds)
./commands/fast-refresh.sh admin development

# Complete Docker rebuild (30-45 seconds)
./commands/rebuild-docker.sh operator development

# Track all database tables for GraphQL
./commands/track-all-tables.sh member development

# Track foreign key relationships
./commands/track-relationships.sh admin development
```

### Testing Workflow
```bash
# Run complete 4-step test (purge → load → verify → purge)
./testing/test-graphql.sh operator development

# Individual test operations
./testing/purge-test-data.sh member development
./testing/load-test-data.sh admin development
```

### Docker Management
```bash
# Start Docker containers
./commands/docker-start.sh member development

# Check Docker status
./commands/docker-status.sh admin development

# Stop Docker containers
./commands/docker-stop.sh operator development
```

### Environment Management
```bash
# Compare dev vs production environments
./commands/compare-environments.sh member

# Verify complete setup
./commands/verify-complete-setup.sh admin development

# Test GraphQL connections
./commands/test-connections.sh operator development
```

## Code Architecture

### Directory Structure
- `commands/` - Main GraphQL operations (17 commands)
  - `_shared_functions.sh` - Core library with tier configuration system
  - All other scripts source this file and use `configure_tier()` function
- `testing/` - Testing framework (3 commands)
  - Implements 4-step workflow: purge → load → verify → purge
- Tier repositories (`../*-graqhql-api/`) contain:
  - `metadata/` - Hasura metadata exports
  - `config/` - Environment configurations
  - `commands/` - Lightweight wrappers to shared system

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

## Integration Status

✅ **All Tiers Fully Integrated**: 
- `admin-graqhql-api` - 16 wrapper commands (13 commands + 3 testing)
- `operator-graqhql-api` - 16 wrapper commands (13 commands + 3 testing)
- `member-graqhql-api` - 16 wrapper commands (13 commands + 3 testing)

Each tier maintains minimal wrapper scripts that delegate to this shared system, achieving 95%+ code reduction.

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

## Commands Available in Shared System

### Core Commands (17 in commands/)
- `deploy-graphql.sh` - Full GraphQL deployment with metadata
- `fast-refresh.sh` - Lightning-fast metadata refresh
- `rebuild-docker.sh` - Complete Docker container rebuild
- `docker-start.sh` - Start Docker containers
- `docker-stop.sh` - Stop Docker containers
- `docker-status.sh` - Check container status
- `track-all-tables.sh` - Auto-discover and track database tables
- `track-relationships.sh` - Track foreign key relationships
- `verify-complete-setup.sh` - Comprehensive setup validation
- `verify-tables-tracked.sh` - Verify table tracking status
- `test-connection.sh` - Basic connectivity test
- `test-connections.sh` - Comprehensive connection testing
- `test-comprehensive-dataset.sh` - Full dataset validation
- `compare-environments.sh` - Dev vs production comparison
- `load-seed-data.sh` - Load tier-specific seed data
- `purge-test-data.sh` - Clean test data from database
- `_shared_functions.sh` - Core library (not called directly)

### Testing Commands (3 in testing/)
- `test-graphql.sh` - Complete 4-step test workflow
- `load-test-data.sh` - Load test data
- `purge-test-data.sh` - Purge test data

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

## Dependencies

- Hasura CLI for metadata management
- Docker and Docker Compose for development
- PostgreSQL client tools (`psql`)
- curl for API interactions
- jq for JSON processing (optional but recommended)
- Access to sibling tier repositories (`../*-graqhql-api/`)