import json
import logging
import os
import time
import socket
import boto3
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure

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


def test_network_connectivity(host, port):
    """Test basic network connectivity to DocumentDB"""
    try:
        # Test DNS resolution
        logger.info(f"Testing DNS resolution for {host}")
        ip_address = socket.gethostbyname(host)
        logger.info(f"DNS resolved {host} to {ip_address}")
        
        # Test TCP connectivity
        logger.info(f"Testing TCP connectivity to {ip_address}:{port}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((ip_address, int(port)))
        sock.close()
        
        if result == 0:
            logger.info(f"Successfully connected to {ip_address}:{port}")
            return True
        else:
            logger.error(f"Failed to connect to {ip_address}:{port} - Error code: {result}")
            return False
    except socket.gaierror as e:
        logger.error(f"DNS resolution failed for {host}: {str(e)}")
        return False
    except Exception as e:
        logger.error(f"Network connectivity test failed: {str(e)}")
        return False


def wait_for_db(host, port, username, password, max_retries=None, retry_delay=None):
    """Wait for DocumentDB to become available"""
    # Use environment variables if not provided
    if max_retries is None:
        max_retries = int(os.environ.get('MAX_RETRIES', '30'))  # Reduced from 60
    if retry_delay is None:
        retry_delay = int(os.environ.get('RETRY_DELAY', '10'))
    
    logger.info(f"Starting DocumentDB connection process")
    logger.info(f"Host: {host}, Port: {port}")
    logger.info(f"Max retries: {max_retries}, Retry delay: {retry_delay}s")
    
    # First test network connectivity
    if not test_network_connectivity(host, port):
        raise Exception(f"Cannot establish network connectivity to DocumentDB at {host}:{port}")
    
    for i in range(max_retries):
        try:
            # Build connection string without replica set first
            conn_string = f"mongodb://{username}:{password}@{host}:{port}/?tls=true&tlsCAFile=/opt/rds-ca-2019-root.pem"
            logger.info(f"Attempting connection {i+1}/{max_retries}")
            
            # DocumentDB requires TLS
            client = MongoClient(
                conn_string,
                serverSelectionTimeoutMS=5000,
                connectTimeoutMS=5000,
                socketTimeoutMS=5000,
                directConnection=True  # Add direct connection for single node
            )
            
            # Test connection
            client.admin.command('ping')
            client.close()
            logger.info("Successfully connected to DocumentDB!")
            return True
            
        except ServerSelectionTimeoutError as e:
            logger.warning(f"Server selection timeout on attempt {i+1}/{max_retries}: {str(e)}")
            if i < max_retries - 1:
                time.sleep(retry_delay)
        except Exception as e:
            logger.error(f"Connection error on attempt {i+1}/{max_retries}: {type(e).__name__}: {str(e)}")
            if i < max_retries - 1:
                time.sleep(retry_delay)
    
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
        
        # Wait for database to be available
        wait_for_db(db_host, db_port, db_user, db_password)
        
        # Connect to DocumentDB
        # Note: In Lambda, the CA file should be included in the deployment package
        conn_string = f"mongodb://{db_user}:{db_password}@{db_host}:{db_port}/?tls=true&tlsCAFile=/opt/rds-ca-2019-root.pem"
        logger.info(f"Connecting to DocumentDB with host: {db_host}")
        
        client = MongoClient(
            conn_string,
            serverSelectionTimeoutMS=5000,
            connectTimeoutMS=5000,
            directConnection=True
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