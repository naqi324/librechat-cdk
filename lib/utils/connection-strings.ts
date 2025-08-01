/**
 * Utility functions for building standardized connection strings
 */

export interface DocumentDBConnectionOptions {
  username: string;
  password: string;
  host: string;
  port?: number;
  database?: string;
  directConnection?: boolean;
  tlsCAFile?: string;
}

/**
 * Build a standardized DocumentDB connection string
 * @param options Connection options
 * @returns MongoDB connection string
 */
export function buildDocumentDBConnectionString(options: DocumentDBConnectionOptions): string {
  const {
    username,
    password,
    host,
    port = 27017,
    database,
    directConnection = false,
    tlsCAFile = '/opt/librechat/rds-ca-2019-root.pem',
  } = options;

  // Escape username and password for URL
  const escapedUsername = encodeURIComponent(username);
  const escapedPassword = encodeURIComponent(password);

  let baseUrl = `mongodb://${escapedUsername}:${escapedPassword}@${host}:${port}`;

  if (database) {
    baseUrl += `/${database}`;
  }

  const params: Record<string, string> = {
    tls: 'true',
    tlsCAFile: tlsCAFile,
    retryWrites: 'false', // DocumentDB doesn't support retryWrites
  };

  if (directConnection) {
    // For Lambda initialization - direct connection to single node
    params.directConnection = 'true';
  } else {
    // For application usage - connect to replica set
    params.replicaSet = 'rs0';
    params.readPreference = 'secondaryPreferred';
  }

  const queryString = Object.entries(params)
    .map(([key, value]) => `${key}=${value}`)
    .join('&');

  return `${baseUrl}/?${queryString}`;
}

/**
 * Build connection string template for use in shell scripts
 * Uses shell variable substitution for credentials
 */
export function buildDocumentDBConnectionTemplate(host: string, port: number = 27017): string {
  return `mongodb://$(cat /tmp/docdb-secrets.json | jq -r .username):$(cat /tmp/docdb-secrets.json | jq -r .password)@${host}:${port}/?tls=true&tlsCAFile=/opt/librechat/rds-ca-2019-root.pem&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false`;
}

/**
 * Build connection string template for ECS with environment variables
 */
export function buildDocumentDBConnectionTemplateECS(host: string, port: number = 27017): string {
  return `mongodb://\${MONGO_USER}:\${MONGO_PASSWORD}@${host}:${port}/?tls=true&tlsCAFile=/opt/librechat/rds-ca-2019-root.pem&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false`;
}
