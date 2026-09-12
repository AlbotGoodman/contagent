FROM python:3.13-slim-bookworm

# Create non-root user and group as well as hardcoded IDs (for now)
RUN groupadd -g 1000 devgroup && useradd -u 1000 -g devgroup -m -d /home/superuser superuser

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install UV to system-wide location
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN cp /root/.local/bin/uv /usr/local/bin/uv && \
    chmod 0755 /usr/local/bin/uv
ENV PATH="/usr/local/bin:$PATH"

# Install OpenCode to system-wide location
RUN curl -fsSL https://opencode.ai/install -o /tmp/install-opencode.sh && \
    bash /tmp/install-opencode.sh --no-modify-path && \
    cp /root/.opencode/bin/opencode /usr/local/bin/opencode && \
    chmod 0755 /usr/local/bin/opencode && \
    rm -f /tmp/install-opencode.sh

# Ensure temp directories exist for read-only mode
RUN mkdir -p /tmp /run && chmod 1777 /tmp /run

# Set working directory
WORKDIR /workspace

# Switch to non-root user
USER superuser

# Default command
CMD ["/bin/bash"]