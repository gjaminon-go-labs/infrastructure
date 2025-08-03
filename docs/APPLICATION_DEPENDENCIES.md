# Application Dependencies Architecture

## Overview

This document defines the architectural approach for managing application dependencies in the go-labs microservices platform. Instead of each service managing its own infrastructure resources, we centralize dependency provisioning while maintaining service isolation through logical boundaries.

## Core Principles

### 1. Infrastructure as Application Dependencies
- **Infrastructure team** manages "plumbing" (databases, queues, caches, secrets)
- **Service teams** focus purely on business logic and schema evolution
- **Clear separation** of operational vs. business concerns

### 2. Shared Resources with Service Isolation
- Single resource instances for operational efficiency
- Logical isolation through schemas, namespaces, and permissions
- Service-specific users with least-privilege access

### 3. Environment Consistency
- Same dependency setup across dev/test/prod
- Version-controlled infrastructure provisioning
- Reproducible environments through automation

## Database Architecture

### Current Approach (Per-Service Databases) → New Approach (Shared Database)

**Before:**
```
- billing_service_dev (dedicated PostgreSQL instance)
- catalog_service_dev (dedicated PostgreSQL instance)
- order_service_dev (dedicated PostgreSQL instance)
```

**After:**
```
go_labs_database (single PostgreSQL instance)
├── billing schema (owned by billing_service_user)
├── catalog schema (owned by catalog_service_user)
└── order schema (owned by order_service_user)
```

### Benefits of Shared Database Approach

#### ✅ Operational Advantages
- **Single DB instance** to manage, backup, monitor, scale
- **Resource efficiency** - shared connection pools, memory, CPU
- **Simplified DevOps** - one database to provision across environments
- **Cost effective** - especially important in cloud environments

#### ✅ Service Boundaries Maintained
- **Schema isolation** - services cannot access each other's data
- **Permission boundaries** - each user can only access their schema
- **Team autonomy** - teams still control their data model evolution
- **Clear ownership** - each team owns their schema completely

#### ✅ Migration Management
- **Service-managed** - each team handles their own schema migrations
- **Version coupling** - schema version tied to service version
- **Independent deployment** - services can evolve schemas independently

### Implementation Details

#### Database Setup (Infrastructure Responsibility)
```sql
-- Create main database
CREATE DATABASE go_labs_database;

-- Create service-specific users
CREATE USER billing_service_user WITH PASSWORD 'secure_password';
CREATE USER catalog_service_user WITH PASSWORD 'secure_password';
CREATE USER order_service_user WITH PASSWORD 'secure_password';

-- Create service-specific schemas
CREATE SCHEMA billing AUTHORIZATION billing_service_user;
CREATE SCHEMA catalog AUTHORIZATION catalog_service_user;
CREATE SCHEMA order AUTHORIZATION order_service_user;

-- Grant schema-specific permissions
GRANT USAGE ON SCHEMA billing TO billing_service_user;
GRANT ALL ON ALL TABLES IN SCHEMA billing TO billing_service_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA billing TO billing_service_user;
-- (repeat for other services)
```

#### Service Configuration (Service Team Responsibility)
```yaml
# billing-api/configs/base.yaml
database:
  host: "localhost"
  port: 5432
  user: "billing_service_user"
  password: "secure_password"
  dbname: "go_labs_database"
  schema: "billing"  # Service only sees its own schema
```

#### Migration Management
- **Service teams** manage their own migrations in their repos
- **Infrastructure** provides database, users, and schemas
- **Autonomous evolution** - teams can change their schema independently

## Extended Dependencies Pattern

### RabbitMQ (Messaging)
```
go_labs_rabbitmq (single RabbitMQ instance)
├── billing_vhost (billing_service_user access)
├── catalog_vhost (catalog_service_user access)
└── order_vhost (order_service_user access)
```

### Redis (Caching)
```
go_labs_redis (single Redis instance)
├── billing: namespace (database 1)
├── catalog: namespace (database 2)
└── order: namespace (database 3)
```

### Secrets Management
```
go_labs_secrets
├── billing/ (billing service secrets)
├── catalog/ (catalog service secrets)
└── order/ (order service secrets)
```

## Infrastructure Project Structure

```
infrastructure/
├── docs/
│   └── APPLICATION_DEPENDENCIES.md (this file)
├── dependencies/
│   ├── database/
│   │   ├── setup-database.sql
│   │   ├── create-users.sql
│   │   └── setup-schemas.sql
│   ├── messaging/
│   │   ├── rabbitmq-setup.sh
│   │   └── vhost-definitions.yml
│   ├── caching/
│   │   ├── redis-setup.sh
│   │   └── namespace-config.yml
│   └── secrets/
│       ├── service-accounts.yml
│       └── rbac-policies.yml
├── scripts/
│   ├── provision-dev-environment.sh
│   ├── provision-test-environment.sh
│   └── provision-prod-environment.sh
└── playbooks/ (future: Ansible/Terraform)
    ├── dev.yml
    ├── test.yml
    └── prod.yml
```

## Developer Workflow

### For Service Teams
1. **Request new service dependencies** via infrastructure team
2. **Receive connection details** and credentials
3. **Manage own schema migrations** within their service repo
4. **Deploy independently** without coordinating with other teams

### For Infrastructure Team
1. **Provision shared resources** (database, queues, caches)
2. **Create service-specific isolation** (schemas, vhosts, namespaces)
3. **Manage operational concerns** (backups, monitoring, scaling)
4. **Provide service credentials** and connection details

## Implementation Phases

### Phase 1: Database Architecture (Current Priority)
- [ ] Create shared `go_labs_database`
- [ ] Setup service-specific schemas and users
- [ ] Migrate billing-api to use new database architecture
- [ ] Update integration tests
- [ ] Document migration process

### Phase 2: Messaging Infrastructure
- [ ] Setup RabbitMQ with service-specific vHosts
- [ ] Create service users with limited permissions
- [ ] Integrate with service configurations

### Phase 3: Caching Infrastructure
- [ ] Setup Redis with service-specific namespaces
- [ ] Configure connection pooling
- [ ] Integrate with service configurations

### Phase 4: Secrets Management
- [ ] Implement centralized secrets management
- [ ] Setup service-specific secret access
- [ ] Integrate with deployment pipelines

## Benefits Summary

### Operational Benefits
- **Reduced complexity** - fewer infrastructure components to manage
- **Resource efficiency** - shared resources, better utilization
- **Simplified monitoring** - centralized observability
- **Cost optimization** - especially in cloud environments

### Development Benefits
- **Team autonomy** - services evolve independently
- **Clear boundaries** - logical separation maintained
- **Simplified local development** - fewer services to run locally
- **Consistent environments** - same setup across dev/test/prod

### Architectural Benefits
- **Microservice principles maintained** - services remain decoupled
- **Platform approach** - infrastructure as a service to teams
- **Scalability** - can migrate to dedicated resources when needed
- **Cloud-native ready** - aligns with Kubernetes and cloud patterns

## Migration Strategy

### From Current Architecture
1. **Create shared database** alongside existing databases
2. **Migrate one service at a time** (start with billing-api)
3. **Validate functionality** with existing tests
4. **Decommission old databases** once migration is complete

### Rollback Plan
- Keep existing databases until migration is fully validated
- Service-specific rollback possible due to schema isolation
- Gradual migration reduces risk

---

**Document Version**: 1.0  
**Created**: August 2025  
**Status**: Architecture Design Phase  
**Next Steps**: Begin Phase 1 - Database Architecture Implementation