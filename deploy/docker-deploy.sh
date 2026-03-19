#!/bin/bash
# =============================================================================
# Sub2API Docker Deployment Preparation Script
# =============================================================================
# This script prepares deployment files for Sub2API:
#   - Resolves the latest stable release tag and downloads matching deploy files
#   - Generates secure secrets (JWT_SECRET, TOTP_ENCRYPTION_KEY, POSTGRES_PASSWORD, REDIS_PASSWORD, ADMIN_PASSWORD)
#   - Creates necessary data directories
#
# After running this script, you can start services with:
#   docker compose up -d
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

GITHUB_REPO="${GITHUB_REPO:-Wei-Shaw/sub2api}"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}"
GITHUB_RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}"
DEPLOY_REF=""

# Print colored message
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Generate random secret
generate_secret() {
    local bytes="${1:-32}"
    openssl rand -hex "${bytes}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Resolve deployment ref (latest release by default, fallback to main)
resolve_download_ref() {
    if [ -n "${SUB2API_REF:-}" ]; then
        DEPLOY_REF="${SUB2API_REF}"
        print_info "Using custom deployment ref: ${DEPLOY_REF}"
        return
    fi

    print_info "Resolving latest stable release..."
    local latest_tag=""

    if command_exists curl; then
        latest_tag=$(curl -fsSL --connect-timeout 10 --max-time 30 "${GITHUB_API_URL}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)
    elif command_exists wget; then
        latest_tag=$(wget -qO- "${GITHUB_API_URL}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)
    fi

    if [ -n "${latest_tag}" ]; then
        DEPLOY_REF="${latest_tag}"
        print_success "Using latest stable release: ${DEPLOY_REF}"
        return
    fi

    DEPLOY_REF="main"
    print_warning "Failed to resolve latest release, falling back to main branch files."
}

# Download a file from the selected deployment ref
download_deploy_file() {
    local source_name="$1"
    local target_name="$2"
    local url="${GITHUB_RAW_BASE_URL}/${DEPLOY_REF}/deploy/${source_name}"

    if command_exists curl; then
        curl -fsSL "${url}" -o "${target_name}"
    else
        wget -q "${url}" -O "${target_name}"
    fi
}

# Update .env with a generated or resolved value
set_env_value() {
    local key="$1"
    local value="$2"

    if ! grep -q "^${key}=" .env; then
        return
    fi

    if sed --version >/dev/null 2>&1; then
        sed -i "s#^${key}=.*#${key}=${value}#" .env
    else
        sed -i '' "s#^${key}=.*#${key}=${value}#" .env
    fi
}

# Main installation function
main() {
    echo ""
    echo "=========================================="
    echo "  Sub2API Deployment Preparation"
    echo "=========================================="
    echo ""

    # Check if openssl is available
    if ! command_exists openssl; then
        print_error "openssl is not installed. Please install openssl first."
        exit 1
    fi

    resolve_download_ref

    # Check if deployment already exists
    if [ -f "docker-compose.yml" ] && [ -f ".env" ]; then
        print_warning "Deployment files already exist in current directory."
        read -p "Overwrite existing files? (y/N): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Cancelled."
            exit 0
        fi
    fi

    # Download docker-compose.local.yml and save as docker-compose.yml
    print_info "Downloading docker-compose.yml from ${DEPLOY_REF}..."
    if ! command_exists curl && ! command_exists wget; then
        print_error "Neither curl nor wget is installed. Please install one of them."
        exit 1
    fi
    download_deploy_file "docker-compose.local.yml" "docker-compose.yml"
    print_success "Downloaded docker-compose.yml"

    # Download .env.example
    print_info "Downloading .env.example from ${DEPLOY_REF}..."
    download_deploy_file ".env.example" ".env.example"
    print_success "Downloaded .env.example"

    # Generate .env file with auto-generated secrets
    print_info "Generating secure secrets..."
    echo ""

    # Generate secrets
    JWT_SECRET=$(generate_secret)
    TOTP_ENCRYPTION_KEY=$(generate_secret)
    POSTGRES_PASSWORD=$(generate_secret)
    REDIS_PASSWORD=$(generate_secret)
    ADMIN_PASSWORD=$(generate_secret 12)

    # Create .env from .env.example
    cp .env.example .env

    # Update .env with generated secrets (cross-platform compatible)
    set_env_value "JWT_SECRET" "${JWT_SECRET}"
    set_env_value "TOTP_ENCRYPTION_KEY" "${TOTP_ENCRYPTION_KEY}"
    set_env_value "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD}"
    set_env_value "REDIS_PASSWORD" "${REDIS_PASSWORD}"
    set_env_value "ADMIN_PASSWORD" "${ADMIN_PASSWORD}"

    if [ "${DEPLOY_REF}" != "main" ]; then
        SUB2API_VERSION="${DEPLOY_REF#v}"
        set_env_value "SUB2API_VERSION" "${SUB2API_VERSION}"
        print_info "Pinned SUB2API_VERSION=${SUB2API_VERSION}"
    fi

    # Create data directories
    print_info "Creating data directories..."
    mkdir -p data postgres_data redis_data
    print_success "Created data directories"

    # Set secure permissions for .env file (readable/writable only by owner)
    chmod 600 .env
    echo ""

    # Display completion message
    echo "=========================================="
    echo "  Preparation Complete!"
    echo "=========================================="
    echo ""
    echo "Deployment source:"
    echo "  Repository:            ${GITHUB_REPO}"
    echo "  Deployment ref:        ${DEPLOY_REF}"
    if [ -n "${SUB2API_VERSION:-}" ]; then
        echo "  Pinned image version:  ${SUB2API_VERSION}"
    fi
    echo ""
    echo "Generated secure credentials:"
    echo "  POSTGRES_PASSWORD:     ${POSTGRES_PASSWORD}"
    echo "  REDIS_PASSWORD:        ${REDIS_PASSWORD}"
    echo "  JWT_SECRET:            ${JWT_SECRET}"
    echo "  TOTP_ENCRYPTION_KEY:   ${TOTP_ENCRYPTION_KEY}"
    echo "  ADMIN_PASSWORD:        ${ADMIN_PASSWORD}"
    echo ""
    print_warning "These credentials have been saved to .env file."
    print_warning "Please keep them secure and do not share publicly!"
    echo ""
    echo "Directory structure:"
    echo "  docker-compose.yml        - Docker Compose configuration"
    echo "  .env                      - Environment variables (generated secrets)"
    echo "  .env.example              - Example template (for reference)"
    echo "  data/                     - Application data (will be created on first run)"
    echo "  postgres_data/            - PostgreSQL data"
    echo "  redis_data/               - Redis data"
    echo ""
    echo "Next steps:"
    echo "  1. (Optional) Edit .env to customize configuration"
    echo "  2. Start services:"
    echo "     docker compose up -d"
    echo ""
    echo "  3. View logs:"
    echo "     docker compose logs -f sub2api"
    echo ""
    echo "  4. Access Web UI:"
    echo "     http://localhost:8080"
    echo ""
    print_info "To upgrade later, change SUB2API_VERSION in .env and run: docker compose pull sub2api && docker compose up -d sub2api"
    echo ""
}

# Run main function
main "$@"
