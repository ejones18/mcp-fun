"""
MCP Server for Azure ML Scoring - Deployed on Azure Container Apps.

This MCP server exposes an Azure ML managed online endpoint as a tool
that can be called from AI agents like Microsoft Copilot Studio or 
Azure AI Foundry agents.

Architecture:
- FastMCP with stateless HTTP transport (required for cloud deployment)
- FastAPI wrapper with lifespan management and CORS middleware
- MCP endpoint mounted at /mcp (accessible at /mcp/mcp)

References:
- FastMCP Pattern: https://github.com/joelborellis/MCP-server-fastapi-containerapp
- DNS Rebinding Fix: https://github.com/modelcontextprotocol/python-sdk/issues/1798
"""

import ast
import contextlib
import json
import os
import urllib.request
import urllib.error

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
import pandas as pd
import uvicorn


# =============================================================================
# Configuration (from environment variables)
# =============================================================================

AML_SCORE_URL = os.environ.get("AML_SCORE_URL", "")
AML_API_KEY = os.environ.get("AML_API_KEY", "")
AML_DEFAULT_DEPLOYMENT = os.environ.get("AML_DEFAULT_DEPLOYMENT", "")


# =============================================================================
# MCP Server Setup
# =============================================================================

# Create MCP server with DNS rebinding protection disabled for cloud deployment.
# This is REQUIRED when deploying to Azure Container Apps, App Service, or any
# cloud platform where the hostname differs from localhost.
# See: https://github.com/modelcontextprotocol/python-sdk/issues/1798
mcp = FastMCP(
    "azureml-mcp-server",
    stateless_http=True,
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)
)


# =============================================================================
# Helper Functions
# =============================================================================

def _validate_config():
    """Validate required configuration at runtime."""
    if not AML_SCORE_URL:
        raise RuntimeError("Missing AML_SCORE_URL environment variable")
    if not AML_API_KEY:
        raise RuntimeError("Missing AML_API_KEY environment variable")


# =============================================================================
# MCP Tools
# =============================================================================

@mcp.tool()
def invoke_azure_ml_endpoint(
    distributor_id: float,
    delivery_date: str,
) -> float:
    """
    Invoke an Azure ML managed online endpoint for prediction.
    
    This example calls a vaccine forecasting model, but you can modify this
    to call any Azure ML endpoint by changing the input data structure.
    
    Args:
        distributor_id: The distributor organization reference ID.
        delivery_date: The scheduled delivery date in "YYYY-MM-DD" format.
        
    Returns:
        The model prediction result.
        
    Raises:
        RuntimeError: If required environment variables are not set.
        Exception: If the Azure ML endpoint returns an error.
    """
    _validate_config()

    # Prepare request headers
    headers = {
        'Content-Type': 'application/json', 
        'Accept': 'application/json', 
        'Authorization': f'Bearer {AML_API_KEY}'
    }
    
    # Add deployment header if specified
    if AML_DEFAULT_DEPLOYMENT:
        headers["azureml-model-deployment"] = AML_DEFAULT_DEPLOYMENT

    # Create input dataframe (modify columns for your model)
    df = pd.DataFrame(
        [[float(distributor_id), delivery_date]], 
        columns=["ShipToDistributorOrgRefId", "ScheduledDeliveryDate"]
    )
        
    # Prepare request body
    data = {"input_data": df.to_dict(orient='split')}
    body = str.encode(json.dumps(data))
    
    # Make the request
    req = urllib.request.Request(AML_SCORE_URL, body, headers)
    
    try:
        response = urllib.request.urlopen(req)
        result = response.read()
        return ast.literal_eval(result.decode())[0]
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error body'
        raise Exception(f"Azure ML scoring failed: {e.code} {e.reason} - {error_body}")


# =============================================================================
# FastAPI Application
# =============================================================================

@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage MCP session manager lifecycle."""
    async with mcp.session_manager.run():
        yield


# Create FastAPI app with lifespan management
app = FastAPI(
    title="MCP Server for Azure ML",
    description="Model Context Protocol server exposing Azure ML endpoints as tools",
    lifespan=lifespan
)

# Add CORS middleware (required for browser-based clients)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount MCP server at /mcp path
# The MCP endpoint will be available at /mcp/mcp
app.mount("/mcp", mcp.streamable_http_app())


@app.get("/health")
async def health():
    """Health check endpoint for container orchestration."""
    return {"status": "healthy"}


@app.get("/")
async def root():
    """Root endpoint with service information."""
    return {
        "service": "MCP Server for Azure ML",
        "mcp_endpoint": "/mcp/mcp",
        "health_endpoint": "/health"
    }


# =============================================================================
# Entry Point
# =============================================================================

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"Starting MCP server on port {port}...")
    print(f"MCP endpoint: http://localhost:{port}/mcp/mcp")
    uvicorn.run(app, host="0.0.0.0", port=port)
