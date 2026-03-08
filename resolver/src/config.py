"""
Configuration module - loads environment variables from .env files.
This module MUST be imported before any other resolver modules that need env vars.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Get absolute path to the config directory, regardless of working directory
_THIS_FILE = Path(__file__).resolve()
_SRC_DIR = _THIS_FILE.parent
_RESOLVER_DIR = _SRC_DIR.parent
_CONFIG_DIR = _RESOLVER_DIR / "config"

# Load .env files using absolute paths
_env_file = _CONFIG_DIR / ".env"
_env_example = _CONFIG_DIR / ".env.example"

# Try .env first, fall back to .env.example
if _env_file.exists():
    load_dotenv(_env_file, override=True)
elif _env_example.exists():
    load_dotenv(_env_example, override=True)

# Export config values with validation
def _get_required(key: str) -> str:
    val = os.getenv(key, "")
    if not val:
        raise ValueError(f"Missing required environment variable: {key}")
    return val

def _get_optional(key: str, default: str = "") -> str:
    return os.getenv(key, default)

# Network config
NETWORK_NAME = _get_optional("NETWORK_NAME", "base-sepolia")
CHAIN_ID = int(_get_optional("CHAIN_ID", "84532"))
RPC_URL = _get_optional("RPC_URL", "")

# Contract config
ESCROW_CONTRACT_ADDRESS = _get_optional("ESCROW_CONTRACT_ADDRESS", "")

# Resolver API config
RESOLVER_BASE_URL = _get_optional("RESOLVER_BASE_URL", "http://127.0.0.1:8080")
RESOLVER_API_TOKEN = _get_optional("RESOLVER_API_TOKEN", "")

# Signer config
RESOLVER_SIGNER_PRIVATE_KEY = _get_optional("RESOLVER_SIGNER_PRIVATE_KEY", "")
RESOLVER_SIGNER_ADDRESS = _get_optional("RESOLVER_SIGNER_ADDRESS", "")

# AI assessor
ANTHROPIC_API_KEY = _get_optional("ANTHROPIC_API_KEY", "")

# Optional
POLL_INTERVAL_SECONDS = int(_get_optional("POLL_INTERVAL_SECONDS", "30"))
LOG_LEVEL = _get_optional("LOG_LEVEL", "INFO")


def validate_chain_config():
    """Validate that required chain config is present."""
    missing = []
    if not RPC_URL:
        missing.append("RPC_URL")
    if not ESCROW_CONTRACT_ADDRESS:
        missing.append("ESCROW_CONTRACT_ADDRESS")
    if not RESOLVER_SIGNER_PRIVATE_KEY:
        missing.append("RESOLVER_SIGNER_PRIVATE_KEY")
    
    if missing:
        raise ValueError(f"Missing required env vars: {', '.join(missing)}")
