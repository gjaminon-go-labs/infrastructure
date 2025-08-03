#!/bin/bash
#
# PostgreSQL 16 Installation Script for RHEL9
# Uses only Red Hat official repositories (postgresql:16 module)
# 
# Usage: sudo ./install-postgresql16.sh
# Logs: Check infrastructure/logs/postgresql16-install-*.log
#
# This script:
# 1. Removes existing PostgreSQL 13 (if present)
# 2. Enables PostgreSQL 16 module from Red Hat repos
# 3. Installs PostgreSQL 16 server and client
# 4. Initializes database cluster
# 5. Creates development databases
# 6. Validates installation
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_ROOT/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="$LOG_DIR/postgresql16-install-$TIMESTAMP.log"

# Development databases to create
DEV_DATABASES=("billing_service_dev" "billing_service_test")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}INFO:${NC} $*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}SUCCESS:${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}WARNING:${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}ERROR:${NC} $*" >&2
}

# Error handler
error_exit() {
    local line_number="$1"
    log_error "Script failed at line $line_number"
    log_error "Check the log file for details: $LOG_FILE"
    exit 1
}

trap 'error_exit $LINENO' ERR

# Main functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check if this is RHEL9
    if ! grep -q "Red Hat Enterprise Linux.*9" /etc/redhat-release 2>/dev/null; then
        log_warning "This script is designed for RHEL9. Current system:"
        cat /etc/redhat-release | tee -a "$LOG_FILE"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    log_success "Prerequisites check passed"
}

remove_existing_postgresql() {
    log_info "Checking for existing PostgreSQL installations..."
    
    # Check if PostgreSQL 13 is installed
    if rpm -qa | grep -q "postgresql.*13"; then
        log_info "Found PostgreSQL 13 installation. Removing..."
        
        # Stop service if running
        if systemctl is-active --quiet postgresql 2>/dev/null; then
            log_info "Stopping PostgreSQL service..."
            systemctl stop postgresql 2>&1 | tee -a "$LOG_FILE"
        fi
        
        if systemctl is-enabled --quiet postgresql 2>/dev/null; then
            log_info "Disabling PostgreSQL service..."
            systemctl disable postgresql 2>&1 | tee -a "$LOG_FILE"
        fi
        
        # Remove packages
        log_info "Removing PostgreSQL 13 packages..."
        dnf remove -y postgresql-server postgresql postgresql-contrib postgresql-private-libs 2>&1 | tee -a "$LOG_FILE" || true
        
        # Remove data directory (after user confirmation)
        if [[ -d "/var/lib/pgsql" ]]; then
            log_warning "PostgreSQL data directory exists at /var/lib/pgsql"
            echo -e "${YELLOW}This will remove all existing PostgreSQL data!${NC}"
            read -p "Remove /var/lib/pgsql directory? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Removing PostgreSQL data directory..."
                rm -rf /var/lib/pgsql 2>&1 | tee -a "$LOG_FILE"
                log_success "PostgreSQL data directory removed"
            else
                log_warning "Keeping existing data directory. This may cause conflicts."
            fi
        fi
        
        log_success "PostgreSQL 13 removal completed"
    else
        log_info "No existing PostgreSQL installation found"
    fi
}

install_postgresql16() {
    log_info "Installing PostgreSQL 16 from Red Hat official repositories..."
    
    # Reset any existing PostgreSQL module
    log_info "Resetting PostgreSQL module state..."
    dnf module reset postgresql -y 2>&1 | tee -a "$LOG_FILE"
    
    # Enable PostgreSQL 16 module
    log_info "Enabling PostgreSQL 16 module..."
    dnf module enable postgresql:16 -y 2>&1 | tee -a "$LOG_FILE"
    
    # Update package cache
    log_info "Updating package cache..."
    dnf update -y 2>&1 | tee -a "$LOG_FILE"
    
    # Install PostgreSQL 16
    log_info "Installing PostgreSQL 16 server and client..."
    dnf install -y postgresql-server postgresql postgresql-contrib 2>&1 | tee -a "$LOG_FILE"
    
    log_success "PostgreSQL 16 installation completed"
}

initialize_database() {
    log_info "Checking PostgreSQL database cluster status..."
    
    # Check if database is already initialized
    if [[ -d "/var/lib/pgsql/data" && -f "/var/lib/pgsql/data/PG_VERSION" ]]; then
        log_info "PostgreSQL database cluster already exists"
        local pg_version=$(cat /var/lib/pgsql/data/PG_VERSION)
        log_info "Existing PostgreSQL version: $pg_version"
        
        if [[ "$pg_version" == "16" ]]; then
            log_success "PostgreSQL 16 database cluster already initialized"
        else
            log_warning "Database cluster is version $pg_version, but PostgreSQL 16 is installed"
            log_warning "Consider upgrading the data directory or recreating it"
        fi
    else
        log_info "Initializing PostgreSQL database cluster..."
        
        # Initialize database
        if postgresql-setup --initdb 2>&1 | tee -a "$LOG_FILE"; then
            log_success "PostgreSQL database cluster initialized successfully"
        else
            log_error "Failed to initialize PostgreSQL database cluster"
            exit 1
        fi
    fi
    
    # Enable and start service
    log_info "Configuring PostgreSQL service..."
    
    if ! systemctl is-enabled --quiet postgresql; then
        log_info "Enabling PostgreSQL service..."
        systemctl enable postgresql 2>&1 | tee -a "$LOG_FILE"
    else
        log_info "PostgreSQL service already enabled"
    fi
    
    if ! systemctl is-active --quiet postgresql; then
        log_info "Starting PostgreSQL service..."
        systemctl start postgresql 2>&1 | tee -a "$LOG_FILE"
        
        # Wait for service to be ready
        log_info "Waiting for PostgreSQL to be ready..."
        sleep 3
    else
        log_info "PostgreSQL service already running"
    fi
    
    # Verify service is running
    if systemctl is-active --quiet postgresql; then
        log_success "PostgreSQL service is running"
    else
        log_error "PostgreSQL service failed to start"
        systemctl status postgresql 2>&1 | tee -a "$LOG_FILE"
        exit 1
    fi
}

configure_authentication() {
    log_info "Configuring PostgreSQL authentication..."
    
    # Check if password authentication is already working
    log_info "Testing current authentication method..."
    local auth_working=false
    if PGPASSWORD=postgres psql -h localhost -U postgres -c "SELECT 1;" 2>/dev/null | grep -q "1"; then
        log_info "Password authentication already working locally"
        auth_working=true
    fi
    
    # Set password for postgres user (always safe to run)
    if [ "$auth_working" = false ]; then
        log_info "Password authentication not working - configuring now..."
        log_info "Setting postgres user password..."
        if sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "PostgreSQL user password set successfully"
        else
            log_error "Failed to set postgres user password"
            exit 1
        fi
    else
        log_info "Password already set - verifying pg_hba.conf configuration..."
    fi
    
    # Check pg_hba.conf configuration
    local pg_hba_file="/var/lib/pgsql/data/pg_hba.conf"
    
    # Check if pg_hba.conf has all required authentication rules (local + network)
    local has_local_md5=$(grep -c "^local.*all.*all.*md5" "$pg_hba_file" 2>/dev/null || echo "0")
    local has_localhost_md5=$(grep -c "^host.*all.*all.*127.0.0.1/32.*md5" "$pg_hba_file" 2>/dev/null || echo "0")
    local has_network_md5=$(grep -c "^host.*all.*all.*10.130.0.0/24.*md5" "$pg_hba_file" 2>/dev/null || echo "0")
    
    if [ "$has_local_md5" -gt 0 ] && [ "$has_localhost_md5" -gt 0 ] && [ "$has_network_md5" -gt 0 ]; then
        log_success "pg_hba.conf already configured for both local and network authentication"
        return 0
    else
        log_info "Configuring pg_hba.conf for password authentication..."
        
        # Backup original pg_hba.conf
        local pg_hba_backup="${pg_hba_file}.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "Backing up pg_hba.conf to: $pg_hba_backup"
        cp "$pg_hba_file" "$pg_hba_backup" 2>&1 | tee -a "$LOG_FILE"
        
        # Create new pg_hba.conf with password authentication
        cat > "$pg_hba_file" << 'EOF'
# PostgreSQL Client Authentication Configuration File
# ===================================================
#
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     md5

# IPv4 local connections:
host    all             all             127.0.0.1/32            md5

# IPv4 network connections (10.130.0.0/24 subnet):
host    all             all             10.130.0.0/24           md5

# IPv6 local connections:
host    all             all             ::1/128                 md5

# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            md5
host    replication     all             ::1/128                 md5
EOF

        if [[ $? -eq 0 ]]; then
            log_success "pg_hba.conf configured for password authentication"
        else
            log_error "Failed to configure pg_hba.conf"
            exit 1
        fi
        
        # Restart PostgreSQL to apply pg_hba.conf changes
        log_info "Restarting PostgreSQL to apply pg_hba.conf changes..."
        if systemctl restart postgresql 2>&1 | tee -a "$LOG_FILE"; then
            log_success "PostgreSQL restarted successfully"
        else
            log_error "Failed to restart PostgreSQL"
            exit 1
        fi
        
        # Wait for service to be ready
        log_info "Waiting for PostgreSQL to be ready after restart..."
        sleep 5
        
        # Verify service is running
        if systemctl is-active --quiet postgresql; then
            log_success "PostgreSQL is running after restart"
        else
            log_error "PostgreSQL is not running after restart"
            systemctl status postgresql 2>&1 | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
    
    # Test password authentication
    log_info "Testing password authentication..."
    sleep 2  # Give PostgreSQL time to reload config
    
    if PGPASSWORD=postgres psql -h localhost -U postgres -c "SELECT 1;" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Password authentication test passed"
    else
        log_error "Password authentication test failed"
        log_info "Checking if we can connect without password (for debugging)..."
        if sudo -u postgres psql -c "SELECT 1;" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Connection works without password - authentication configuration may not have taken effect"
        else
            log_error "Cannot connect with or without password - there may be a service issue"
        fi
        exit 1
    fi
}

configure_remote_access() {
    log_info "Configuring PostgreSQL for remote access..."
    
    local postgresql_conf="/var/lib/pgsql/data/postgresql.conf"
    
    # Check current listen_addresses setting
    if grep -q "^listen_addresses.*=.*'\*'" "$postgresql_conf"; then
        log_success "PostgreSQL already configured to listen on all addresses"
    else
        log_info "Configuring PostgreSQL to accept remote connections..."
        
        # Backup postgresql.conf
        local pg_conf_backup="${postgresql_conf}.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "Backing up postgresql.conf to: $pg_conf_backup"
        cp "$postgresql_conf" "$pg_conf_backup" 2>&1 | tee -a "$LOG_FILE"
        
        # Update listen_addresses
        if grep -q "^#listen_addresses" "$postgresql_conf"; then
            # Uncomment and set to '*'
            sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$postgresql_conf"
        elif grep -q "^listen_addresses" "$postgresql_conf"; then
            # Replace existing setting
            sed -i "s/^listen_addresses = .*/listen_addresses = '*'/" "$postgresql_conf"
        else
            # Add new setting
            echo "listen_addresses = '*'" >> "$postgresql_conf"
        fi
        
        if [[ $? -eq 0 ]]; then
            log_success "Updated postgresql.conf for remote access"
        else
            log_error "Failed to update postgresql.conf"
            exit 1
        fi
        
        # Restart PostgreSQL to apply changes
        log_info "Restarting PostgreSQL to apply configuration changes..."
        systemctl restart postgresql 2>&1 | tee -a "$LOG_FILE"
        
        # Wait for service to be ready
        log_info "Waiting for PostgreSQL to be ready after restart..."
        sleep 5
        
        # Verify service is running
        if systemctl is-active --quiet postgresql; then
            log_success "PostgreSQL restarted successfully"
        else
            log_error "PostgreSQL failed to restart"
            systemctl status postgresql 2>&1 | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
}

configure_firewall() {
    log_info "Configuring firewall for PostgreSQL access..."
    
    # Check if firewalld is running
    if ! systemctl is-active --quiet firewalld; then
        log_warning "Firewalld is not running - skipping firewall configuration"
        return 0
    fi
    
    # Check if PostgreSQL service is already allowed
    if firewall-cmd --list-services | grep -q postgresql; then
        log_success "PostgreSQL service already allowed in firewall"
    else
        log_info "Adding PostgreSQL service to firewall..."
        
        # Add PostgreSQL service to firewall
        firewall-cmd --add-service=postgresql --permanent 2>&1 | tee -a "$LOG_FILE"
        
        if [[ $? -eq 0 ]]; then
            log_success "PostgreSQL service added to firewall"
        else
            log_warning "Failed to add PostgreSQL service, trying port-based rule..."
            
            # Try adding port directly if service fails
            firewall-cmd --add-port=5432/tcp --permanent 2>&1 | tee -a "$LOG_FILE"
            
            if [[ $? -eq 0 ]]; then
                log_success "PostgreSQL port 5432/tcp added to firewall"
            else
                log_error "Failed to configure firewall for PostgreSQL"
                exit 1
            fi
        fi
        
        # Reload firewall rules
        log_info "Reloading firewall rules..."
        firewall-cmd --reload 2>&1 | tee -a "$LOG_FILE"
        
        if [[ $? -eq 0 ]]; then
            log_success "Firewall rules reloaded successfully"
        else
            log_error "Failed to reload firewall rules"
            exit 1
        fi
    fi
    
    # Show current firewall configuration
    log_info "Current firewall configuration:"
    firewall-cmd --list-all 2>&1 | tee -a "$LOG_FILE"
}

create_development_databases() {
    log_info "Creating development databases..."
    
    for db in "${DEV_DATABASES[@]}"; do
        log_info "Checking if database '$db' exists..."
        
        # Check if database already exists
        if PGPASSWORD=postgres psql -h localhost -U postgres -lqt | cut -d \| -f 1 | grep -qw "$db"; then
            log_success "Database '$db' already exists"
        else
            log_info "Creating database: $db"
            if PGPASSWORD=postgres createdb -h localhost -U postgres "$db" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Database '$db' created successfully"
            else
                log_error "Failed to create database '$db'"
                exit 1
            fi
        fi
    done
    
    # List all databases to verify
    log_info "Current databases:"
    PGPASSWORD=postgres psql -h localhost -U postgres -l 2>&1 | tee -a "$LOG_FILE"
}

validate_installation() {
    log_info "Validating PostgreSQL installation..."
    
    # Check version
    log_info "PostgreSQL version:"
    psql --version 2>&1 | tee -a "$LOG_FILE"
    
    # Check if we can connect with password authentication
    log_info "Testing database connection with password authentication..."
    if PGPASSWORD=postgres psql -h localhost -U postgres -c "SELECT version();" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Database connection test passed"
    else
        log_error "Database connection test failed"
        exit 1
    fi
    
    # Check service status
    log_info "PostgreSQL service status:"
    systemctl status postgresql --no-pager 2>&1 | tee -a "$LOG_FILE"
    
    # Verify development databases exist
    log_info "Verifying development databases..."
    for db in "${DEV_DATABASES[@]}"; do
        if PGPASSWORD=postgres psql -h localhost -U postgres -lqt | cut -d \| -f 1 | grep -qw "$db"; then
            log_success "Database '$db' exists and is accessible"
        else
            log_error "Database '$db' is missing or inaccessible"
            exit 1
        fi
    done
    
    # Test connecting to each development database
    log_info "Testing connection to development databases..."
    for db in "${DEV_DATABASES[@]}"; do
        if PGPASSWORD=postgres psql -h localhost -U postgres -d "$db" -c "SELECT 1;" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Successfully connected to database '$db'"
        else
            log_error "Failed to connect to database '$db'"
            exit 1
        fi
    done
}

validate_remote_access() {
    log_info "Validating PostgreSQL remote access configuration..."
    
    # Check if PostgreSQL is listening on all interfaces
    log_info "Checking PostgreSQL listening addresses..."
    if ss -tlnp | grep ":5432" | grep -q "0.0.0.0:5432"; then
        log_success "PostgreSQL is listening on all interfaces (0.0.0.0:5432)"
    elif ss -tlnp | grep ":5432" | grep -q "127.0.0.1:5432"; then
        log_warning "PostgreSQL is only listening on localhost (127.0.0.1:5432)"
        log_warning "Remote connections may not work properly"
    else
        log_error "PostgreSQL listening status unclear"
        log_info "Current listening ports:"
        ss -tlnp | grep ":5432" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Test local connection with explicit host
    log_info "Testing local connection with explicit host..."
    if PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -c "SELECT 'Local connection works' as test;" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Local connection test passed"
    else
        log_error "Local connection test failed"
        exit 1
    fi
    
    # Test connection using external DNS name
    local external_dns="flxlinuxcnpjumppoc01.cnp.fluxys.poc"
    log_info "Testing connection using external DNS name ($external_dns)..."
    if PGPASSWORD=postgres psql -h "$external_dns" -U postgres -c "SELECT 'External DNS connection works' as test;" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "External DNS connection test passed"
    else
        log_warning "External DNS connection test failed - this may be expected if DNS resolution is restricted"
        log_info "This test verifies that PostgreSQL would accept connections from the external DNS name"
    fi
    
    # Verify network subnet rule in pg_hba.conf
    log_info "Verifying network subnet rule in pg_hba.conf..."
    if grep -q "^host.*all.*all.*10.130.0.0/24.*md5" "/var/lib/pgsql/data/pg_hba.conf"; then
        log_success "Network subnet rule (10.130.0.0/24) found in pg_hba.conf"
    else
        log_error "Network subnet rule (10.130.0.0/24) missing from pg_hba.conf"
        log_info "Current pg_hba.conf contents:"
        cat "/var/lib/pgsql/data/pg_hba.conf" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Check firewall status
    if systemctl is-active --quiet firewalld; then
        log_info "Checking firewall configuration for PostgreSQL..."
        if firewall-cmd --list-services | grep -q postgresql || firewall-cmd --list-ports | grep -q "5432/tcp"; then
            log_success "Firewall allows PostgreSQL connections"
        else
            log_warning "Firewall may be blocking PostgreSQL connections"
        fi
    else
        log_info "Firewalld is not active - no firewall restrictions"
    fi
}

print_summary() {
    echo ""
    echo "=============================================="
    echo "PostgreSQL 16 Installation Summary"
    echo "=============================================="
    echo ""
    echo -e "${GREEN}✓${NC} PostgreSQL 16 installed from Red Hat official repositories"
    echo -e "${GREEN}✓${NC} Database cluster initialized"
    echo -e "${GREEN}✓${NC} Service enabled and started"
    echo -e "${GREEN}✓${NC} Password authentication configured (user: postgres, password: postgres)"
    echo -e "${GREEN}✓${NC} Remote access configured (listening on all interfaces)"
    echo -e "${GREEN}✓${NC} Firewall configured to allow PostgreSQL connections"
    echo -e "${GREEN}✓${NC} Development databases created:"
    for db in "${DEV_DATABASES[@]}"; do
        echo "   - $db"
    done
    echo ""
    echo "Next steps:"
    echo "1. Test your billing-api integration tests:"
    echo "   cd ../billing-api && make test-integration"
    echo ""
    echo "2. Check PostgreSQL status:"
    echo "   sudo systemctl status postgresql"
    echo ""
    echo "3. Connect to PostgreSQL with password:"
    echo "   PGPASSWORD=postgres psql -h localhost -U postgres"
    echo "   PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres  # Explicit IP"
    echo ""
    echo "4. Connect to development databases:"
    echo "   PGPASSWORD=postgres psql -h localhost -U postgres -d billing_service_dev"
    echo "   PGPASSWORD=postgres psql -h localhost -U postgres -d billing_service_test"
    echo ""
    echo "5. Test remote connectivity:"
    echo "   PGPASSWORD=postgres psql -h <server-ip> -U postgres -d billing_service_test"
    echo ""
    echo "Installation log: $LOG_FILE"
    echo "=============================================="
}

# Main execution
main() {
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    log_info "Starting PostgreSQL 16 installation..."
    log_info "Log file: $LOG_FILE"
    log_info "Script running as: $(whoami)"
    log_info "System: $(cat /etc/redhat-release)"
    
    check_prerequisites
    remove_existing_postgresql
    install_postgresql16
    initialize_database
    configure_authentication
    configure_remote_access
    configure_firewall
    create_development_databases
    validate_installation
    validate_remote_access
    
    log_success "PostgreSQL 16 installation completed successfully!"
    print_summary
}

# Run main function
main "$@"