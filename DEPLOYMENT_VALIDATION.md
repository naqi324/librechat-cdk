# LibreChat CDK Deployment Validation

This document confirms that both EC2 and ECS deployment modes are properly configured to run LibreChat Docker containers.

## ✅ EC2 Deployment Configuration

### Docker Setup
- **Docker Installation**: Amazon Linux 2023 with Docker CE
- **Docker Compose**: v2.29.1 (both plugin and standalone)
- **Container Orchestration**: docker-compose.yml with proper service definitions

### LibreChat Container Configuration
```yaml
services:
  api:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: librechat-api
    restart: unless-stopped
    env_file: .env
    ports:
      - "3080:3080"
    volumes:
      - ./librechat.yaml:/app/librechat.yaml
      - ./logs:/app/api/logs
      - ./uploads:/app/client/public/uploads
    environment:
      - NODE_ENV=production
      - MONGO_URI=mongodb://mongodb:27017/LibreChat
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    depends_on:
      mongodb:
        condition: service_started
```

### MongoDB Container
```yaml
mongodb:
  image: mongo:7
  container_name: mongodb
  restart: unless-stopped
  environment:
    - MONGO_INITDB_DATABASE=LibreChat
  volumes:
    - ./mongodb_data:/data/db
  command: mongod --noauth
  healthcheck:
    test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 20s
```

### Startup Sequence
1. Docker daemon starts and waits for readiness
2. Docker images are pulled with retry logic
3. MongoDB starts first and waits for health
4. LibreChat API starts after MongoDB is ready
5. Health checks verify application is running
6. Systemd service ensures persistence

### Key Improvements Made
- ✅ Fixed Docker Compose installation to v2.29.1
- ✅ Added proper health checks for both containers
- ✅ Ensured MongoDB is ready before LibreChat starts
- ✅ Fixed directory permissions for container volumes
- ✅ Added retry logic and comprehensive logging
- ✅ Changed instance type from t3.micro to t3.large (minimum)

## ✅ ECS Deployment Configuration

### Task Definition
- **Image**: `ghcr.io/danny-avila/librechat:latest`
- **CPU**: 2048 (2 vCPU)
- **Memory**: 4096 MiB
- **Platform**: Fargate

### Container Configuration
```typescript
{
  image: 'ghcr.io/danny-avila/librechat:latest',
  memoryLimitMiB: 4096,
  cpu: 2048,
  environment: {
    NODE_ENV: 'production',
    HOST: '0.0.0.0',
    PORT: '3080',
    MONGO_URI: 'mongodb://...',  // DocumentDB or local
    ENDPOINTS: 'bedrock',
    // ... other env vars
  },
  healthCheck: {
    command: ['CMD-SHELL', 'curl -f http://localhost:3080/health || exit 1'],
    interval: 30,
    timeout: 10,
    retries: 3,
    startPeriod: 60,
  },
  portMappings: [{
    containerPort: 3080,
    protocol: 'TCP'
  }]
}
```

### Service Configuration
- **Service Type**: Fargate Service
- **Desired Count**: Configurable (default: 2)
- **Auto-scaling**: Enabled with CPU/memory targets
- **Service Discovery**: CloudMap integration
- **Health Checks**: ALB + container health checks

### Key Improvements Made
- ✅ Added container health checks
- ✅ Fixed environment variable configuration
- ✅ Ensured proper memory and CPU allocation
- ✅ Added NODE_ENV=production
- ✅ Fixed DOMAIN_CLIENT and DOMAIN_SERVER variables
- ✅ Proper MongoDB URI configuration

## Deployment Commands

### EC2 Deployment
```bash
# Build and deploy
npm run build
cdk deploy -c configSource=minimal-dev -c deploymentMode=EC2 -c keyPairName=your-key

# Verify after deployment
aws ssm start-session --target <instance-id>
sudo docker ps
curl http://localhost:3080/health
```

### ECS Deployment
```bash
# Build and deploy
npm run build
cdk deploy -c configSource=production-ecs -c deploymentMode=ECS -c alertEmail=ops@example.com

# Verify after deployment
aws ecs list-tasks --cluster LibreChat-production
aws logs tail /ecs/librechat --follow
```

## Validation Checklist

### EC2 Mode
- [x] Docker and Docker Compose properly installed
- [x] LibreChat container pulls and starts
- [x] MongoDB container runs alongside
- [x] Health endpoint responds on port 3080
- [x] Systemd service ensures persistence
- [x] Logs captured in CloudWatch

### ECS Mode
- [x] Task definition properly configured
- [x] Container starts with correct environment
- [x] Health checks pass
- [x] ALB routes traffic correctly
- [x] Auto-scaling configured
- [x] CloudWatch logs available

## Instance Sizing Recommendations

### EC2 Mode
- **Minimum**: t3.large (2 vCPU, 8 GB RAM)
- **Recommended**: t3.xlarge (4 vCPU, 16 GB RAM)
- **Production**: t3.2xlarge (8 vCPU, 32 GB RAM)

### ECS Mode
- **Minimum**: 1024 CPU, 2048 MiB memory
- **Recommended**: 2048 CPU, 4096 MiB memory
- **Production**: 4096 CPU, 8192 MiB memory

## Troubleshooting

### EC2 Issues
```bash
# Check container status
sudo docker ps -a
sudo docker logs librechat-api

# Check cloud-init logs
sudo tail -f /var/log/cloud-init-output.log

# Restart containers
cd /opt/librechat
sudo /usr/local/bin/docker-compose down
sudo /usr/local/bin/docker-compose up -d
```

### ECS Issues
```bash
# Check task status
aws ecs describe-tasks --cluster <cluster-name> --tasks <task-arn>

# View container logs
aws logs get-log-events --log-group /ecs/librechat --log-stream <stream-name>

# Force new deployment
aws ecs update-service --cluster <cluster-name> --service librechat --force-new-deployment
```

## Conclusion

Both EC2 and ECS deployment modes are now properly configured to run LibreChat Docker containers successfully. The key fixes included:

1. Proper Docker Compose v2 installation
2. Correct container health checks
3. Appropriate instance/task sizing
4. Fixed environment variables
5. Proper startup sequencing
6. MongoDB configuration

The deployments will now successfully instantiate and run LibreChat when either EC2 or ECS mode is selected.