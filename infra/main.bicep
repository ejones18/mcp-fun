// =============================================================================
// MCP Server on Azure Container Apps - Infrastructure as Code
// =============================================================================
// This Bicep template deploys:
// - Azure Container Registry (ACR)
// - Azure Container Apps Environment
// - Azure Container App running the MCP server
// - Log Analytics workspace for monitoring
//
// Usage:
//   az deployment group create \
//     --resource-group <your-rg> \
//     --template-file main.bicep \
//     --parameters main.parameters.bicepparam
// =============================================================================

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Azure ML scoring endpoint URL')
@secure()
param amlScoreUrl string

@description('Azure ML API key for authentication')
@secure()
param amlApiKey string

@description('Azure ML deployment name (optional)')
param amlDefaultDeployment string = ''

@description('Minimum number of container replicas (0 = scale to zero)')
@minValue(0)
@maxValue(10)
param minReplicas int = 0

@description('Maximum number of container replicas')
@minValue(1)
@maxValue(30)
param maxReplicas int = 5

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var uniqueSuffix = uniqueString(resourceGroup().id)
var acrName = 'mcpacr${uniqueSuffix}'

// -----------------------------------------------------------------------------
// Resources
// -----------------------------------------------------------------------------

// Log Analytics Workspace for Container Apps logs
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'mcp-logs-${uniqueSuffix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { 
    adminUserEnabled: true 
  }
}

// Container Apps Environment
resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'mcp-env-${uniqueSuffix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Container App - MCP Server
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'mcp-server'
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['*']
          allowedHeaders: ['*']
        }
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        { name: 'acr-password', value: acr.listCredentials().passwords[0].value }
        { name: 'aml-api-key', value: amlApiKey }
        { name: 'aml-score-url', value: amlScoreUrl }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp-server'
          image: '${acr.properties.loginServer}/mcp-server:latest'
          resources: { 
            cpu: json('0.5')
            memory: '1Gi' 
          }
          env: [
            { name: 'AML_API_KEY', secretRef: 'aml-api-key' }
            { name: 'AML_SCORE_URL', secretRef: 'aml-score-url' }
            { name: 'AML_DEFAULT_DEPLOYMENT', value: amlDefaultDeployment }
            { name: 'PORT', value: '8080' }
          ]
        }
      ]
      scale: { 
        minReplicas: minReplicas
        maxReplicas: maxReplicas 
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Azure Container Registry login server')
output acrLoginServer string = acr.properties.loginServer

@description('Azure Container Registry name')
output acrName string = acr.name

@description('MCP server endpoint URL')
output mcpEndpoint string = 'https://${containerApp.properties.configuration.ingress.fqdn}/mcp/mcp'

@description('Container App name')
output containerAppName string = containerApp.name

@description('Container App FQDN')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
