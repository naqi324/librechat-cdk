# LibreChat CDK Troubleshooting Guide

## Table of Contents

1. [Deployment Issues](#deployment-issues)
2. [Runtime Issues](#runtime-issues)
3. [Database Issues](#database-issues)
4. [Network Issues](#network-issues)
5. [Performance Issues](#performance-issues)
6. [Security Issues](#security-issues)
7. [Cost Issues](#cost-issues)
8. [Debugging Tools](#debugging-tools)

## Deployment Issues

### Issue: Secret Already Exists Error

**Symptoms:**
```
Resource handler returned message: "The operation failed because the secret librechat-development-postgres-secret already exists"
```
or
```
You can't create this secret because a secret with this name is already scheduled for deletion.
```

**Solution:**
This has been fixed - secrets now use the stack name plus a timestamp for uniqueness. Each deployment creates new unique secrets. If you encounter this with an old deployment:

1. **Delete the existing secret immediately:**
   ```bash
   # For postgres secrets
   aws secretsmanager delete-secret \
     --secret-id librechat-development-postgres-secret \
     --force-delete-without-recovery
   
   # For app secrets
   aws secretsmanager delete-secret \
     --secret-id librechat-development-app-secrets \
     --force-delete-without-recovery
   ```

2. **Or use the cleanup script:**
   ```bash
   ./scripts/cleanup-failed.sh
   ```

3. **For secrets scheduled for deletion:**
   ```bash
   # List all secrets scheduled for deletion
   aws secretsmanager list-secrets --filters Key=tag-key,Values=aws:cloudformation:stack-name \
     Key=tag-value,Values=LibreChatStack* --include-planned-deletion
   
   # Force delete them
   aws secretsmanager list-secrets --include-planned-deletion | \
     jq -r '.SecretList[] | select(.Name | contains("librechat")) | .ARN' | \
     xargs -I {} aws secretsmanager delete-secret --secret-id {} --force-delete-without-recovery
   ```

### Issue: ECS Registry Authentication Error

**Symptoms:**
```
ResourceInitializationError: unable to pull secrets or registry auth: execution resource retrieval failed: unable to retrieve secret from asm: service call has been retried 1 time(s): retrieved secret from Secrets Manager did not contain json key creds_key
```

**Solution:**
This has been fixed - the app secrets now properly include all required keys (jwt_secret, creds_key, creds_iv, and meilisearch_master_key). If you encounter this error:

1. **The fix has been automatically applied** - new deployments will create all required secret keys
2. **For existing deployments**, delete and recreate the stack:
   ```bash
   cdk destroy LibreChatStack --force
   cdk deploy
   ```
3. **Manual fix (if needed)**:
   ```bash
   # Get the secret ARN
   SECRET_ARN=$(aws secretsmanager describe-secret --secret-id LibreChatStack-*-AppSecrets* --query ARN --output text)
   
   # Update the secret with all required keys
   aws secretsmanager put-secret-value \
     --secret-id $SECRET_ARN \
     --secret-string '{
       "jwt_secret":"'$(openssl rand -hex 32)'",
       "creds_key":"'$(openssl rand -hex 32)'",
       "creds_iv":"'$(openssl rand -hex 16)'",
       "meilisearch_master_key":"'$(openssl rand -hex 32)'"
     }'
   ```

## Deployment Issues

### Issue: CDK Bootstrap Fails

**Symptoms:**
```
Error: This stack uses assets, so the toolkit stack must be deployed to the environment
```

**Solution:**
```bash
# Bootstrap with specific account and region
cdk bootstrap aws://ACCOUNT-ID/REGION

# If using multiple profiles
aws configure set profile.YOUR_PROFILE.region us-east-1
cdk bootstrap --profile YOUR_PROFILE
```

### Issue: Stack Creation Fails with "Resource Already Exists"

**Symptoms:**
```
Resource with logical ID already exists in stack
```

**Solutions:**
1. **Delete existing stack:**
   ```bash
   cdk destroy LibreChatStack --force
   ```

2. **Use a different stack name:**
   ```bash
   cdk deploy LibreChatStack-v2
   ```

3. **Clean up orphaned resources:**
   ```bash
   # List all resources
   aws cloudformation list-stack-resources --stack-name LibreChatStack
   
   # Manually delete orphaned resources
   aws s3 rb s3://BUCKET-NAME --force
   aws rds delete-db-instance --db-instance-identifier INSTANCE-ID --skip-final-snapshot
   ```

### Issue: IAM Permission Errors During Deployment

**Symptoms:**
```
User: arn:aws:iam::... is not authorized to perform: iam:CreateRole
```

**Solution:**
Ensure your AWS user has AdministratorAccess or create a custom policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:*",
        "ec2:*",
        "rds:*",
        "s3:*",
        "elasticloadbalancing:*",
        "cloudformation:*",
        "cloudwatch:*",
        "logs:*",
        "secretsmanager:*",
        "ssm:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Issue: Lambda Function Build Fails

**Symptoms:**
```
Error: Failed to bundle asset
docker exited with status 125
```

**Solution:**
The project uses pre-built Lambda layers and does NOT require Docker. If you see Docker errors, ensure you're using the latest version of the code which includes pre-built layers for psycopg2.

## Runtime Issues

### Issue: LibreChat Container Won't Start

**Symptoms:**
- Container exits immediately
- Health checks failing

**Debugging Steps:**

1. **Check container logs:**
   ```bash
   # For EC2
   ssh -i your-key.pem ec2-user@INSTANCE-IP
   docker logs librechat
   
   # For ECS
   aws logs tail /ecs/librechat --follow
   ```

2. **Check environment variables:**
   ```bash
   # EC2
   docker exec librechat env | sort
   
   # ECS
   aws ecs describe-tasks --cluster LibreChat-cluster --tasks TASK-ARN
   ```

3. **Common fixes:**
   - Verify database connection string
   - Check JWT_SECRET is set
   - Ensure S3 bucket permissions
   - Verify Bedrock model access

### Issue: "502 Bad Gateway" from Load Balancer

**Symptoms:**
- ALB returns 502 errors
- Target health checks failing

**Solutions:**

1. **Check target health:**
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn arn:aws:elasticloadbalancing:...
   ```

2. **Verify security groups:**
   ```bash
   # ALB should allow inbound 80/443
   # Targets should allow inbound from ALB security group on port 3080
   ```

3. **Check application health endpoint:**
   ```bash
   curl http://localhost:3080/health
   ```

### Issue: File Uploads Not Working

**Symptoms:**
- Upload fails with permission error
- Files not appearing in S3

**Solutions:**

1. **Check S3 permissions:**
   ```bash
   aws s3 ls s3://your-librechat-bucket/
   ```

2. **Verify IAM role:**
   ```bash
   aws iam get-role-policy --role-name LibreChatInstanceRole --policy-name S3Access
   ```

3. **Check CORS configuration:**
   ```json
   {
     "CORSRules": [{
       "AllowedOrigins": ["*"],
       "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
       "AllowedHeaders": ["*"],
       "ExposeHeaders": ["ETag"]
     }]
   }
   ```

## Database Issues

### Issue: "FATAL: password authentication failed"

**Symptoms:**
- Database connection errors in logs
- Application fails to start

**Solutions:**

1. **Verify credentials:**
   ```bash
   # Get secret value
   aws secretsmanager get-secret-value \
     --secret-id librechat-postgres-secret \
     --query SecretString --output text | jq .
   ```

2. **Test connection manually:**
   ```bash
   psql -h database-endpoint.region.rds.amazonaws.com \
        -U postgres -d librechat -p 5432
   ```

3. **Check security group:**
   ```bash
   # Ensure EC2/ECS security group can access RDS
   aws ec2 describe-security-groups --group-ids sg-xxxxxx
   ```

### Issue: Database Initialization Timeout

**Symptoms:**
```
Error: Database did not become available in time
CREATE_FAILED | AWS::CloudFormation::CustomResource | Database/InitPostgresResource
```

**Solutions:**

1. **RDS takes 5-10 minutes to start** - This is normal for first deployment
2. **The fix has been applied** - Lambda timeout increased to 15 minutes, retries increased to 60
3. **If still failing**, check CloudWatch logs:
   ```bash
   aws logs tail /aws/lambda/LibreChatStack-development-DatabaseInitPostgresFunc
   ```
4. **Manual initialization option:**
   ```bash
   # Connect to RDS after deployment completes:
   psql -h <rds-endpoint> -U postgres -d librechat
   # Then run:
   CREATE EXTENSION IF NOT EXISTS vector;
   ```

### Issue: pgvector Extension Not Found

**Symptoms:**
```
ERROR: extension "vector" does not exist
```

**Solutions:**

1. **Check parameter group:**
   ```bash
   aws rds describe-db-parameters \
     --db-parameter-group-name your-param-group \
     --query "Parameters[?ParameterName=='shared_preload_libraries']"
   ```

2. **Manually create extension:**
   ```sql
   CREATE EXTENSION IF NOT EXISTS vector;
   ```

3. **Verify PostgreSQL version:**
   ```bash
   # Must be 15.x or higher
   SELECT version();
   ```

### Issue: DocumentDB Connection Timeout

**Symptoms:**
- MongoDB connection timeouts
- TLS handshake failures

**Solutions:**

1. **Download CA certificate:**
   ```bash
   wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
   ```

2. **Update connection string:**
   ```
   mongodb://username:password@docdb-endpoint:27017/?tls=true&tlsCAFile=/opt/rds-ca-bundle.pem&replicaSet=rs0
   ```

3. **Check DocumentDB parameter group:**
   ```bash
   aws docdb describe-db-cluster-parameters \
     --db-cluster-parameter-group-name your-param-group
   ```

## Network Issues

### Issue: Cannot Access Application

**Symptoms:**
- Timeout when accessing ALB URL
- Cannot SSH to EC2 instance

**Solutions:**

1. **Check security groups:**
   ```bash
   # ALB security group should allow 80/443 from 0.0.0.0/0
   # EC2 security group should allow 22 from your IP
   ```

2. **Verify network ACLs:**
   ```bash
   aws ec2 describe-network-acls --filters "Name=vpc-id,Values=vpc-xxxxx"
   ```

3. **Check route tables:**
   ```bash
   # Public subnets should have route to IGW
   aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxx"
   ```

### Issue: Inter-Service Communication Fails (ECS)

**Symptoms:**
- Services cannot reach each other
- Service discovery not working

**Solutions:**

1. **Check Cloud Map namespace:**
   ```bash
   aws servicediscovery list-services --filters Name="NAMESPACE_ID",Values=ns-xxxxx
   ```

2. **Verify service security groups:**
   ```bash
   # Services should allow traffic from each other
   aws ecs describe-services --cluster LibreChat-cluster --services librechat
   ```

3. **Test DNS resolution:**
   ```bash
   # From within container
   nslookup meilisearch.librechat.local
   ```

## Performance Issues

### Issue: Slow Response Times

**Symptoms:**
- High latency
- Timeouts on complex queries

**Solutions:**

1. **Check CloudWatch metrics:**
   ```bash
   # CPU and memory utilization
   aws cloudwatch get-metric-statistics \
     --namespace AWS/EC2 \
     --metric-name CPUUtilization \
     --dimensions Name=InstanceId,Value=i-xxxxx \
     --start-time 2024-01-01T00:00:00Z \
     --end-time 2024-01-01T01:00:00Z \
     --period 300 \
     --statistics Average
   ```

2. **Scale resources:**
   ```bash
   # EC2: Change instance type
   aws ec2 modify-instance-attribute \
     --instance-id i-xxxxx \
     --instance-type t3.2xlarge
   
   # ECS: Increase task count
   aws ecs update-service \
     --cluster LibreChat-cluster \
     --service librechat \
     --desired-count 4
   ```

3. **Optimize database:**
   ```sql
   -- Check slow queries
   SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;
   
   -- Add indexes
   CREATE INDEX idx_messages_conversation ON messages(conversation_id);
   ```

### Issue: High Memory Usage

**Symptoms:**
- OutOfMemory errors
- Container restarts

**Solutions:**

1. **Increase memory limits:**
   ```typescript
   // For ECS in task definition
   memoryLimitMiB: 8192,
   cpu: 4096,
   ```

2. **Add memory monitoring:**
   ```bash
   # Inside container
   free -h
   ps aux --sort=-%mem | head
   ```

3. **Configure Node.js heap size:**
   ```bash
   NODE_OPTIONS="--max-old-space-size=4096"
   ```

## Security Issues

### Issue: Exposed Secrets in Logs

**Symptoms:**
- Sensitive data visible in CloudWatch logs
- Security scan failures

**Solutions:**

1. **Update logging configuration:**
   ```typescript
   environment: {
     LOG_LEVEL: 'info',
     SUPPRESS_SENSITIVE_LOGS: 'true',
   }
   ```

2. **Use Secrets Manager:**
   ```bash
   # Never hardcode secrets
   aws secretsmanager create-secret \
     --name librechat/api-keys \
     --secret-string '{"openai_key":"sk-..."}'
   ```

3. **Audit logs:**
   ```bash
   # Search for patterns
   aws logs filter-log-events \
     --log-group-name /aws/librechat \
     --filter-pattern "password"
   ```

### Issue: Unauthorized Access Attempts

**Symptoms:**
- Suspicious activity in logs
- Failed authentication attempts

**Solutions:**

1. **Enable GuardDuty:**
   ```bash
   aws guardduty create-detector --enable
   ```

2. **Restrict security groups:**
   ```bash
   # Limit SSH access
   aws ec2 authorize-security-group-ingress \
     --group-id sg-xxxxx \
     --protocol tcp \
     --port 22 \
     --source-group YOUR-IP/32
   ```

3. **Enable AWS WAF:**
   ```bash
   # Create WAF rules for ALB
   aws wafv2 create-web-acl ...
   ```

## Cost Issues

### Issue: Unexpected High Costs

**Symptoms:**
- AWS bill higher than estimated
- Cost anomaly alerts

**Solutions:**

1. **Identify cost drivers:**
   ```bash
   # Use Cost Explorer API
   aws ce get-cost-and-usage \
     --time-period Start=2024-01-01,End=2024-01-31 \
     --granularity DAILY \
     --metrics "UnblendedCost" \
     --group-by Type=DIMENSION,Key=SERVICE
   ```

2. **Optimize resources:**
   - Use Savings Plans for EC2/Fargate
   - Enable S3 lifecycle policies
   - Right-size RDS instances
   - Delete unused snapshots

3. **Set up budget alerts:**
   ```bash
   aws budgets create-budget \
     --account-id YOUR-ACCOUNT \
     --budget file://budget.json \
     --notifications-with-subscribers file://notifications.json
   ```

## Debugging Tools

### Useful Commands

**Check stack status:**
```bash
aws cloudformation describe-stacks --stack-name LibreChatStack
```

**View recent events:**
```bash
aws cloudformation describe-stack-events \
  --stack-name LibreChatStack \
  --max-items 20
```

**SSH to EC2 instance:**
```bash
ssh -i your-key.pem ec2-user@$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)
```

**ECS exec into container:**
```bash
aws ecs execute-command \
  --cluster LibreChat-cluster \
  --task TASK-ARN \
  --container librechat \
  --interactive \
  --command "/bin/bash"
```

**View CloudFormation template:**
```bash
aws cloudformation get-template \
  --stack-name LibreChatStack \
  --query TemplateBody \
  --output yaml
```

### Monitoring Dashboard

Create a custom CloudWatch dashboard:
```bash
aws cloudwatch put-dashboard \
  --dashboard-name LibreChat-Troubleshooting \
  --dashboard-body file://dashboard.json
```

### Log Insights Queries

**Find errors:**
```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

**Track response times:**
```
fields @timestamp, responseTime
| filter @message like /Request completed/
| stats avg(responseTime), max(responseTime), min(responseTime) by bin(5m)
```

**Monitor memory usage:**
```
fields @timestamp, memoryUsed
| filter @type = "metric"
| stats avg(memoryUsed) by bin(5m)
```

## Getting Help

1. **Check logs first** - Most issues are apparent in CloudWatch logs
2. **Review this guide** - Common issues are documented here
3. **Search GitHub issues** - Someone may have encountered the same problem
4. **Join Discord** - Community support available
5. **Create an issue** - Include logs, configuration, and steps to reproduce

Remember to redact sensitive information when sharing logs or configuration!
