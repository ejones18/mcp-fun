# =============================================================================
# MCP Server on Azure Container Apps
# =============================================================================
# This Dockerfile creates a production-ready container for running an MCP server
# that exposes Azure ML endpoints as tools for AI agents.
#
# Build: docker build -t mcp-server .
# Run:   docker run -p 8080:8080 --env-file .env mcp-server
# =============================================================================

FROM python:3.11-slim

# Install curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Install dependencies (cached layer)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY server.py .

# Set ownership and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

# Azure Container Apps sets PORT env var; default to 8080
EXPOSE 8080
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

CMD ["python", "server.py"]
