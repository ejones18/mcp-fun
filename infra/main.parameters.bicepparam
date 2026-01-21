// =============================================================================
// Parameters for MCP Server Deployment
// =============================================================================
// Fill in the values below before deploying.
// You can get these from your Azure ML workspace > Endpoints > Consume tab.
// =============================================================================

using './main.bicep'

// REQUIRED: Your Azure ML endpoint URL
// Example: https://your-workspace.uksouth.inference.ml.azure.com/score
param amlScoreUrl = '<YOUR_AZURE_ML_ENDPOINT_URL>'

// REQUIRED: Your Azure ML API key
// Get this from Azure ML Studio > Endpoints > Your endpoint > Consume > Primary key
param amlApiKey = '<YOUR_AZURE_ML_API_KEY>'

// OPTIONAL: Specific deployment name (leave empty to use default)
param amlDefaultDeployment = ''

// OPTIONAL: Scaling configuration
param minReplicas = 0  // Scale to zero when not in use (cost saving)
param maxReplicas = 5
