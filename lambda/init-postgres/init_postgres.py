import json
import logging
import os
import time
import psycopg2
from psycopg2 import sql
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
        raise


def wait_for_db(host, port, max_retries=30, retry_delay=10):
    """Wait for database to become available"""
    for i in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=host,
                port=port,
                user='postgres',
                password='postgres',
                connect_timeout=5
            )
            conn.close()
            logger.info("Database is available")
            return True
        except Exception as e:
            logger.info(f"Waiting for database... Attempt {i+1}/{max_retries}")
            if i < max_retries - 1:
                time.sleep(retry_delay)
    
    raise Exception("Database did not become available in time")


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
    
    try:
        # Get database connection details from environment or event
        db_host = event.get('DBHost', os.environ.get('DB_HOST'))
        db_port = event.get('DBPort', os.environ.get('DB_PORT', '5432'))
        db_name = event.get('DBName', os.environ.get('DB_NAME', 'librechat'))
        secret_id = event.get('SecretId', os.environ.get('DB_SECRET_ID'))
        
        if not db_host:
            raise ValueError("Database host not provided")
        
        # Wait for database to be available
        wait_for_db(db_host, db_port)
        
        # Get credentials from Secrets Manager if provided
        if secret_id:
            credentials = get_db_credentials(secret_id)
            db_user = credentials.get('username', 'postgres')
            db_password = credentials.get('password')
        else:
            db_user = event.get('DBUser', os.environ.get('DB_USER', 'postgres'))
            db_password = event.get('DBPassword', os.environ.get('DB_PASSWORD'))
        
        if not db_password:
            raise ValueError("Database password not provided")
        
        # Connect to PostgreSQL
        connection = psycopg2.connect(
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password
        )
        
        logger.info(f"Connected to database {db_name} on {db_host}:{db_port}")
        
        # Initialize pgvector
        init_pgvector(connection)
        
        # Close connection
        connection.close()
        
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
        
        response = {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
        
        if event.get('RequestType'):
            response['PhysicalResourceId'] = 'postgres-init-failed'
            response['Reason'] = str(e)
        
        raise