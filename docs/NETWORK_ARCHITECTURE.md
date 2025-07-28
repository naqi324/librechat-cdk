# Network Architecture

## Subnet Configuration

### Overview

The LibreChat CDK deployment uses a three-tier subnet architecture:

1. **PUBLIC Subnets**
   - Application Load Balancer (ALB)
   - EC2 instances (EC2 deployment mode)
   - NAT Gateways (if enabled)

2. **PRIVATE_WITH_EGRESS Subnets**
   - ECS Tasks (when using ECS deployment mode)
   - EFS Mount Targets
   - Has internet access via NAT Gateway

3. **PRIVATE_ISOLATED Subnets**
   - RDS PostgreSQL
   - DocumentDB
   - Lambda functions for database initialization
   - No direct internet access

## Component Placement

| Component | Subnet Type | Security Group | Notes |
|-----------|-------------|----------------|-------|
| ALB | PUBLIC | ALBSecurityGroup | Internet-facing |
| EC2 Instance | PUBLIC | EC2SecurityGroup | SSH access allowed |
| ECS Tasks | PRIVATE_WITH_EGRESS | ServiceSecurityGroup | Internet via NAT |
| RDS PostgreSQL | PRIVATE_ISOLATED | PostgresSecurityGroup | No internet |
| DocumentDB | PRIVATE_ISOLATED | DocumentDbSecurityGroup | No internet |
| Lambda (DB Init) | PRIVATE_ISOLATED | InitLambdaSG | Same subnet as DBs |
| EFS | PRIVATE_WITH_EGRESS | EfsSecurityGroup | Accessible by ECS |

## Network Connectivity

### Database Access
- Lambda functions are placed in PRIVATE_ISOLATED subnet to access databases
- ECS tasks in PRIVATE_WITH_EGRESS can access databases in PRIVATE_ISOLATED
- Security groups control access between subnets

### Internet Access
- PUBLIC subnet: Direct internet access
- PRIVATE_WITH_EGRESS: Internet access via NAT Gateway
- PRIVATE_ISOLATED: No internet access

### Security Group Rules
- Databases allow inbound from Lambda and application security groups
- EFS allows inbound from ECS tasks
- ALB allows inbound HTTP/HTTPS from internet
- EC2 allows SSH from specified IP ranges

## Troubleshooting

### Common Issues

1. **Lambda Cannot Connect to Database**
   - Ensure Lambda is in same subnet type as database (PRIVATE_ISOLATED)
   - Check security group rules allow Lambda SG to access database SG

2. **ECS Tasks Cannot Pull Images**
   - Ensure ECS tasks are in PRIVATE_WITH_EGRESS subnet
   - Verify NAT Gateway is configured and route tables are correct

3. **Cannot Access Application**
   - Check ALB is in PUBLIC subnet
   - Verify security group allows inbound HTTP/HTTPS
   - Check target group health checks

## Best Practices

1. Keep databases in PRIVATE_ISOLATED for maximum security
2. Use PRIVATE_WITH_EGRESS for compute resources that need internet
3. Minimize resources in PUBLIC subnet
4. Use security groups as primary access control mechanism
5. Enable VPC Flow Logs for troubleshooting
