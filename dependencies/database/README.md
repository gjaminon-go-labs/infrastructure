# Database Dependencies

This directory contains the database provisioning scripts and templates for the Go Labs application database.

## Architecture

The Go Labs application uses a single PostgreSQL database per environment with schema-based service isolation:

- **Database**: `go-labs-<env>` (e.g., `go-labs-tst`, `go-labs-dev`, `go-labs-prd`)
- **Schemas**: One schema per service (e.g., `billing`, `catalog`, `order`)
- **Users**: Two users per service:
  - **Migration user**: `<service>_migration_<env>_user` - Full DDL privileges on service schema
  - **Application user**: `<service>_app_<env>_user` - DML only (SELECT, INSERT, UPDATE, DELETE)

## Directory Structure

```
database/
├── config/                    # Configuration files
│   ├── environments.conf     # Environment definitions
│   ├── .env.template        # Password template
│   └── .env.<env>          # Environment-specific passwords (not in git)
├── templates/               # SQL templates
│   ├── create-database.sql.template
│   └── create-billing-users.sql.template
└── README.md               # This file
```

## Setup Instructions

### 1. Prepare Environment File

Copy the template and set secure passwords:

```bash
cd infrastructure/dependencies/database/config
cp .env.template .env.tst  # For test environment
# Edit .env.tst and set passwords
```

### 2. Run Provisioning Script

```bash
cd infrastructure/scripts
./provision-database.sh tst  # For test environment
```

The script will:
1. Create the database (drops existing for test environment only)
2. Create service users with appropriate permissions
3. Create service schemas
4. Generate connection configuration files

### 3. Use Generated Configuration

After successful provisioning, find connection details in:
```
infrastructure/output/<env>/billing-connections.yaml
```

## Security Model

### User Permissions

1. **Migration User** (`billing_migration_<env>_user`):
   - Can CREATE, ALTER, DROP tables in their schema
   - Used only during deployments/migrations
   - Cannot access other service schemas

2. **Application User** (`billing_app_<env>_user`):
   - Can only SELECT, INSERT, UPDATE, DELETE on existing tables
   - Used by the running application
   - Cannot modify schema structure
   - Cannot access other service schemas

### Schema Isolation

- Each service owns its schema completely
- No cross-schema access is permitted
- Migration tracking table (`schema_migrations`) lives in each service schema

## Environment Behavior

### Test Environment (`tst`)
- **Drops and recreates** database for clean testing
- Requires confirmation before destructive actions
- Safe for repeated runs

### Development Environment (`dev`)
- Creates resources only if they don't exist
- Never drops existing data
- Safe for repeated runs

### QA/Production (`qua`/`prd`)
- Creates resources only if they don't exist
- Never drops anything
- Extra confirmation required
- Maximum safety

## Adding New Services

To add a new service (e.g., catalog):

1. Create new template: `templates/create-catalog-users.sql.template`
2. Add passwords to `.env.template` and `.env.<env>` files
3. Update provisioning script to process new template
4. Run provisioning to create new schema and users

## Troubleshooting

### Connection Issues
- Verify PostgreSQL is running: `systemctl status postgresql`
- Check host and port in `environments.conf`
- Ensure passwords are set in `.env.<env>` file

### Permission Errors
- Migration user should own the schema
- App user needs USAGE on schema + default privileges
- Check generated SQL files in `output/<env>/`

### Password Issues
- Passwords must not contain special shell characters
- Use strong passwords for non-test environments
- Store production passwords securely (vault, secret manager)