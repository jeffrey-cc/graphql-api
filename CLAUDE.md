# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Shared GraphQL API** repository - a unified command framework that manages GraphQL operations across three tiers (admin, operator, member) in the Community Connect Tech multi-tenant system. It provides parameterized commands that eliminate 95%+ code duplication and ensure consistency across all GraphQL API tiers.

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

### Integration with Tier Repositories
Each tier has its own repository (`admin-graqhql-api`, `operator-graqhql-api`, `member-graqhql-api`) that:
- Contains tier-specific metadata in `metadata/` directory (Hasura GraphQL metadata)
- Stores environment configs in `config/` directory (development.env, production.env)
- Includes testing data and scripts in `testing/` directory
- Maintains version information in `version/` directory with automated versioning system
- No command folders - all commands centralized in this shared repository
- No actions servers - pure Hasura GraphQL APIs using metadata-defined actions only

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

## Common Development Commands

All shared commands follow the pattern: `./command.sh <tier> <environment> [options]`
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
- `commands/` - Main GraphQL operations (12 commands)
  - `_shared_functions.sh` - Core library with tier configuration system
  - All other scripts source this file and use `configure_tier()` function
- `testing/` - Testing framework (4 commands)
  - Implements 4-step workflow: purge → load → verify → purge
- Tier repositories (`admin-graqhql-api/`, `operator-graqhql-api/`, `member-graqhql-api/`) contain:
  - `metadata/` - Hasura GraphQL metadata exports
  - `config/` - Environment configurations (development.env, production.env)
  - `testing/` - Tier-specific test data and scripts
  - `scripts/` - Version management and utility scripts
  - `version/` - Automated versioning system (VERSION.json, docker labels, etc.)

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
- `admin-graqhql-api` - Complete GraphQL API with standardized structure
- `operator-graqhql-api` - Complete GraphQL API with standardized structure  
- `member-graqhql-api` - Complete GraphQL API with standardized structure

Each tier maintains only essential files (metadata, configs, testing data) with 100% command consolidation in shared system.

## Versioning System

All three repositories include an automated versioning system:

### Version Structure: `3.0.0.{build}-{commit}-{status}`
- **Base Version**: 3.0.0 (current major release)
- **Build Number**: Auto-incremented from git commit count
- **Commit SHA**: Short git commit hash
- **Status**: `-dirty` if uncommitted changes exist

### Generated Files (in each `version/` folder):
```bash
version/
├── VERSION.json        # Complete version metadata
├── VERSION.txt         # Simple version string
├── docker-labels.txt   # Docker LABEL commands
└── update-hasura-version.sql  # Database version tracking
```

### Usage:
```bash
# View version information
./scripts/get-version.sh

# Generate/update all version files
./scripts/get-version.sh --write

# Version files auto-update on each commit to main
```

The versioning system automatically updates package.json files and generates database scripts to track API versions in the database.

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

### Core Commands (12 in commands/)
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
- `compare-environments.sh` - Dev vs production comparison
- `_shared_functions.sh` - Core library (not called directly)

### Testing Commands (4 in testing/)
- `test-graphql.sh` - Complete 4-step test workflow
- `load-test-data.sh` - Load test data
- `purge-test-data.sh` - Purge test data
- `test-connection.sh` - Basic connectivity test

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