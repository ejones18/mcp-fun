# MCP Server on Azure Container Apps

Deploy a [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server to Azure Container Apps that exposes Azure ML endpoints as tools for AI agents.

## 🎯 What This Does

This project creates an MCP server that:
- Runs on **Azure Container Apps** (serverless, scales to zero)
- Exposes **Azure ML managed online endpoints** as MCP tools
- Works with **Azure AI Foundry agents**, **Copilot Studio**, and any MCP-compatible client

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  AI Foundry     │────▶│  MCP Server     │────▶│  Azure ML       │
│  Agent          │ MCP │  (Container App)│HTTP │  Endpoint       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## 📋 Prerequisites

1. **Azure Subscription** with permissions to create resources
2. **Azure ML Managed Online Endpoint** deployed and running
3. **Azure CLI** installed ([Install Guide](https://learn.microsoft.com/cli/azure/install-azure-cli))
4. **Docker** installed for local development and building images
5. **Python 3.11+** for local testing

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <your-repo-url>
cd <your-repo-folder>

# Copy environment template
cp .env.sample .env   # Linux/macOS
copy .env.sample .env  # Windows CMD
Copy-Item .env.sample .env  # Windows PowerShell

# Edit .env with your Azure ML endpoint details
# Get these from Azure ML Studio > Endpoints > Your endpoint > Consume tab
```

### 2. Test Locally

```bash
# Create virtual environment
python -m venv .venv
.venv\Scripts\activate  # Windows
# source .venv/bin/activate  # Linux/Mac

# Install dependencies
pip install -r requirements.txt

# Run the server
python server.py
```

Test with curl:
```bash
curl -X POST http://localhost:8080/mcp/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### 3. Deploy to Azure

#### Bash (Linux/macOS/WSL)
```bash
# Login to Azure
az login

# Create resource group
az group create --name rg-mcp-server --location eastus

# Update parameters with your Azure ML credentials
# Edit infra/main.parameters.bicepparam

# Deploy infrastructure
az deployment group create \
  --resource-group rg-mcp-server \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.bicepparam

# Get the ACR name from the output
ACR_NAME=$(az deployment group show -g rg-mcp-server -n main --query properties.outputs.acrName.value -o tsv)

# Build and push Docker image
az acr login --name $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/mcp-server:latest .
docker push $ACR_NAME.azurecr.io/mcp-server:latest

# Restart the container app to pull the new image
az containerapp update \
  --name mcp-server \
  --resource-group rg-mcp-server
```

#### PowerShell (Windows)
```powershell
# Login to Azure
az login

# Create resource group
az group create --name rg-mcp-server --location eastus

# Update parameters with your Azure ML credentials
# Edit infra/main.parameters.bicepparam

# Deploy infrastructure
az deployment group create `
  --resource-group rg-mcp-server `
  --template-file infra/main.bicep `
  --parameters infra/main.parameters.bicepparam

# Get the ACR name from the output
$ACR_NAME = az deployment group show -g rg-mcp-server -n main --query properties.outputs.acrName.value -o tsv

# Build and push Docker image
az acr login --name $ACR_NAME
docker build -t "$ACR_NAME.azurecr.io/mcp-server:latest" .
docker push "$ACR_NAME.azurecr.io/mcp-server:latest"

# Restart the container app to pull the new image
az containerapp update `
  --name mcp-server `
  --resource-group rg-mcp-server
```

### 4. Get Your MCP Endpoint

```bash
az deployment group show \
  --resource-group rg-mcp-server \
  --name main \
  --query properties.outputs.mcpEndpoint.value -o tsv
```

Your MCP endpoint will be: `https://<your-app>.azurecontainerapps.io/mcp/mcp`

## 🤖 Connect to Azure AI Foundry

1. Go to [Azure AI Foundry](https://ai.azure.com)
2. Navigate to your project > **Agent** > **Tools**
3. Click **+ New tool** > **MCP Tool**
4. Configure:
   - **Name**: `AzureMLScoring` (or your preferred name)
   - **Server URL**: `https://<your-app>.azurecontainerapps.io/mcp/mcp`
   - **Auth Type**: None (the app uses managed secrets internally)
5. Save and test the tool in your agent

## 📁 Project Structure

```
├── server.py              # MCP server with Azure ML tool
├── requirements.txt       # Python dependencies
├── Dockerfile            # Container image definition
├── .env.sample           # Environment variables template
├── .gitignore            # Git ignore rules
├── .dockerignore         # Docker build exclusions
└── infra/
    ├── main.bicep              # Azure infrastructure definition
    └── main.parameters.bicepparam  # Deployment parameters
```

## 🔧 Customizing the Tool

> ⚠️ **Important**: The example code is configured for an abitrary forecasting model. You **must** modify `server.py` to match your own Azure ML model's expected input schema (column names, data types) and output format.

Edit `server.py` to modify the MCP tool:

1. **Change the function parameters** to match your model's inputs
2. **Update the DataFrame columns** to match your model's expected schema
3. **Modify the docstring** to describe your tool accurately (this is what AI agents see)

```python
@mcp.tool()
def invoke_azure_ml_endpoint(
    # Change these parameters to match your model's inputs
    your_param_1: float,
    your_param_2: str,
) -> float:
    """
    Update this docstring to describe your tool - AI agents use this to understand
    when and how to call your tool.
    """
    # Modify the DataFrame columns to match your model's expected schema
    df = pd.DataFrame(
        [[float(your_param_1), your_param_2]], 
        columns=["YourColumn1", "YourColumn2"]  # Change to your model's column names
    )
    
    # The payload structure may need adjustment - test your model in the 
    # Azure ML Studio 'Test' tab to see the expected format
    data = {"input_data": df.to_dict(orient='split')}
    # ... rest of the function
```

## 🐛 Troubleshooting

### 421 Misdirected Request Error

If you see this error in logs, ensure you have DNS rebinding protection disabled:

```python
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

mcp = FastMCP(
    "your-server-name",
    stateless_http=True,
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)
)
```

See: [GitHub Issue #1798](https://github.com/modelcontextprotocol/python-sdk/issues/1798)

### Container Not Starting

Check logs:
```bash
az containerapp logs show \
  --name mcp-server \
  --resource-group rg-mcp-server \
  --follow
```

### Azure ML Endpoint Errors

Verify your endpoint is accessible:
```bash
curl -X POST $AML_SCORE_URL \
  -H "Authorization: Bearer $AML_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input_data": {"columns": ["col1"], "data": [[1]]}}'
```

## 📚 Resources

- [Model Context Protocol](https://modelcontextprotocol.io/)
- [FastMCP Documentation](https://gofastmcp.com/)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [Azure ML Managed Endpoints](https://learn.microsoft.com/azure/machine-learning/concept-endpoints)
- [Azure AI Foundry](https://ai.azure.com)

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.
