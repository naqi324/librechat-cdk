import json
import logging
import os
import time
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
        raise


def wait_for_db(host, port, username, password, max_retries=30, retry_delay=10):
    """Wait for DocumentDB to become available"""
    for i in range(max_retries):
        try:
            # DocumentDB requires TLS
            client = MongoClient(
                f"mongodb://{username}:{password}@{host}:{port}/?tls=true&tlsCAFile=/opt/rds-ca-2019-root.pem&replicaSet=rs0",
                serverSelectionTimeoutMS=5000
            )
            # Test connection
            client.admin.command('ping')
            client.close()
            logger.info("DocumentDB is available")
            return True
        except ServerSelectionTimeoutError:
            logger.info(f"Waiting for DocumentDB... Attempt {i+1}/{max_retries}")
            if i < max_retries - 1:
                time.sleep(retry_delay)
        except Exception as e:
            logger.error(f"Error connecting to DocumentDB: {str(e)}")
            if i < max_retries - 1:
                time.sleep(retry_delay)
    
    raise Exception("DocumentDB did not become available in time")


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
    
    try:
        # Get database connection details from environment or event
        db_host = event.get('DBHost', os.environ.get('DB_HOST'))
        db_port = event.get('DBPort', os.environ.get('DB_PORT', '27017'))
        db_name = event.get('DBName', os.environ.get('DB_NAME', 'librechat'))
        secret_id = event.get('SecretId', os.environ.get('DB_SECRET_ID'))
        
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
        client = MongoClient(
            f"mongodb://{db_user}:{db_password}@{db_host}:{db_port}/?tls=true&tlsCAFile=/opt/rds-ca-2019-root.pem&replicaSet=rs0"
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
        
        response = {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
        
        if event.get('RequestType'):
            response['PhysicalResourceId'] = 'docdb-init-failed'
            response['Reason'] = str(e)
        
        raise