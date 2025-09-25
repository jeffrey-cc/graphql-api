# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **GraphQL API** repository - a unified command framework that manages GraphQL operations across three tiers (admin, operator, member) in the Community Connect Tech multi-tenant system. It provides a complete deterministic pipeline for GraphQL API setup, testing, and validation using pure database introspection and GraphQL-only data operations.

## Core Philosophy

**NO EXTERNAL DEPENDENCIES**: This system uses only:
- Database introspection to discover tables, views, enums, and functions
- GraphQL mutations for all data loading
- GraphQL queries for all data counting and verification
- Hasura metadata API for tracking and relationship management

**NEVER** relies on external schema files, SQL scripts from other repos, or manual configuration.

## Deterministic Pipeline

The system implements a complete deterministic workflow that either succeeds entirely or fails with clear error messages:

### Pipeline Steps
1. **Container Management**
   - Development: Destroy and rebuild Docker containers with volumes
   - Production: Preserve containers, purge GraphQL tracking only

2. **Database Connection + Introspection**  
   - Connect to existing populated databases
   - Use SQL introspection to discover all tables, views, enums, functions
   - Track ALL discovered objects via Hasura metadata API

3. **Dynamic Relationship Discovery**
   - Query `information_schema` for foreign key constraints
   - Automatically create object and array relationships
   - No manual relationship configuration required

4. **Test Data Workflow** (GraphQL-only)
   - Purge all data via GraphQL delete mutations
   - Load CSV data via GraphQL insert mutations  
   - Verify record counts match CSV line counts
   - Purge all data again via GraphQL
   - Verify all table counts are zero

5. **Structure Comparison**
   - Compare dev vs production table/relationship counts
   - Ensure structural consistency across environments

## Architecture

### Tier Configuration
| Tier     | GraphQL Port | Container Name          | PostgreSQL Port | Admin Secret        |
|----------|--------------|-------------------------|-----------------|---------------------|
| admin    | 8101         | admin-graphql-server    | 7101           | CCTech2024Admin     |
| operator | 8102         | operator-graphql-server | 7102           | CCTech2024Operator  |
| member   | 8103         | member-graphql-server   | 7103           | CCTech2024Member    |

### Integration with Child Repositories
Child repositories (`./admin-graphql-api/`, `./operator-graphql-api/`, `./member-graphql-api/`) contain:
- `test-data/` - CSV files copied from database system for GraphQL testing
- `CLAUDE.md` - Tier-specific business context

**Important**: Child repositories are NOT tracked in shared Git history (gitignored).

## Key Commands

### Complete Pipeline
```bash
# Run full deterministic pipeline
./commands/complete-pipeline.sh admin development
./commands/complete-pipeline.sh operator production
```

### Individual Operations
```bash
# Container rebuild (development only)
./commands/full-rebuild-dev.sh

# Database introspection and table tracking
./commands/track-all-tables.sh admin development

# Relationship discovery and tracking  
./commands/track-relationships-smart.sh operator development

# Test data workflow
./testing/test-graphql.sh member development
```

## Directory Structure
```
graphql-api/
├── commands/
│   ├── complete-pipeline.sh      # Full deterministic pipeline
│   ├── full-rebuild-dev.sh       # Development container rebuild
│   ├── track-all-tables.sh       # Introspection-based table tracking
│   ├── track-relationships-smart.sh # Dynamic relationship discovery
│   └── _shared_functions.sh      # Core library functions
├── testing/
│   ├── test-graphql.sh           # Complete test workflow
│   ├── load-test-data.sh         # GraphQL-based data loading
│   └── purge-test-data.sh        # GraphQL-based data purging
├── docker-compose.yml            # Unified GraphQL container stack
└── CLAUDE.md                     # This file

Child repositories (gitignored):
./admin-graphql-api/test-data/    # Admin CSV test data
./operator-graphql-api/test-data/ # Operator CSV test data
./member-graphql-api/test-data/   # Member CSV test data
```

## Development Workflow

### Making Changes
1. **Database Schema Changes**: Work in `../database-sql/` 
2. **GraphQL Updates**: Run introspection-based tracking to auto-discover changes
3. **Testing**: Use GraphQL-only test data workflow
4. **No Manual Configuration**: System discovers everything via introspection

### Running Tests
```bash
# Complete end-to-end test
./commands/complete-pipeline.sh admin development

# Individual components
./commands/track-all-tables.sh admin development
./testing/test-graphql.sh admin development
```

## Error Handling

The pipeline is designed to be deterministic:
- **Succeeds Completely**: All steps pass, system ready for use
- **Fails with Clear Errors**: Specific actionable error messages, no partial states
- **No Manual Intervention**: Either runs or stops, never requires hand-fixing

## Integration Points

### With Database System
- Connects to databases populated by `../database-sql/`
- Discovers schema via introspection, never reads database repo files
- Uses CSV data copied to child GraphQL repos

### With Portal Systems  
- GraphQL APIs ready for portal consumption after pipeline completion
- All tables tracked with proper relationships
- Test data available for portal testing

## Performance Expectations
- Complete pipeline: 2-3 minutes for development, 30-60 seconds for production
- Table tracking: Scales with database size, typically 10-30 seconds
- Test data workflow: Scales with data volume, typically 30-60 seconds

## Production Safety
- All production operations require explicit confirmation or `--force` flag
- Container destruction only occurs in development environments
- Production operations preserve existing containers and data
- Clear warnings for destructive operations

This system provides a completely automated, deterministic GraphQL API management solution that scales across all tiers while maintaining consistency and reliability.