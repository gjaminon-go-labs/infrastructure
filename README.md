# Infrastructure

[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](https://argoproj.github.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.25+-green.svg)](https://kubernetes.io)
[![Infrastructure as Code](https://img.shields.io/badge/IaC-Terraform-purple.svg)](https://terraform.io)

Infrastructure as Code and GitOps configurations for the go-labs microservices platform, providing automated deployment, monitoring, and platform services.

## GitOps Pattern
- **Single Source of Truth**: All deployment configurations in Git
- **Declarative Configuration**: Kubernetes manifests describe desired state
- **Automated Deployment**: ArgoCD/Flux watches this repository for changes
- **Environment Promotion**: Changes flow through dev → staging → production

## Repository Structure
```
infrastructure/
├── environments/           # Environment-specific configurations
│   ├── dev/               # Development environment
│   │   ├── billing-api/
│   │   ├── catalog-api/
│   │   ├── order-service/      # Future
│   │   └── kustomization.yaml
│   ├── staging/           # Staging environment
│   │   ├── billing-api/
│   │   ├── catalog-api/
│   │   └── kustomization.yaml
│   └── production/        # Production environment
│       ├── billing-api/
│       ├── catalog-service/
│       └── kustomization.yaml
├── platform/              # Platform-wide resources
│   ├── ingress/           # Ingress controllers and routes
│   ├── monitoring/        # Prometheus, Grafana, AlertManager
│   ├── security/          # RBAC, NetworkPolicies, PodSecurityPolicies
│   └── operators/         # Custom operators and CRDs
└── scripts/               # Deployment automation
    ├── bootstrap.sh       # Initial cluster setup
    ├── deploy.sh          # Manual deployment script
    └── rollback.sh        # Rollback script
```

## Environment Configuration Strategy

### Development Environment
- **Purpose**: Feature development and testing
- **Replicas**: Single instance per service
- **Resources**: Minimal CPU/Memory limits
- **Database**: Shared development database
- **Monitoring**: Basic logging and metrics

### Staging Environment  
- **Purpose**: Pre-production testing and validation
- **Replicas**: Production-like scaling
- **Resources**: Production-equivalent resources
- **Database**: Isolated staging database
- **Monitoring**: Full observability stack

### Production Environment
- **Purpose**: Live customer traffic
- **Replicas**: High availability with multiple instances
- **Resources**: Optimized CPU/Memory limits
- **Database**: Production database with backup/HA
- **Monitoring**: Complete observability + alerting

## Service Deployment Pattern

Each service follows this deployment structure:
```
environments/{env}/{service-name}/
├── deployment.yaml        # Kubernetes Deployment
├── service.yaml          # Kubernetes Service
├── configmap.yaml        # Application configuration
├── secret.yaml           # Sensitive configuration (sealed)
├── ingress.yaml          # External access rules
└── kustomization.yaml    # Kustomize configuration
```

## Platform Components

### Ingress
- **Controller**: Nginx Ingress Controller
- **SSL/TLS**: Let's Encrypt certificates
- **Routing**: Path-based routing to services

### Monitoring Stack
- **Metrics**: Prometheus for metrics collection
- **Visualization**: Grafana dashboards
- **Alerting**: AlertManager for notifications
- **Logging**: ELK Stack (Elasticsearch, Logstash, Kibana)
- **Tracing**: Jaeger for distributed tracing

### Security
- **RBAC**: Role-based access control
- **Network Policies**: Service-to-service communication rules
- **Pod Security**: Pod security policies and standards
- **Secrets**: Sealed Secrets for sensitive data

## Deployment Workflow

### GitOps Flow
```
1. Developer commits code → Service repository
2. CI pipeline builds image → Container registry
3. CI updates image tag → GitOps repository (this repo)
4. ArgoCD detects change → Pulls new manifests
5. ArgoCD applies changes → Kubernetes cluster
6. Monitoring alerts → If deployment issues
```

### Manual Deployment
```bash
# Deploy to development
./scripts/deploy.sh dev billing-api

# Deploy to staging
./scripts/deploy.sh staging billing-api

# Deploy to production (requires approval)
./scripts/deploy.sh production billing-api
```

## Service Versions

Current deployed versions:
- **Development**: Latest builds from main branch
- **Staging**: Release candidates
- **Production**: Stable releases

## ArgoCD Applications

### Application Structure
```yaml
# Example ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: billing-api-dev
  namespace: argocd
spec:
  project: go-labs
  source:
    repoURL: https://github.com/gjaminon-go-labs/infrastructure
    targetRevision: HEAD
    path: environments/dev/billing-api
  destination:
    server: https://kubernetes.default.svc
    namespace: go-labs-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Configuration Management

### Configuration Hierarchy
```
Final Configuration = 
  Service Base Config (from service repo) +
  Environment Overrides (from this repo) +
  Runtime Secrets (from secret management)
```

### Environment Variables
- **Development**: Permissive settings, debug logging
- **Staging**: Production-like settings, info logging  
- **Production**: Secure settings, error/warn logging

## Security Considerations

### Secrets Management
- **Sealed Secrets**: Encrypted secrets stored in Git
- **External Secrets**: Integration with HashiCorp Vault
- **RBAC**: Least privilege access principles
- **Network Policies**: Zero-trust networking

### Compliance
- **Audit Logging**: All changes tracked in Git history
- **Access Control**: Branch protection and review requirements
- **Vulnerability Scanning**: Container image scanning
- **Policy Enforcement**: OPA Gatekeeper policies

## Monitoring and Alerting

### Key Metrics
- **Service Health**: Pod status, readiness, liveness
- **Performance**: Response times, throughput, error rates
- **Resources**: CPU, memory, disk usage
- **Business**: Order completion, payment success rates

### Alert Rules
- **Critical**: Service down, high error rates
- **Warning**: High latency, resource exhaustion
- **Info**: Deployment success, configuration changes

## Disaster Recovery

### Backup Strategy
- **Database**: Automated daily backups
- **Configuration**: Git history serves as backup
- **Secrets**: Vault backup and replication

### Recovery Procedures
- **Rollback**: Automated rollback on deployment failure
- **Point-in-time**: Database restoration capabilities
- **Multi-region**: Future disaster recovery setup

## Development Status
- [x] Repository structure created
- [x] Environment directories established
- [ ] Base Kubernetes manifests
- [ ] Kustomize configurations
- [ ] ArgoCD application definitions
- [ ] Monitoring stack deployment
- [ ] Security policies implementation
- [ ] CI/CD integration

## Getting Started
*To be implemented*

## Contributing
All changes to production deployments require:
1. Pull request with proper review
2. Successful deployment to staging
3. Approval from platform team
4. Automated testing validation

## Contact
- **Platform Team**: For infrastructure and deployment issues
- **Service Teams**: For application-specific configurations
- **Security Team**: For security policy questions

---

**Part of**: [gjaminon-go-labs](https://github.com/gjaminon-go-labs) - A comprehensive Go microservices showcase  
**Purpose**: Infrastructure as Code and GitOps for enterprise-grade microservices deployment