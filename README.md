# Shared GraphQL API

Unified GraphQL API management commands and frameworks for the admin, operator, and member GraphQL tiers.

## Overview

This repository provides a centralized set of parameterized commands that work across all three GraphQL API tiers (admin, operator, member), eliminating duplication and ensuring consistency in GraphQL operations.

## Architecture

The shared system uses tier-based parameterization to manage three separate Hasura GraphQL APIs:

| Tier     | GraphQL Port | Container Name          | PostgreSQL Port | Admin Secret        |
|----------|--------------|-------------------------|-----------------|---------------------|
| admin    | 8101         | admin-graphql-server    | 7101           | CCTech2024Admin     |
| operator | 8102         | operator-graphql-server | 7102           | CCTech2024Operator  |
| member   | 8103         | member-graphql-server   | 7103           | CCTech2024Member    |

## Directory Structure

```
shared-graphql-api/
├── commands/                           # Unified GraphQL commands (31 commands)
│   ├── _shared_functions.sh           # Core library with tier configuration
│   ├── deploy-graphql.sh              # Deploy GraphQL API for any tier
│   ├── fast-refresh.sh                # Fast metadata refresh (1-3 seconds)
│   ├── rebuild-docker.sh              # Complete Docker rebuild (30-45 seconds)
│   ├── full-rebuild.sh                # Smart rebuild (Docker in dev, refresh in prod)
│   ├── docker-start.sh                # Start GraphQL containers
│   ├── docker-stop.sh                 # Stop GraphQL containers
│   ├── docker-status.sh               # Check container status
│   ├── restart-graphql.sh             # Restart with health check
│   ├── track-all-tables.sh            # Track database tables for GraphQL
│   ├── track-relationships.sh         # Track foreign key relationships
│   ├── verify-complete-setup.sh       # Full setup validation
│   ├── verify-tables-tracked.sh       # Verify table tracking
│   ├── test-health.sh                 # Health endpoint testing
│   ├── status-all.sh                  # System-wide status check
│   ├── compare-environments.sh        # Basic dev vs prod comparison
│   ├── compare-schema-deep.sh         # Deep schema introspection
│   ├── compare-tables.sh              # Compare tracked tables
│   ├── count-records.sh               # Count records in all tables
│   ├── setup-production.sh            # Configure production
│   ├── test-all-comprehensive.sh      # Run all tier tests with report
│   ├── test-all-tiers-graphql.sh      # Test all tiers in sequence
│   ├── test-graphql-data-workflow.sh  # Complete test workflow
│   ├── purge-admin-test-data-via-graphql.sh      # Purge admin data
│   ├── purge-operator-test-data-via-graphql.sh   # Purge operator data
│   ├── purge-member-test-data-via-graphql.sh     # Purge member data
│   ├── purge-test-data-via-graphql.sh            # Generic purge
│   ├── load-admin-test-data-via-graphql.sh       # Load admin data
│   ├── load-operator-test-data-via-graphql.sh    # Load operator data
│   ├── load-member-test-data-via-graphql.sh      # Load member data
│   └── load-test-data-via-graphql.sh             # Generic load
├── testing/                            # Unified testing framework (4 commands)
│   ├── test-graphql.sh                # Complete 4-step test workflow
│   ├── test-connection.sh             # Basic connectivity testing
│   ├── purge-test-data.sh             # Remove data, preserve schema
│   └── load-test-data.sh              # Load tier-specific test data
├── test-data/                          # Test data for all schemas
├── version/                            # Version management
└── README.md                           # This file
```

## Usage

All commands follow the same pattern:
```bash
./command-name.sh <tier> <environment> [options]
```

Where:
- `tier` is one of: `admin`, `operator`, or `member`
- `environment` is one of: `development` or `production`

### Examples

#### Deploy GraphQL API
```bash
# Deploy member GraphQL API to development
./commands/deploy-graphql.sh member development

# Deploy admin GraphQL API to production
./commands/deploy-graphql.sh admin production

# Deploy operator GraphQL API without tracking
./commands/deploy-graphql.sh operator development --no-track
```

#### Fast Operations
```bash
# Fast refresh member API (1-3 seconds)
./commands/fast-refresh.sh member development

# Fast refresh admin API in production
./commands/fast-refresh.sh admin production
```

#### Docker Management
```bash
# Complete rebuild of operator Docker (30-45 seconds)
./commands/rebuild-docker.sh operator development

# Force rebuild without confirmation
./commands/rebuild-docker.sh member development --force
```

#### Table and Relationship Tracking
```bash
# Track all member tables for GraphQL
./commands/track-all-tables.sh member development

# Track admin relationships for nested queries
./commands/track-relationships.sh admin development
```

#### Testing Workflow
```bash
# Run complete test workflow for operator
./testing/test-graphql.sh operator development

# Purge member test data only
./testing/purge-test-data.sh member development

# Load admin test data
./testing/load-test-data.sh admin development
```

#### Environment Management
```bash
# Compare member development vs production
./commands/compare-environments.sh member

# Detailed comparison for admin
./commands/compare-environments.sh admin --detailed
```

## How It Works

### Tier Configuration

The `_shared_functions.sh` library provides the `configure_tier()` function that sets all tier-specific variables:

```bash
configure_tier "admin"
# Sets: GRAPHQL_TIER_PORT=8101, GRAPHQL_TIER_CONTAINER=admin-graphql-server, etc.

configure_tier "operator"  
# Sets: GRAPHQL_TIER_PORT=8102, GRAPHQL_TIER_CONTAINER=operator-graphql-server, etc.

configure_tier "member"
# Sets: GRAPHQL_TIER_PORT=8103, GRAPHQL_TIER_CONTAINER=member-graphql-server, etc.
```

### Environment Configuration

Each tier repository maintains its own environment configurations:
- `admin-graqhql-api/config/development.env`
- `admin-graqhql-api/config/production.env`
- `operator-graqhql-api/config/development.env`
- `operator-graqhql-api/config/production.env`
- `member-graqhql-api/config/development.env`
- `member-graqhql-api/config/production.env`

The shared commands automatically locate and load the appropriate configuration file.

### Resource Discovery System

Commands automatically discover resources from the tier-specific repositories:
- **Metadata** from `[tier]-graqhql-api/metadata/` (Hasura metadata exports)
- **Environment configs** from `[tier]-graqhql-api/config/` (development.env, production.env)
- **Database connections** via tier-specific database URLs
- **Test data** via delegation to shared-database-sql system

## Features

### Unified Command Interface
- **35 total commands** (31 in commands/ + 4 in testing/) covering all GraphQL operations
- Consistent parameter handling and validation across all tiers
- Shared error handling and comprehensive logging
- Tier-based parameterization (admin/operator/member)

### Advanced GraphQL Operations
- **Database Introspection**: Automatic discovery of tables, views, and functions
- **Relationship Tracking**: Auto-track foreign key relationships for nested queries
- **Metadata Management**: Fast refresh vs complete rebuild workflows
- **Environment Comparison**: Comprehensive dev vs production analysis
- **Schema Validation**: Ensures GraphQL schema consistency

### Lightning-Fast Deployment Workflows
- **Fast Refresh**: 1-3 seconds for metadata-only updates
- **Docker Rebuild**: 30-45 seconds for complete container recreation
- **Table Tracking**: Automatic discovery and tracking of all database objects
- **Relationship Analysis**: Smart foreign key relationship detection

### Comprehensive Testing Framework
- **4-step test workflow**: purge → load → verify → purge (fully automated)
- **Tier-specific test data**: Automatically loads appropriate test data
- **GraphQL validation**: Tests queries, mutations, and subscriptions
- **Environment verification**: Ensures identical behavior across environments

### Production Safety & Monitoring
- **Production safeguards**: Explicit confirmation prompts for destructive operations
- **Health checks**: Container and GraphQL service status monitoring
- **Comprehensive logging**: Colored output with operation tracking
- **Error recovery**: Robust error handling with detailed reporting

### Hasura Integration
- **Metadata API**: Direct integration with Hasura metadata management
- **Introspection Queries**: GraphQL schema analysis and validation
- **Container Management**: Docker lifecycle management for development
- **Cloud Deployment**: Production deployment to Hasura Cloud

## Migration Status

### Completed Migrations ✅
- **All three tier repositories**: Fully migrated to shared system architecture
- **admin-graqhql-api**: Complete migration with wrapper commands
- **operator-graqhql-api**: Complete migration with wrapper commands  
- **member-graqhql-api**: Complete migration with wrapper commands

### System Status
All GraphQL API tiers now use the unified shared command system with 95%+ code reduction achieved.

### Migration Process
To migrate a repository from individual commands to the shared system:

1. **Add shared configuration**: Create `config/shared-settings.env`
2. **Replace commands** with lightweight wrappers calling shared implementations
3. **Clean up duplicates**: Remove old command files and shared functions
4. **Preserve tier-specific data**: Keep metadata and configuration files
5. **Test integration**: Verify all commands work via shared system

Example wrapper pattern:
```bash
#!/bin/bash
source "$(dirname "$0")/../config/shared-settings.env"
exec "$SHARED_GRAPHQL_API_PATH/commands/deploy-graphql.sh" member "$@"
```

## Key Benefits Achieved

### Code Efficiency
1. **95%+ Code Reduction**: Member repository commands now delegate to shared system
2. **Zero Duplication**: Eliminated maintaining 3 copies of identical GraphQL commands
3. **Unified Maintenance**: Fix once, apply across all tiers automatically
4. **Single Source of Truth**: All GraphQL logic centralized in shared system

### Operational Excellence
5. **Consistent Behavior**: Identical command logic enforced across all tiers
6. **Production Safety**: Comprehensive safeguards and validation for all operations
7. **Advanced Testing**: 35 commands covering every aspect of GraphQL management
8. **Dynamic Discovery**: Commands automatically discover and handle database objects

### System Integration
9. **Tier Parameterization**: Easy to add new tiers or modify existing configurations
10. **Environment Comparison**: Automated dev vs production consistency validation
11. **Comprehensive Monitoring**: Health checks, status monitoring, and detailed reporting
12. **Wrapper Integration**: Tier repositories use lightweight wrappers for convenience

## Requirements

- Hasura CLI (for metadata management)
- Docker for development environments  
- PostgreSQL client tools (`psql`)
- curl for API interactions
- jq for JSON processing (optional, for better output)
- Access to tier repository directories

## Production Safety

All production operations:
- Require explicit confirmation
- Display clear warnings
- Log all operations
- Support dry-run options where applicable

## Error Handling

The shared system provides:
- Comprehensive error tracking
- Colored output for clarity
- Command duration tracking
- Summary reports after execution

## Contributing

### Adding New Commands
1. **Create the command** in appropriate directory (`commands/` or `testing/`)
2. **Use `configure_tier()`** for all tier-specific settings (ports, containers, credentials)
3. **Follow parameter pattern**: `./command.sh <tier> <environment> [options]`
4. **Use shared functions** from `_shared_functions.sh` for common operations
5. **Add error handling** with colored output and comprehensive logging
6. **Include production safeguards** for destructive operations
7. **Update documentation** with usage examples and descriptions

### Adding Wrapper Commands to Tier Repositories
Tier repositories can add lightweight wrapper commands that delegate to shared implementations:
```bash
#!/bin/bash
source "$(dirname "$0")/../config/shared-settings.env"
exec "$SHARED_GRAPHQL_API_PATH/commands/new-command.sh" admin "$@"
```

### Command Naming Conventions
- **GraphQL operations**: `commands/action-graphql.sh`
- **Testing framework**: `testing/test-function.sh`  
- **Comparison tools**: `commands/compare-type.sh`
- **Tracking tools**: `commands/track-target.sh`

## Performance Targets

- **Fast Refresh**: < 3 seconds for metadata-only updates
- **Table Tracking**: < 10 seconds for complete database introspection
- **Docker Rebuild**: < 45 seconds for complete infrastructure recreation
- **Test Workflow**: < 60 seconds for complete purge→load→verify→purge cycle

## License

Part of the Community Connect Tech multi-tenant system.