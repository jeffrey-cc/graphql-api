#!/bin/bash

# ================================================================================
# Get Version Script - Member Database SQL
# ================================================================================
# Manages version information for the member-database-sql repository
# Version format: major.minor.patch.build (e.g., 3.0.0.173)
# ================================================================================

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Version configuration
MAJOR_VERSION="3"
MINOR_VERSION="0"
PATCH_VERSION="0"

# Function to get build number (commit count)
get_build_number() {
    if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to get git information
get_git_info() {
    local git_commit="unknown"
    local git_branch="unknown"
    local git_dirty=""
    
    if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        git_commit=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        git_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        
        # Check if working directory is clean
        if git -C "$REPO_ROOT" diff-index --quiet HEAD -- 2>/dev/null; then
            git_dirty=""
        else
            git_dirty="-dirty"
        fi
    fi
    
    echo "$git_commit|$git_branch|$git_dirty"
}

# Function to update version files
update_version_files() {
    local version="$1"
    local build_number="$2"
    local git_info="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Parse git info
    IFS='|' read -r git_commit git_branch git_dirty <<< "$git_info"
    
    # Write VERSION file (simple format)
    echo "$version" > "$SCRIPT_DIR/VERSION"
    
    # Write VERSION.json
    cat > "$SCRIPT_DIR/VERSION.json" <<EOF
{
  "version": "$version",
  "major": $MAJOR_VERSION,
  "minor": $MINOR_VERSION,
  "patch": $PATCH_VERSION,
  "build": $build_number,
  "repository": "member-database-sql",
  "tier": "member",
  "git": {
    "commit": "$git_commit",
    "branch": "$git_branch",
    "dirty": $([ -n "$git_dirty" ] && echo "true" || echo "false")
  },
  "timestamp": "$timestamp"
}
EOF
    
    # Write VERSION.md
    cat > "$SCRIPT_DIR/VERSION.md" <<EOF
# Version Information

**Repository:** member-database-sql  
**Tier:** Member (Bottom-tier database)  
**Version:** $version  
**Build Date:** $timestamp  

## Version Components
- **Major:** $MAJOR_VERSION (Breaking changes)
- **Minor:** $MINOR_VERSION (New features)
- **Patch:** $PATCH_VERSION (Bug fixes)
- **Build:** $build_number (Total commits)

## Git Information
- **Commit:** $git_commit$git_dirty
- **Branch:** $git_branch
- **Status:** $([ -n "$git_dirty" ] && echo "Modified" || echo "Clean")

## Database Information
- **Container:** member-postgres
- **Port:** 5435
- **Database:** member

## Usage
Run \`./version/get-version.sh\` to display version information.  
Run \`./version/get-version.sh --update\` to update version files.
EOF

    # Write SQL version update script
    cat > "$SCRIPT_DIR/version-update.sql" <<EOF
-- Member Database Version Update
-- Generated: $timestamp
-- Version: $version

-- Create version table if it doesn't exist
CREATE TABLE IF NOT EXISTS member.schema_version (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    major INTEGER NOT NULL,
    minor INTEGER NOT NULL,
    patch INTEGER NOT NULL,
    build INTEGER NOT NULL,
    git_commit VARCHAR(40),
    git_branch VARCHAR(100),
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Insert version record
INSERT INTO member.schema_version (version, major, minor, patch, build, git_commit, git_branch, metadata)
VALUES (
    '$version',
    $MAJOR_VERSION,
    $MINOR_VERSION,
    $PATCH_VERSION,
    $build_number,
    '$git_commit',
    '$git_branch',
    '{
        "timestamp": "$timestamp",
        "dirty": $([ -n "$git_dirty" ] && echo "true" || echo "false"),
        "repository": "member-database-sql",
        "tier": "member"
    }'::jsonb
);
EOF
}

# Main logic
main() {
    local action="${1:-display}"
    
    # Get build number and git info
    local build_number=$(get_build_number)
    local git_info=$(get_git_info)
    local version="${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_VERSION}.${build_number}"
    
    # Parse git info for display
    IFS='|' read -r git_commit git_branch git_dirty <<< "$git_info"
    
    case "$action" in
        --update)
            update_version_files "$version" "$build_number" "$git_info"
            echo "✅ Version files updated: $version"
            echo "   Repository: member-database-sql"
            echo "   Location: $SCRIPT_DIR/"
            echo "   Files: VERSION, VERSION.json, VERSION.md, version-update.sql"
            ;;
        --json)
            # Output JSON format
            cat "$SCRIPT_DIR/VERSION.json" 2>/dev/null || echo "{\"error\": \"Version file not found. Run with --update first.\"}"
            ;;
        --simple)
            # Output simple version string
            echo "$version"
            ;;
        *)
            # Default: Display formatted version info
            echo "🏷️  Member Database SQL Version"
            echo "================================"
            echo "Version: $version"
            echo "Tier: Member"
            echo ""
            echo "Components:"
            echo "  Major: $MAJOR_VERSION"
            echo "  Minor: $MINOR_VERSION"
            echo "  Patch: $PATCH_VERSION"
            echo "  Build: $build_number"
            echo ""
            echo "Git Info:"
            echo "  Commit: $git_commit$git_dirty"
            echo "  Branch: $git_branch"
            
            if [[ -n "$git_dirty" ]]; then
                echo "  Status: ⚠️  Modified working directory"
            else
                echo "  Status: ✅ Clean"
            fi
            
            # Check if version files exist
            if [[ ! -f "$SCRIPT_DIR/VERSION.json" ]]; then
                echo ""
                echo "💡 Tip: Run './version/get-version.sh --update' to create version files"
            fi
            ;;
    esac
}

# Run main function
main "$@"