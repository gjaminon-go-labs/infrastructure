#!/bin/bash
#
# Database Provisioning Script for Go Labs Application
# 
# Usage: ./provision-database.sh <environment>
# Examples:
#   ./provision-database.sh tst    # Test environment (will drop/recreate)
#   ./provision-database.sh dev    # Development environment
#   ./provision-database.sh qua    # Quality/Staging environment
#   ./provision-database.sh prd    # Production environment
#
# This script:
# 1. Creates the go-labs-<env> database
# 2. Creates service-specific users (migration and application)
# 3. Sets up schemas with proper permissions
# 4. Generates connection configuration files
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"
DB_DEPS_DIR="$INFRA_ROOT/dependencies/database"
TEMPLATES_DIR="$DB_DEPS_DIR/templates"
CONFIG_DIR="$DB_DEPS_DIR/config"
OUTPUT_DIR="$INFRA_ROOT/output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  ${NC}$*"
}

log_success() {
    echo -e "${GREEN}✅ ${NC}$*"
}

log_warning() {
    echo -e "${YELLOW}⚠️  ${NC}$*"
}

log_error() {
    echo -e "${RED}❌ ${NC}$*" >&2
}

# Show usage
usage() {
    echo "Usage: $0 <environment>"
    echo "Environments: tst, dev, qua, prd"
    echo ""
    echo "Examples:"
    echo "  $0 tst    # Provision test database (drops existing)"
    echo "  $0 dev    # Provision development database"
    echo "  $0 prd    # Provision production database"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    # Check if psql is available
    if ! command -v psql >/dev/null 2>&1; then
        log_error "PostgreSQL client (psql) is not installed"
        exit 1
    fi
    
    # Check if envsubst is available (for template processing)
    if ! command -v envsubst >/dev/null 2>&1; then
        log_error "envsubst is not installed (part of gettext package)"
        exit 1
    fi
}

# Process template file
process_template() {
    local template_file=$1
    local output_file=$2
    
    # First pass: handle conditionals
    local temp_file=$(mktemp)
    local in_if_block=false
    local should_include=true
    
    while IFS= read -r line; do
        # Check for if statements
        if [[ "$line" =~ \{%[[:space:]]*if[[:space:]]+ENV[[:space:]]*==[[:space:]]*\'([^\']+)\'[[:space:]]*%\} ]]; then
            local match_env="${BASH_REMATCH[1]}"
            in_if_block=true
            should_include=false
            if [[ "$ENV" == "$match_env" ]]; then
                should_include=true
            fi
            continue
        elif [[ "$line" =~ \{%[[:space:]]*if[[:space:]]+ENV[[:space:]]*!=[[:space:]]*\'([^\']+)\'[[:space:]]*%\} ]]; then
            local match_env="${BASH_REMATCH[1]}"
            in_if_block=true
            should_include=false
            if [[ "$ENV" != "$match_env" ]]; then
                should_include=true
            fi
            continue
        elif [[ "$line" =~ \{%[[:space:]]*endif[[:space:]]*%\} ]]; then
            in_if_block=false
            should_include=true
            continue
        fi
        
        # Include line if we should
        if [[ "$should_include" == "true" ]]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$template_file"
    
    # Second pass: substitute variables
    # Replace {{VAR}} style variables
    sed -e "s/{{ENV}}/$ENV/g" \
        -e "s/{{ENV_DESCRIPTION}}/$ENV_DESCRIPTION/g" \
        -e "s/{{TIMESTAMP}}/$TIMESTAMP/g" \
        -e "s/{{BILLING_MIGRATION_PASSWORD}}/$BILLING_MIGRATION_PASSWORD/g" \
        -e "s/{{BILLING_APP_PASSWORD}}/$BILLING_APP_PASSWORD/g" \
        "$temp_file" > "$output_file"
    
    rm -f "$temp_file"
}

# Main provisioning function
main() {
    # Check if environment parameter provided
    if [[ $# -ne 1 ]]; then
        usage
    fi
    
    ENV=$1
    
    # Source environment configuration
    source "$CONFIG_DIR/environments.conf"
    
    # Validate environment
    if ! validate_environment "$ENV"; then
        log_error "Invalid environment: $ENV"
        log_info "Valid environments: ${VALID_ENVIRONMENTS[*]}"
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Load environment-specific configuration
    local DB_HOST="${DB_HOSTS[$ENV]}"
    local DB_PORT="${DB_PORTS[$ENV]}"
    local ALLOW_DROP_DB="${ALLOW_DROP[$ENV]}"
    local ENV_DESCRIPTION="${ENV_DESCRIPTIONS[$ENV]}"
    local DB_ADMIN="${DB_ADMIN_USER[$ENV]}"
    
    log_info "Provisioning database for: $ENV_DESCRIPTION"
    log_info "Database host: $DB_HOST:$DB_PORT"
    
    # Check for environment file with passwords
    local ENV_FILE="$CONFIG_DIR/.env.$ENV"
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "Please copy $CONFIG_DIR/.env.template to $ENV_FILE and set passwords"
        exit 1
    fi
    
    # Source environment file
    set -a  # Export all variables
    source "$ENV_FILE"
    set +a
    
    # Verify required passwords are set
    if [[ -z "${POSTGRES_ADMIN_PASSWORD:-}" ]] || \
       [[ -z "${BILLING_MIGRATION_PASSWORD:-}" ]] || \
       [[ -z "${BILLING_APP_PASSWORD:-}" ]]; then
        log_error "Required passwords not set in $ENV_FILE"
        log_info "Please set: POSTGRES_ADMIN_PASSWORD, BILLING_MIGRATION_PASSWORD, BILLING_APP_PASSWORD"
        exit 1
    fi
    
    # Safety prompts
    if [[ "$ENV" == "tst" ]]; then
        log_warning "TEST Environment detected"
        log_warning "This will DROP and recreate the go-labs-tst database!"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    else
        log_info "This will create database go-labs-$ENV if it doesn't exist"
        log_info "Existing databases will NOT be dropped"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi
    
    # Create output directory for this environment
    local ENV_OUTPUT_DIR="$OUTPUT_DIR/$ENV"
    mkdir -p "$ENV_OUTPUT_DIR"
    
    # Set up template variables
    export ENV
    export ENV_DESCRIPTION
    export TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    export BILLING_MIGRATION_PASSWORD
    export BILLING_APP_PASSWORD
    
    # Process templates
    log_info "Processing database creation template..."
    process_template \
        "$TEMPLATES_DIR/create-database.sql.template" \
        "$ENV_OUTPUT_DIR/01-create-database.sql"
    
    log_info "Processing billing users template..."
    process_template \
        "$TEMPLATES_DIR/create-billing-users.sql.template" \
        "$ENV_OUTPUT_DIR/02-create-billing-users.sql"
    
    # Execute SQL scripts
    log_info "Creating database and users..."
    
    # Set PostgreSQL password
    export PGPASSWORD="$POSTGRES_ADMIN_PASSWORD"
    
    # Execute database creation
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN" -f "$ENV_OUTPUT_DIR/01-create-database.sql"; then
        log_success "Database created successfully"
    else
        log_error "Failed to create database"
        exit 1
    fi
    
    # Execute user creation
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN" -f "$ENV_OUTPUT_DIR/02-create-billing-users.sql"; then
        log_success "Users and schemas created successfully"
    else
        log_error "Failed to create users and schemas"
        exit 1
    fi
    
    # Generate connection configuration files
    log_info "Generating connection configuration..."
    
    cat > "$ENV_OUTPUT_DIR/billing-connections.yaml" << EOF
# Generated connection configuration for billing service - $ENV environment
# Generated at: $TIMESTAMP
# 
# Use these settings in your billing-api configuration files

migration:
  host: "$DB_HOST"
  port: $DB_PORT
  database: "go-labs-$ENV"
  user: "billing_migration_${ENV}_user"
  password: "$BILLING_MIGRATION_PASSWORD"
  schema: "billing"
  sslmode: "disable"
  
  # Database URL format for migration tools
  database_url: "postgres://billing_migration_${ENV}_user:$BILLING_MIGRATION_PASSWORD@$DB_HOST:$DB_PORT/go-labs-$ENV?sslmode=disable&search_path=billing"

application:
  host: "$DB_HOST"
  port: $DB_PORT
  database: "go-labs-$ENV"
  user: "billing_app_${ENV}_user"
  password: "$BILLING_APP_PASSWORD"
  schema: "billing"
  sslmode: "disable"
  
  # Connection pool settings
  max_open_conns: 25
  max_idle_conns: 5
  conn_max_lifetime: "5m"
  
  # Database URL format for application
  database_url: "postgres://billing_app_${ENV}_user:$BILLING_APP_PASSWORD@$DB_HOST:$DB_PORT/go-labs-$ENV?sslmode=disable&search_path=billing"
EOF
    
    # Test connections
    log_info "Testing connections..."
    
    # Test migration user
    export PGPASSWORD="$BILLING_MIGRATION_PASSWORD"
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "billing_migration_${ENV}_user" -d "go-labs-$ENV" -c "SELECT current_schema();" >/dev/null 2>&1; then
        log_success "Migration user connection successful"
    else
        log_error "Migration user connection failed"
    fi
    
    # Test application user
    export PGPASSWORD="$BILLING_APP_PASSWORD"
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "billing_app_${ENV}_user" -d "go-labs-$ENV" -c "SELECT current_schema();" >/dev/null 2>&1; then
        log_success "Application user connection successful"
    else
        log_error "Application user connection failed"
    fi
    
    # Clear password from environment
    unset PGPASSWORD
    
    # Summary
    echo ""
    log_success "Database provisioning complete!"
    echo ""
    echo "📊 Database: go-labs-$ENV"
    echo "🗂️  Schema: billing"
    echo "👤 Migration User: billing_migration_${ENV}_user"
    echo "👤 Application User: billing_app_${ENV}_user"
    echo "📄 Connection config: $ENV_OUTPUT_DIR/billing-connections.yaml"
    echo ""
    log_info "Next steps:"
    echo "  1. Update billing-api configuration with connection details"
    echo "  2. Run database migrations using migration user"
    echo "  3. Configure application to use app user for runtime"
}

# Run main function
main "$@"