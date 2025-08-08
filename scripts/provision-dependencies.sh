#!/bin/bash
#
# Generic Application Dependencies Provisioning Script
# 
# This script provisions ALL application dependencies for a given environment.
# It serves as the single entry point for setting up all required services.
#
# Usage: ./provision-dependencies.sh <environment>
# Examples:
#   ./provision-dependencies.sh tst    # Test environment
#   ./provision-dependencies.sh dev    # Development environment
#   ./provision-dependencies.sh qua    # Quality/Staging environment
#   ./provision-dependencies.sh prd    # Production environment
#
# Currently provisions:
# - PostgreSQL (database, schemas, users)
#
# Future additions:
# - RabbitMQ (message queuing)
# - Redis (caching)
# - MinIO (object storage)
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-}"

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

# Validate environment parameter
if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Environment parameter is required"
    echo "Usage: $0 <environment>"
    echo "Available environments: tst, dev, qua, prd"
    exit 1
fi

# Validate environment value
if [[ ! "$ENVIRONMENT" =~ ^(tst|dev|qua|prd)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    echo "Available environments: tst, dev, qua, prd"
    exit 1
fi

# Main provisioning logic
log_info "🚀 Starting application dependencies provisioning for environment: $ENVIRONMENT"
echo ""

# Database dependencies (PostgreSQL)
log_info "📦 Configuring PostgreSQL database dependencies..."
if [[ -f "$SCRIPT_DIR/provision-database.sh" ]]; then
    "$SCRIPT_DIR/provision-database.sh" "$ENVIRONMENT"
    log_success "PostgreSQL dependencies configured"
else
    log_error "Database provisioning script not found: $SCRIPT_DIR/provision-database.sh"
    exit 1
fi
echo ""

# Future: Message queue dependencies (RabbitMQ)
# log_info "📦 Configuring RabbitMQ message queue dependencies..."
# if [[ -f "$SCRIPT_DIR/provision-rabbitmq.sh" ]]; then
#     "$SCRIPT_DIR/provision-rabbitmq.sh" "$ENVIRONMENT"
#     log_success "RabbitMQ dependencies configured"
# fi
# echo ""

# Future: Cache dependencies (Redis)
# log_info "📦 Configuring Redis cache dependencies..."
# if [[ -f "$SCRIPT_DIR/provision-redis.sh" ]]; then
#     "$SCRIPT_DIR/provision-redis.sh" "$ENVIRONMENT"
#     log_success "Redis dependencies configured"
# fi
# echo ""

# Future: Object storage dependencies (MinIO)
# log_info "📦 Configuring MinIO object storage dependencies..."
# if [[ -f "$SCRIPT_DIR/provision-minio.sh" ]]; then
#     "$SCRIPT_DIR/provision-minio.sh" "$ENVIRONMENT"
#     log_success "MinIO dependencies configured"
# fi
# echo ""

# Summary
echo ""
log_success "🎉 All application dependencies successfully provisioned for $ENVIRONMENT environment!"
echo ""
echo "Provisioned services:"
echo "  ✓ PostgreSQL - Database with schemas and users"
# echo "  ✓ RabbitMQ  - Message queuing (coming soon)"
# echo "  ✓ Redis     - Caching (coming soon)"
# echo "  ✓ MinIO     - Object storage (coming soon)"
echo ""
echo "Applications can now connect using the configured credentials."
echo "Run migrations from your application directory to complete setup."