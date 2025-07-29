import json
import logging
import os
import time
import socket
import boto3
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_client = boto3.client('secretsmanager')


def get_db_credentials(secret_id):
    """Retrieve database credentials from AWS Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_id)
        secret = json.loads(response['SecretString'])
        return secret
    except Exception as e:
        logger.error(f"Error retrieving secret: {str(e)}")
        # Add more context to the error
        if 'AccessDeniedException' in str(e):
            raise Exception(f"Access denied to secret {secret_id}. Check Lambda IAM role permissions.")
        elif 'ResourceNotFoundException' in str(e):
            raise Exception(f"Secret {secret_id} not found. Verify the secret exists.")
        else:
            raise Exception(f"Failed to retrieve secret {secret_id}: {str(e)}")


def validate_network_connectivity(host, port, secret_id=None):
    """Comprehensive network connectivity validation"""
    errors = []
    warnings = []
    
    logger.info("Starting comprehensive network connectivity validation")
    
    # Test DNS resolution
    try:
        logger.info(f"Testing DNS resolution for {host}")
        ip_address = socket.gethostbyname(host)
        logger.info(f"✓ DNS resolution successful: {host} -> {ip_address}")
    except socket.gaierror as e:
        errors.append(f"DNS resolution failed for {host}: {str(e)}")
        logger.error(f"✗ DNS resolution failed: {str(e)}")
    except Exception as e:
        errors.append(f"DNS test failed: {str(e)}")
        logger.error(f"✗ DNS test error: {str(e)}")
    
    # Test TCP connectivity
    try:
        logger.info(f"Testing TCP connectivity to {host}:{port}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((socket.gethostbyname(host), int(port)))
        sock.close()
        
        if result == 0:
            logger.info(f"✓ TCP connection successful to {host}:{port}")
        else:
            error_msg = f"TCP connection failed with code {result}"
            errors.append(error_msg)
            logger.error(f"✗ {error_msg}")
    except Exception as e:
        errors.append(f"TCP connectivity test failed: {str(e)}")
        logger.error(f"✗ TCP test error: {str(e)}")
    
    # Test Secrets Manager access if secret_id provided
    if secret_id:
        try:
            logger.info(f"Testing Secrets Manager access for {secret_id}")
            response = secrets_client.describe_secret(SecretId=secret_id)
            logger.info(f"✓ Secrets Manager access successful: {response['Name']}")
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'AccessDeniedException':
                errors.append(f"Access denied to Secrets Manager. Check Lambda IAM role.")
            elif error_code == 'ResourceNotFoundException':
                errors.append(f"Secret {secret_id} not found.")
            else:
                errors.append(f"Secrets Manager error: {error_code}")
            logger.error(f"✗ Secrets Manager access failed: {error_code}")
        except Exception as e:
            errors.append(f"Secrets Manager test failed: {str(e)}")
            logger.error(f"✗ Secrets Manager test error: {str(e)}")
    
    # Test environment
    logger.info("Checking Lambda environment:")
    logger.info(f"  VPC ID: {os.environ.get('AWS_VPC_ID', 'Not set')}")
    logger.info(f"  Subnet IDs: {os.environ.get('AWS_VPC_SUBNET_IDS', 'Not set')}")
    logger.info(f"  Security Groups: {os.environ.get('AWS_VPC_SECURITY_GROUP_IDS', 'Not set')}")
    
    # Summary
    logger.info("=" * 60)
    logger.info("Network Validation Summary:")
    logger.info(f"  Errors: {len(errors)}")
    logger.info(f"  Warnings: {len(warnings)}")
    
    if errors:
        logger.error("Validation FAILED with errors:")
        for error in errors:
            logger.error(f"  - {error}")
        raise Exception(f"Network validation failed: {'; '.join(errors)}")
    
    logger.info("✓ All network validation checks passed")
    return True


def build_connection_string(username, password, host, port, use_direct_connection=True):
    """Build appropriate DocumentDB connection string based on context"""
    base_url = f"mongodb://{username}:{password}@{host}:{port}"
    
    params = {
        'tls': 'true',
        'tlsCAFile': '/opt/rds-ca-2019-root.pem',
        'retryWrites': 'false'  # DocumentDB doesn't support retryWrites
    }
    
    if use_direct_connection:
        # For Lambda initialization - direct connection
        params['directConnection'] = 'true'
    else:
        # For application usage - replica set
        params['replicaSet'] = 'rs0'
        params['readPreference'] = 'secondaryPreferred'
    
    query_string = '&'.join(f"{k}={v}" for k, v in params.items())
    return f"{base_url}/?{query_string}"


def wait_for_db(host, port, username, password, max_retries=None, retry_delay=None):
    """Wait for DocumentDB to become available with exponential backoff"""
    # Use environment variables if not provided
    if max_retries is None:
        max_retries = int(os.environ.get('MAX_RETRIES', '30'))  # Reduced from 60
    if retry_delay is None:
        retry_delay = int(os.environ.get('RETRY_DELAY', '10'))
    
    logger.info(f"Starting DocumentDB connection process")
    logger.info(f"Host: {host}, Port: {port}")
    logger.info(f"Max retries: {max_retries}, Initial retry delay: {retry_delay}s")
    
    current_delay = retry_delay
    
    for i in range(max_retries):
        try:
            # Build connection string for Lambda initialization
            conn_string = build_connection_string(username, password, host, port, use_direct_connection=True)
            logger.info(f"Attempting connection {i+1}/{max_retries} (delay: {current_delay}s)")
            
            # DocumentDB requires TLS
            client = MongoClient(
                conn_string,
                serverSelectionTimeoutMS=5000,
                connectTimeoutMS=5000,
                socketTimeoutMS=5000
            )
            
            # Test connection
            client.admin.command('ping')
            client.close()
            logger.info("✓ Successfully connected to DocumentDB!")
            return True
            
        except ServerSelectionTimeoutError as e:
            logger.warning(f"Server selection timeout on attempt {i+1}/{max_retries}: {str(e)}")
            if i < max_retries - 1:
                logger.info(f"Waiting {current_delay} seconds before retry...")
                time.sleep(current_delay)
                # Exponential backoff with cap at 60 seconds
                current_delay = min(current_delay * 2, 60)
        except Exception as e:
            logger.error(f"Connection error on attempt {i+1}/{max_retries}: {type(e).__name__}: {str(e)}")
            if i < max_retries - 1:
                logger.info(f"Waiting {current_delay} seconds before retry...")
                time.sleep(current_delay)
                # Exponential backoff with cap at 60 seconds
                current_delay = min(current_delay * 2, 60)
    
    total_wait_time = max_retries * retry_delay
    raise Exception(f"DocumentDB did not become available after {total_wait_time} seconds ({max_retries} attempts)")


def init_collections(db):
    """Initialize DocumentDB collections and indexes"""
    try:
        # Collections for LibreChat
        collections = {
            'users': [
                {'key': {'email': 1}, 'unique': True},
                {'key': {'username': 1}, 'unique': True},
                {'key': {'createdAt': 1}}
            ],
            'conversations': [
                {'key': {'userId': 1, 'createdAt': -1}},
                {'key': {'endpoint': 1}},
                {'key': {'title': 'text'}}
            ],
            'messages': [
                {'key': {'conversationId': 1, 'createdAt': 1}},
                {'key': {'userId': 1}},
                {'key': {'parentMessageId': 1}}
            ],
            'presets': [
                {'key': {'userId': 1}},
                {'key': {'title': 1}}
            ],
            'files': [
                {'key': {'userId': 1, 'createdAt': -1}},
                {'key': {'type': 1}},
                {'key': {'filename': 1}}
            ],
            'assistants': [
                {'key': {'userId': 1}},
                {'key': {'name': 1}}
            ],
            'tools': [
                {'key': {'userId': 1}},
                {'key': {'name': 1}},
                {'key': {'type': 1}}
            ],
            'sessions': [
                {'key': {'userId': 1}},
                {'key': {'expiresAt': 1}, 'expireAfterSeconds': 0}
            ]
        }
        
        # Create collections and indexes
        for collection_name, indexes in collections.items():
            # Create collection if it doesn't exist
            if collection_name not in db.list_collection_names():
                db.create_collection(collection_name)
                logger.info(f"Created collection: {collection_name}")
            else:
                logger.info(f"Collection already exists: {collection_name}")
            
            # Create indexes
            collection = db[collection_name]
            for index_spec in indexes:
                try:
                    if 'expireAfterSeconds' in index_spec:
                        collection.create_index(
                            index_spec['key'],
                            expireAfterSeconds=index_spec['expireAfterSeconds']
                        )
                    else:
                        collection.create_index(
                            index_spec['key'],
                            unique=index_spec.get('unique', False)
                        )
                    logger.info(f"Created index on {collection_name}: {index_spec['key']}")
                except OperationFailure as e:
                    if "already exists" in str(e):
                        logger.info(f"Index already exists on {collection_name}: {index_spec['key']}")
                    else:
                        raise
        
        # Create system indexes for performance
        db.users.create_index({'lastLogin': -1})
        db.conversations.create_index({'updatedAt': -1})
        db.messages.create_index({'model': 1})
        
        logger.info("All collections and indexes created successfully")
        
    except Exception as e:
        logger.error(f"Error initializing collections: {str(e)}")
        raise


def handler(event, context):
    """Lambda handler for DocumentDB initialization"""
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Initialize response for CloudFormation
    response_data = {}
    physical_resource_id = event.get('PhysicalResourceId', 'docdb-init')
    
    # Handle CloudFormation custom resource lifecycle
    request_type = event.get('RequestType')
    if request_type in ['Delete', 'Update']:
        logger.info(f"Handling {request_type} request - no action needed for database initialization")
        # For Delete, we don't want to fail even if there are issues
        try:
            if request_type == 'Delete':
                logger.info("Delete request received - database resources will be cleaned up by CloudFormation")
        except Exception as e:
            logger.warning(f"Non-critical error during {request_type}: {str(e)}")
        
        return {
            'PhysicalResourceId': physical_resource_id,
            'Data': {'Message': f'{request_type} completed successfully'}
        }
    
    try:
        # Get database connection details from environment or event
        # Priority: ResourceProperties (from CloudFormation) > Direct event properties > Environment variables
        resource_props = event.get('ResourceProperties', {})
        db_host = resource_props.get('DBHost', event.get('DBHost', os.environ.get('DB_HOST')))
        db_port = resource_props.get('DBPort', event.get('DBPort', os.environ.get('DB_PORT', '27017')))
        db_name = resource_props.get('DBName', event.get('DBName', os.environ.get('DB_NAME', 'librechat')))
        secret_id = resource_props.get('SecretId', event.get('SecretId', os.environ.get('DB_SECRET_ID')))
        
        if not db_host:
            raise ValueError("Database host not provided")
        
        # Get credentials from Secrets Manager if provided
        if secret_id:
            credentials = get_db_credentials(secret_id)
            db_user = credentials.get('username', 'docdbadmin')
            db_password = credentials.get('password')
        else:
            db_user = event.get('DBUser', os.environ.get('DB_USER', 'docdbadmin'))
            db_password = event.get('DBPassword', os.environ.get('DB_PASSWORD'))
        
        if not db_password:
            raise ValueError("Database password not provided")
        
        # Validate network connectivity first
        logger.info("=" * 60)
        logger.info("PHASE 1: Network Connectivity Validation")
        logger.info("=" * 60)
        validate_network_connectivity(db_host, db_port, secret_id)
        
        # Wait for database to be available
        logger.info("=" * 60)
        logger.info("PHASE 2: DocumentDB Connection")
        logger.info("=" * 60)
        wait_for_db(db_host, db_port, db_user, db_password)
        
        # Connect to DocumentDB
        logger.info("=" * 60)
        logger.info("PHASE 3: Database Initialization")
        logger.info("=" * 60)
        
        conn_string = build_connection_string(db_user, db_password, db_host, db_port, use_direct_connection=True)
        logger.info(f"Connecting to DocumentDB with host: {db_host}")
        
        client = MongoClient(
            conn_string,
            serverSelectionTimeoutMS=5000,
            connectTimeoutMS=5000
        )
        
        logger.info(f"Connected to DocumentDB at {db_host}:{db_port}")
        
        # Get or create database
        db = client[db_name]
        
        # Initialize collections and indexes
        init_collections(db)
        
        # Close connection
        client.close()
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DocumentDB initialized successfully',
                'database': db_name,
                'collections': list(db.list_collection_names())
            })
        }
        
        # Return response for CloudFormation Custom Resource
        if event.get('RequestType'):
            response['PhysicalResourceId'] = f"docdb-init-{db_host}-{db_name}"
            response['Data'] = {
                'Message': 'DocumentDB initialized successfully'
            }
        
        logger.info("DocumentDB initialization completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Error in handler: {str(e)}")
        logger.error(f"Error type: {type(e).__name__}")
        
        import traceback
        logger.error(f"Full traceback: {traceback.format_exc()}")
        
        # Clean up connection if it exists
        if 'client' in locals() and client:
            try:
                client.close()
                logger.info("DocumentDB connection closed")
            except Exception as close_error:
                logger.warning(f"Error closing connection: {str(close_error)}")
        
        # For Delete operations, don't fail
        if request_type == 'Delete':
            logger.warning(f"Error during Delete operation (non-fatal): {str(e)}")
            return {
                'PhysicalResourceId': physical_resource_id,
                'Data': {'Message': 'Delete completed (with warnings)'}
            }
        
        response = {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
        
        if event.get('RequestType'):
            response['PhysicalResourceId'] = physical_resource_id
            response['Reason'] = str(e)
        
        raise