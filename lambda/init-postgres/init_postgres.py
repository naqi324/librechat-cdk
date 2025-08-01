import json
import logging
import os
import time
import psycopg2
import boto3

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


def wait_for_db(host, port, user, password, max_retries=None, retry_delay=None):
    # Get retry configuration from environment or use defaults
    if max_retries is None:
        max_retries = int(os.environ.get('MAX_RETRIES', '30'))  # Reduced from 90
    if retry_delay is None:
        retry_delay = int(os.environ.get('RETRY_DELAY', '5'))   # Reduced from 10
    """Wait for database to become available"""
    logger.info(f"Waiting for database at {host}:{port} with max retries: {max_retries}")
    logger.info(f"Using user: {user}")
    
    # Use exponential backoff for retries
    for i in range(max_retries):
        try:
            # Add more detailed connection parameters
            conn_params = {
                'host': host,
                'port': port,
                'user': user,
                'password': password,
                'database': 'postgres',  # Connect to default postgres database first
                'connect_timeout': 10,   # Increased from 5 to 10
                'sslmode': 'require',    # RDS requires SSL connections
                'options': '-c statement_timeout=30000'  # 30 second statement timeout
            }
            
            logger.info(f"Attempting connection with params: host={host}, port={port}, user={user}, sslmode=require")
            conn = psycopg2.connect(**conn_params)
            
            # Test the connection is actually working
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            
            conn.close()
            logger.info("Database is available and responding to queries")
            return True
            
        except psycopg2.OperationalError as e:
            error_msg = str(e)
            logger.warning(f"Database connection attempt {i+1}/{max_retries} failed: {error_msg}")
            
            # Check for specific error conditions
            if "could not connect to server" in error_msg:
                logger.info("Database server is not yet reachable, waiting...")
            elif "password authentication failed" in error_msg:
                logger.error("Authentication failed - check credentials")
                raise  # Don't retry on auth failures
            elif "SSL connection has been closed unexpectedly" in error_msg:
                logger.info("SSL handshake failed, database may still be starting up")
            
            if i < max_retries - 1:
                # Use exponential backoff with jitter
                delay = min(retry_delay * (1.5 ** min(i, 10)), 60) + (time.time() % 5)
                logger.info(f"Waiting {delay:.1f} seconds before retry...")
                time.sleep(delay)
                
        except Exception as e:
            logger.error(f"Unexpected error during connection attempt {i+1}: {type(e).__name__}: {str(e)}")
            if i < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise
    
    raise Exception(f"Database did not become available after {max_retries} attempts over ~{max_retries * retry_delay / 60:.1f} minutes")


def safe_close_connection(connection):
    """Safely close database connection"""
    if connection:
        try:
            if not connection.closed:
                safe_close_connection(connection)
                logger.info("Database connection closed")
        except Exception as e:
            logger.warning(f"Error closing connection: {str(e)}")


def init_pgvector(connection):
    """Initialize pgvector extension"""
    try:
        with connection.cursor() as cursor:
            # Create pgvector extension
            cursor.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            logger.info("pgvector extension created successfully")
            
            # Create embeddings table for RAG
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS embeddings (
                    id SERIAL PRIMARY KEY,
                    document_id VARCHAR(255) NOT NULL,
                    chunk_index INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    embedding vector(1536),
                    metadata JSONB,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            
            # Create indexes for better performance
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_embeddings_document_id 
                ON embeddings(document_id);
            """)
            
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_embeddings_embedding 
                ON embeddings USING ivfflat (embedding vector_cosine_ops)
                WITH (lists = 100);
            """)
            
            logger.info("Embeddings table and indexes created successfully")
            
            # Create function to update updated_at timestamp
            cursor.execute("""
                CREATE OR REPLACE FUNCTION update_updated_at_column()
                RETURNS TRIGGER AS $$
                BEGIN
                    NEW.updated_at = CURRENT_TIMESTAMP;
                    RETURN NEW;
                END;
                $$ language 'plpgsql';
            """)
            
            # Create trigger for updated_at
            cursor.execute("""
                CREATE TRIGGER update_embeddings_updated_at 
                BEFORE UPDATE ON embeddings 
                FOR EACH ROW 
                EXECUTE FUNCTION update_updated_at_column();
            """)
            
            logger.info("Database functions and triggers created successfully")
            
            connection.commit()
            
    except Exception as e:
        logger.error(f"Error initializing pgvector: {str(e)}")
        connection.rollback()
        raise


def handler(event, context):
    """Lambda handler for PostgreSQL initialization"""
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Initialize response for CloudFormation
    response_data = {}
    physical_resource_id = event.get('PhysicalResourceId', 'postgres-init')
    
    # Handle CloudFormation custom resource lifecycle
    request_type = event.get('RequestType')
    if request_type in ['Delete', 'Update']:
        logger.info(f"Handling {request_type} request - no action needed for database initialization")
        # For Delete, we don't want to fail even if there are issues
        try:
            # Optionally verify database still exists (but don't fail if it doesn't)
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
        db_port = resource_props.get('DBPort', event.get('DBPort', os.environ.get('DB_PORT', '5432')))
        db_name = resource_props.get('DBName', event.get('DBName', os.environ.get('DB_NAME', 'librechat')))
        secret_id = resource_props.get('SecretId', event.get('SecretId', os.environ.get('DB_SECRET_ID')))
        
        if not db_host:
            raise ValueError("Database host not provided")
        
        logger.info(f"Database endpoint: {db_host}:{db_port}")
        
        # Get credentials from Secrets Manager if provided
        if secret_id:
            logger.info(f"Retrieving credentials from secret: {secret_id}")
            credentials = get_db_credentials(secret_id)
            db_user = credentials.get('username', 'postgres')
            db_password = credentials.get('password')
            logger.info(f"Retrieved username from secret: {db_user}")
            # Log password length for debugging (not the actual password)
            logger.info(f"Retrieved password length: {len(db_password) if db_password else 0}")
        else:
            db_user = event.get('DBUser', os.environ.get('DB_USER', 'postgres'))
            db_password = event.get('DBPassword', os.environ.get('DB_PASSWORD'))
            logger.info("Using credentials from event/environment")
        
        if not db_password:
            raise ValueError("Database password not provided")
        
        # Wait for database to be available
        wait_for_db(db_host, db_port, db_user, db_password)
        
        # Common connection parameters
        conn_params = {
            'host': db_host,
            'port': db_port,
            'user': db_user,
            'password': db_password,
            'connect_timeout': 10,
            'sslmode': 'require',  # RDS requires SSL connections
            'options': '-c statement_timeout=30000'
        }
        
        # First, try to connect to the target database
        try:
            connection = psycopg2.connect(database=db_name, **conn_params)
            logger.info(f"Connected to database {db_name} on {db_host}:{db_port}")
        except psycopg2.OperationalError as e:
            if "does not exist" in str(e):
                # Database doesn't exist, create it
                logger.info(f"Database {db_name} does not exist, creating it...")
                
                # Connect to default postgres database
                connection = psycopg2.connect(database='postgres', **conn_params)
                connection.autocommit = True
                
                with connection.cursor() as cursor:
                    # Check if database exists (in case of race condition)
                    cursor.execute(
                        "SELECT 1 FROM pg_database WHERE datname = %s",
                        (db_name,)
                    )
                    if cursor.fetchone():
                        logger.info(f"Database {db_name} already exists (race condition)")
                    else:
                        # Create the database
                        cursor.execute(f'CREATE DATABASE "{db_name}"')
                        logger.info(f"Database {db_name} created successfully")
                
                safe_close_connection(connection)
                
                # Now connect to the new database
                connection = psycopg2.connect(database=db_name, **conn_params)
                logger.info(f"Connected to database {db_name}")
            else:
                logger.error(f"Failed to connect to database: {str(e)}")
                raise
        
        # Initialize pgvector
        init_pgvector(connection)
        
        # Close connection
        safe_close_connection(connection)
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'PostgreSQL initialized successfully',
                'database': db_name,
                'extensions': ['pgvector']
            })
        }
        
        # Return response for CloudFormation Custom Resource
        if event.get('RequestType'):
            response['PhysicalResourceId'] = f"postgres-init-{db_host}-{db_name}"
            response['Data'] = {
                'Message': 'PostgreSQL initialized successfully'
            }
        
        logger.info("PostgreSQL initialization completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Error in handler: {str(e)}")
        logger.error(f"Error type: {type(e).__name__}")
        logger.error(f"DB Host: {db_host if 'db_host' in locals() else 'not set'}")
        logger.error(f"DB Port: {db_port if 'db_port' in locals() else 'not set'}")
        logger.error(f"DB Name: {db_name if 'db_name' in locals() else 'not set'}")
        logger.error(f"Secret ID: {secret_id if 'secret_id' in locals() else 'not set'}")
        
        import traceback
        logger.error(f"Full traceback: {traceback.format_exc()}")
        
        # Clean up connection if it exists
        if 'connection' in locals():
            safe_close_connection(connection)
        
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
                'error': str(e),
                'error_type': type(e).__name__
            })
        }
        
        if event.get('RequestType'):
            response['PhysicalResourceId'] = physical_resource_id
            response['Reason'] = f"{type(e).__name__}: {str(e)}"
        
        raise