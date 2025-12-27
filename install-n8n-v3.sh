#!/bin/bash
###############################################################################
# N8N PRODUCTION INSTALLER v3.3 - DIAGNOSTIC & FIX
# 
# Mejoras v3.3:
# ✓ Diagnóstico completo de errores
# ✓ Detección de por qué n8n no arranca
# ✓ Validación exhaustiva paso a paso
# ✓ Logs detallados de cada error
# ✓ Solución automática de problemas comunes
###############################################################################

set -e
trap 'handle_error $LINENO' ERR

# Variables
SCRIPT_VERSION="3.3"
INSTALL_DIR="/opt/n8n-production"
LOG_DIR="/var/log/n8n"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="$INSTALL_DIR/.install_state"

# Colores
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; M='\033[0;35m'
W='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# Recursos
TOTAL_CPUS=0
TOTAL_RAM_GB=0
N8N_CPU_LIMIT=""
N8N_MEM_LIMIT=""
POSTGRES_CPU_LIMIT=""
POSTGRES_MEM_LIMIT=""
REDIS_CPU_LIMIT=""
REDIS_MEM_LIMIT=""

# Credenciales
DOMAIN=""
EMAIL=""
PGPASS=""
ADMIN_USER=""
ADMIN_PASS=""
ENC_KEY=""

declare -A STEPS=(
    ["deps"]="false"
    ["struct"]="false"
    ["nginx"]="false"
    ["ssl"]="false"
    ["imgs"]="false"
    ["svcs"]="false"
    ["maint"]="false"
)

# ============================================================================
# UI
# ============================================================================

handle_error() {
    echo ""
    echo -e "${R}${BOLD}✗ ERROR LÍNEA $1${NC}"
    echo -e "${Y}Log: $LOG_FILE${NC}"
    save_state
    exit 1
}

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok() { echo -e "${G}✓${NC} $1"; log "OK: $1"; }
err() { echo -e "${R}✗${NC} $1"; log "ERR: $1"; }
info() { echo -e "${B}ℹ${NC} $1"; log "INFO: $1"; }
warn() { echo -e "${Y}⚠${NC} $1"; log "WARN: $1"; }

header() {
    echo ""; echo -e "${C}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC} ${W}${BOLD}$1${NC}"; echo -e "${C}╚════════════════════════════════════════════════════════════════╝${NC}"; echo ""
}

step() { echo ""; echo -e "${M}▶${NC} ${BOLD}$1${NC}"; }

banner() {
    clear
    echo -e "${C}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║     🚀 N8N INSTALLER v3.3 - DIAGNOSTIC & ROBUST                     ║
║     ✓ Detección de Errores  ✓ Diagnóstico Completo                 ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ============================================================================
# ESTADO
# ============================================================================

save_state() {
    mkdir -p "$INSTALL_DIR"
    declare -p STEPS > "$STATE_FILE" 2>/dev/null || true
}

load_state() {
    [ -f "$STATE_FILE" ] && source "$STATE_FILE" 2>/dev/null || true
}

mark() {
    STEPS[$1]="true"
    save_state
}

done_step() {
    [[ "${STEPS[$1]}" == "true" ]]
}

# ============================================================================
# RECURSOS
# ============================================================================

detect_resources() {
    header "DETECCIÓN DE RECURSOS"
    
    TOTAL_CPUS=$(nproc)
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    TOTAL_RAM_GB=$((ram_mb / 1024))
    
    info "CPUs: $TOTAL_CPUS"
    info "RAM:  ${TOTAL_RAM_GB} GB"
    
    [ "$TOTAL_CPUS" -lt 2 ] && { err "Mínimo 2 CPUs"; exit 1; }
    [ "$ram_mb" -lt 3500 ] && { err "Mínimo 4 GB RAM"; exit 1; }
    
    ok "Recursos suficientes"
}

calculate_limits() {
    header "CÁLCULO DE LÍMITES"
    
    # Dejar 0.2 CPUs para sistema
    local usable_cpus=$(awk "BEGIN {print $TOTAL_CPUS - 0.2}")
    
    if [ "$TOTAL_CPUS" -eq 2 ]; then
        N8N_CPU_LIMIT="1.0"
        POSTGRES_CPU_LIMIT="0.5"
        REDIS_CPU_LIMIT="0.3"
        
        if [ "$TOTAL_RAM_GB" -ge 8 ]; then
            N8N_MEM_LIMIT="3072M"
            POSTGRES_MEM_LIMIT="1536M"
            REDIS_MEM_LIMIT="768M"
        else
            N8N_MEM_LIMIT="2048M"
            POSTGRES_MEM_LIMIT="1024M"
            REDIS_MEM_LIMIT="512M"
        fi
    elif [ "$TOTAL_CPUS" -eq 4 ]; then
        N8N_CPU_LIMIT="2.5"
        POSTGRES_CPU_LIMIT="1.0"
        REDIS_CPU_LIMIT="0.5"
        
        N8N_MEM_LIMIT="4096M"
        POSTGRES_MEM_LIMIT="2560M"
        REDIS_MEM_LIMIT="1024M"
    else
        N8N_CPU_LIMIT="5.0"
        POSTGRES_CPU_LIMIT="2.0"
        REDIS_CPU_LIMIT="1.0"
        
        N8N_MEM_LIMIT="8192M"
        POSTGRES_MEM_LIMIT="4096M"
        REDIS_MEM_LIMIT="2048M"
    fi
    
    info "Límites calculados:"
    echo "  n8n:        $N8N_CPU_LIMIT CPUs, $N8N_MEM_LIMIT"
    echo "  PostgreSQL: $POSTGRES_CPU_LIMIT CPUs, $POSTGRES_MEM_LIMIT"
    echo "  Redis:      $REDIS_CPU_LIMIT CPUs, $REDIS_MEM_LIMIT"
    
    ok "Límites calculados"
}

# ============================================================================
# DEPENDENCIAS
# ============================================================================

install_deps() {
    done_step "deps" && { info "Dependencias OK (skip)"; return 0; }
    
    header "INSTALACIÓN DE DEPENDENCIAS"
    
    apt-get update -qq
    
    # Nginx
    if ! command -v nginx &>/dev/null; then
        info "Instalando Nginx..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx
        systemctl enable nginx
        systemctl start nginx
    fi
    ok "Nginx OK"
    
    # Docker
    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
        info "Instalando Docker..."
        
        . /etc/os-release
        apt-get install -y -qq apt-transport-https ca-certificates curl gnupg
        
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        systemctl enable docker
        systemctl start docker
    fi
    ok "Docker OK"
    
    # Certbot
    if ! command -v certbot &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx jq
    fi
    ok "Certbot OK"
    
    mkdir -p /var/www/certbot
    
    mark "deps"
    ok "Dependencias instaladas"
}

# ============================================================================
# CREDENCIALES
# ============================================================================

get_creds() {
    header "CREDENCIALES"
    
    while true; do
        read -p "Dominio: " DOMAIN
        [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] && break
    done
    
    while true; do
        read -p "Email SSL: " EMAIL
        [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break
    done
    
    while true; do
        read -sp "Password PostgreSQL (16+): " PGPASS; echo ""
        [ ${#PGPASS} -ge 16 ] || continue
        read -sp "Confirmar: " P2; echo ""
        [ "$PGPASS" == "$P2" ] && break
    done
    
    read -p "Usuario admin (admin): " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    while true; do
        read -sp "Password admin (16+): " ADMIN_PASS; echo ""
        [ ${#ADMIN_PASS} -ge 16 ] || continue
        read -sp "Confirmar: " P2; echo ""
        [ "$ADMIN_PASS" == "$P2" ] && break
    done
    
    ENC_KEY=$(openssl rand -base64 32)
    
    ok "Credenciales OK"
}

# ============================================================================
# ESTRUCTURA
# ============================================================================

create_struct() {
    done_step "struct" && { info "Estructura OK (skip)"; return 0; }
    
    header "ESTRUCTURA"
    
    mkdir -p "$INSTALL_DIR"/{data/{postgres,redis,n8n,files},backups,scripts}
    mkdir -p "$LOG_DIR"
    
    cat > "$INSTALL_DIR/.env" << EOF
POSTGRES_DB=n8n_production
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=$PGPASS
N8N_ENCRYPTION_KEY=$ENC_KEY
N8N_BASIC_AUTH_USER=$ADMIN_USER
N8N_BASIC_AUTH_PASSWORD=$ADMIN_PASS
N8N_HOST=$DOMAIN
CERTBOT_EMAIL=$EMAIL
N8N_CPU_LIMIT=$N8N_CPU_LIMIT
N8N_MEM_LIMIT=$N8N_MEM_LIMIT
POSTGRES_CPU_LIMIT=$POSTGRES_CPU_LIMIT
POSTGRES_MEM_LIMIT=$POSTGRES_MEM_LIMIT
REDIS_CPU_LIMIT=$REDIS_CPU_LIMIT
REDIS_MEM_LIMIT=$REDIS_MEM_LIMIT
EOF
    chmod 600 "$INSTALL_DIR/.env"
    
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOFC'
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD', 'pg_isready', '-U', '${POSTGRES_USER}']
      interval: 10s
    deploy:
      resources:
        limits:
          cpus: '${POSTGRES_CPU_LIMIT}'
          memory: ${POSTGRES_MEM_LIMIT}

  redis:
    image: redis:7-alpine
    container_name: n8n_redis
    restart: unless-stopped
    command: redis-server --maxmemory 400mb --maxmemory-policy allkeys-lru
    volumes:
      - ./data/redis:/data
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 10s
    deploy:
      resources:
        limits:
          cpus: '${REDIS_CPU_LIMIT}'
          memory: ${REDIS_MEM_LIMIT}

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n_app
    restart: unless-stopped
    depends_on:
      postgres: {condition: service_healthy}
      redis: {condition: service_healthy}
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_HOST: ${N8N_HOST}
      N8N_PROTOCOL: https
      N8N_PORT: 5678
      WEBHOOK_URL: https://${N8N_HOST}/
      QUEUE_BULL_REDIS_HOST: redis
      EXECUTIONS_MODE: queue
      GENERIC_TIMEZONE: America/Bogota
      NODE_ENV: production
      N8N_LOG_LEVEL: debug
    volumes:
      - ./data/n8n:/home/node/.n8n
      - ./data/files:/files
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD-SHELL', 'wget --spider -q http://localhost:5678/healthz || exit 1']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s
    deploy:
      resources:
        limits:
          cpus: '${N8N_CPU_LIMIT}'
          memory: ${N8N_MEM_LIMIT}

networks:
  n8n_network:
    driver: bridge
EOFC
    
    mark "struct"
    ok "Estructura creada"
}

save_state() { mkdir -p "$INSTALL_DIR"; declare -p STEPS > "$STATE_FILE" 2>/dev/null || true; }
load_state() { [ -f "$STATE_FILE" ] && source "$STATE_FILE" 2>/dev/null || true; }
mark() { STEPS[$1]="true"; save_state; }
done_step() { [[ "${STEPS[$1]}" == "true" ]]; }

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok() { echo -e "${G}✓${NC} $1"; log "OK: $1"; }
err() { echo -e "${R}✗${NC} $1"; log "ERR: $1"; }
info() { echo -e "${B}ℹ${NC} $1"; log "INFO: $1"; }
warn() { echo -e "${Y}⚠${NC} $1"; log "WARN: $1"; }
header() { echo ""; echo -e "${C}╔═══ ${W}${BOLD}$1${NC} ${C}═══╗${NC}"; echo ""; }

# ============================================================================
# RECURSOS
# ============================================================================

detect_resources() {
    header "RECURSOS"
    
    TOTAL_CPUS=$(nproc)
    TOTAL_RAM_GB=$(($(free -m | awk '/^Mem:/{print $2}') / 1024))
    
    info "CPUs: $TOTAL_CPUS | RAM: ${TOTAL_RAM_GB}GB"
    
    [ "$TOTAL_CPUS" -lt 2 ] && { err "Mínimo 2 CPUs"; exit 1; }
    [ "$TOTAL_RAM_GB" -lt 3 ] && { err "Mínimo 4 GB RAM"; exit 1; }
    
    # Calcular límites seguros (dejar margen)
    if [ "$TOTAL_CPUS" -eq 2 ]; then
        N8N_CPU_LIMIT="1.0"
        POSTGRES_CPU_LIMIT="0.5"
        REDIS_CPU_LIMIT="0.3"
        N8N_MEM_LIMIT="2048M"
        POSTGRES_MEM_LIMIT="1024M"
        REDIS_MEM_LIMIT="512M"
    else
        N8N_CPU_LIMIT="2.5"
        POSTGRES_CPU_LIMIT="1.0"
        REDIS_CPU_LIMIT="0.5"
        N8N_MEM_LIMIT="4096M"
        POSTGRES_MEM_LIMIT="2560M"
        REDIS_MEM_LIMIT="1024M"
    fi
    
    ok "Límites: n8n($N8N_CPU_LIMIT, $N8N_MEM_LIMIT)"
}

# ============================================================================
# DEPS
# ============================================================================

install_deps() {
    done_step "deps" && { info "Deps OK (skip)"; return 0; }
    
    header "DEPENDENCIAS"
    
    apt-get update -qq
    
    command -v nginx &>/dev/null || {
        info "Nginx..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx
        systemctl enable nginx; systemctl start nginx
    }
    
    command -v docker &>/dev/null || {
        info "Docker..."
        . /etc/os-release
        apt-get install -y -qq curl gnupg
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-compose-plugin
        systemctl enable docker; systemctl start docker
    }
    
    command -v certbot &>/dev/null || apt-get install -y -qq certbot python3-certbot-nginx
    command -v jq &>/dev/null || apt-get install -y -qq jq
    
    mkdir -p /var/www/certbot
    
    mark "deps"
    ok "Dependencias OK"
}

# ============================================================================
# NGINX
# ============================================================================

config_nginx() {
    done_step "nginx" && {
        if [ -f "/etc/nginx/sites-enabled/$DOMAIN" ] && nginx -t 2>&1 | grep -q "syntax is ok"; then
            info "Nginx OK (skip)"
            return 0
        fi
        warn "Nginx necesita reconfiguración"
    }
    
    header "NGINX"
    
    cat > "/etc/nginx/sites-available/$DOMAIN" << EOFN
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        client_max_body_size 50M;
    }
}
EOFN
    
    ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx || { err "Nginx inválido"; exit 1; }
    
    mark "nginx"
    ok "Nginx configurado"
}

# ============================================================================
# SSL
# ============================================================================

gen_ssl() {
    done_step "ssl" && {
        if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
            info "SSL OK (skip)"
            config_https
            return 0
        fi
    }
    
    header "SSL"
    
    systemctl reload nginx; sleep 2
    
    certbot certonly --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        config_https
        mark "ssl"
        ok "SSL OK"
        systemctl enable certbot.timer 2>/dev/null || true
    else
        warn "SSL falló (continuando sin HTTPS)"
    fi
}

config_https() {
    cat > "/etc/nginx/sites-available/$DOMAIN" << EOFH
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$server_name\$request_uri; }
}
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        client_max_body_size 50M;
    }
}
EOFH
    nginx -t && systemctl reload nginx
}

# ============================================================================
# DOCKER
# ============================================================================

pull_imgs() {
    done_step "imgs" && { info "Imágenes OK (skip)"; return 0; }
    
    header "DESCARGA DE IMÁGENES"
    
    cd "$INSTALL_DIR"
    docker compose pull 2>&1 | tee -a "$LOG_FILE"
    
    mark "imgs"
    ok "Imágenes descargadas"
}

start_svcs() {
    header "SERVICIOS DOCKER"
    
    cd "$INSTALL_DIR"
    
    # Verificar si ya están corriendo
    local running=$(docker ps --filter "name=n8n_" --format '{{.Names}}' | wc -l)
    
    if [ "$running" -eq 3 ]; then
        local healthy=$(docker ps --filter "name=n8n_" --filter "health=healthy" --format '{{.Names}}' | wc -l)
        
        if [ "$healthy" -eq 3 ]; then
            info "Servicios OK (3/3 saludables, skip)"
            return 0
        else
            warn "Servicios corriendo pero no saludables, reiniciando..."
        fi
    fi
    
    # Detener servicios con problemas
    docker compose down 2>/dev/null || true
    
    # Iniciar
    info "Iniciando servicios..."
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        err "Error al iniciar contenedores"
        info "Revisando causa del error..."
        
        echo ""
        echo -e "${R}═══ LOGS DE ERROR ═══${NC}"
        docker compose logs --tail=30
        
        exit 1
    fi
    
    # Esperar health checks
    info "Esperando servicios saludables..."
    local max_wait=120
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local healthy=$(docker ps --filter "name=n8n_" --filter "health=healthy" --format '{{.Names}}' | wc -l)
        
        echo -ne "  Saludables: $healthy/3 (${waited}s)...\r"
        
        if [ "$healthy" -eq 3 ]; then
            echo ""
            ok "Todos los servicios saludables (3/3)"
            break
        fi
        
        # Verificar si n8n está crasheando
        if [ $waited -gt 30 ]; then
            local n8n_status=$(docker inspect n8n_app --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
            
            if [ "$n8n_status" == "restarting" ]; then
                echo ""
                warn "n8n está crasheando, diagnosticando..."
                diagnose_n8n_crash
                exit 1
            fi
        fi
        
        sleep 5
        waited=$((waited + 5))
    done
    
    echo ""
    
    mark "svcs"
}

# ============================================================================
# DIAGNÓSTICO DE ERRORES DE N8N
# ============================================================================

diagnose_n8n_crash() {
    header "DIAGNÓSTICO DE ERROR N8N"
    
    err "n8n no puede iniciar correctamente"
    echo ""
    
    info "Revisando logs de n8n..."
    echo ""
    echo -e "${Y}═══ ÚLTIMOS 50 LOGS DE N8N ═══${NC}"
    docker logs n8n_app --tail=50
    echo -e "${Y}═══════════════════════════════${NC}"
    echo ""
    
    # Análisis de errores comunes
    local logs=$(docker logs n8n_app 2>&1)
    
    if echo "$logs" | grep -qi "encryption key"; then
        err "PROBLEMA: Clave de encriptación inválida"
        info "Solución: Regenerando clave..."
        ENC_KEY=$(openssl rand -base64 32)
        sed -i "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$ENC_KEY/" "$INSTALL_DIR/.env"
        warn "Reintenta: cd $INSTALL_DIR && docker compose up -d"
        
    elif echo "$logs" | grep -qi "database"; then
        err "PROBLEMA: Error de base de datos"
        info "Verificando PostgreSQL..."
        docker logs n8n_postgres --tail=20
        
    elif echo "$logs" | grep -qi "redis"; then
        err "PROBLEMA: Error de conexión a Redis"
        info "Verificando Redis..."
        docker exec n8n_redis redis-cli ping || err "Redis no responde"
        
    elif echo "$logs" | grep -qi "memory"; then
        err "PROBLEMA: Sin memoria suficiente"
        info "RAM actual: $(free -h | awk '/^Mem:/{print $2}')"
        info "Solución: Aumenta la RAM del servidor a 8 GB mínimo"
        
    else
        err "Error desconocido. Revisa logs completos:"
        info "docker logs n8n_app"
    fi
}

# ============================================================================
# VALIDACIÓN EXHAUSTIVA
# ============================================================================

validate_all() {
    header "VALIDACIÓN COMPLETA"
    
    local errors=0
    local warnings=0
    
    # 1. Nginx
    step "1/8 - Nginx"
    if systemctl is-active --quiet nginx; then
        ok "Nginx corriendo"
    else
        err "Nginx NO corriendo"
        errors=$((errors + 1))
    fi
    
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        ok "Configuración Nginx válida"
    else
        err "Configuración Nginx inválida"
        nginx -t
        errors=$((errors + 1))
    fi
    
    # 2. Sitio Nginx
    step "2/8 - Sitio Nginx"
    if [ -f "/etc/nginx/sites-enabled/$DOMAIN" ]; then
        ok "Sitio habilitado: $DOMAIN"
    else
        err "Sitio NO habilitado"
        errors=$((errors + 1))
    fi
    
    # 3. SSL
    step "3/8 - Certificado SSL"
    if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
        local days=$(( ($(date -d "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" | cut -d= -f2)" +%s 2>/dev/null || echo "0") - $(date +%s)) / 86400 ))
        ok "SSL válido ($days días)"
    else
        warn "SSL no instalado"
        warnings=$((warnings + 1))
    fi
    
    # 4. Contenedores
    step "4/8 - Contenedores Docker"
    local containers=("n8n_postgres" "n8n_redis" "n8n_app")
    for c in "${containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
            local status=$(docker inspect $c --format='{{.State.Status}}')
            if [ "$status" == "running" ]; then
                ok "$c corriendo"
            else
                err "$c estado: $status"
                errors=$((errors + 1))
            fi
        else
            err "$c NO existe"
            errors=$((errors + 1))
        fi
    done
    
    # 5. Health checks
    step "5/8 - Health Checks"
    local healthy=$(docker ps --filter "name=n8n_" --filter "health=healthy" | wc -l)
    if [ "$healthy" -ge 3 ]; then
        ok "Contenedores saludables: $healthy/3"
    else
        warn "Solo $healthy/3 saludables"
        warnings=$((warnings + 1))
        
        # Mostrar cuáles no están saludables
        for c in "${containers[@]}"; do
            local health=$(docker inspect $c --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
            if [ "$health" != "healthy" ]; then
                warn "$c: $health"
            fi
        done
    fi
    
    # 6. Conectividad local
    step "6/8 - Conectividad Local"
    local code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5678/healthz" 2>/dev/null || echo "000")
    if [ "$code" == "200" ]; then
        ok "n8n responde localmente (200)"
    else
        err "n8n NO responde (código: $code)"
        errors=$((errors + 1))
        
        info "Verificando logs de n8n..."
        echo ""
        docker logs n8n_app --tail=20
        echo ""
    fi
    
    # 7. Respuesta HTTP externa
    step "7/8 - Acceso HTTP Externo"
    sleep 2
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|301|401)$ ]]; then
        ok "HTTP externo OK ($code)"
    else
        warn "HTTP externo: $code"
        warnings=$((warnings + 1))
    fi
    
    # 8. Respuesta HTTPS externa
    step "8/8 - Acceso HTTPS Externo"
    code=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|401)$ ]]; then
        ok "HTTPS externo OK ($code)"
        
        # Test de login
        info "Probando página de login..."
        local content=$(curl -s -k "https://$DOMAIN" 2>/dev/null || echo "")
        if echo "$content" | grep -qi "n8n"; then
            ok "Página de n8n cargando correctamente"
        else
            warn "La respuesta no parece ser de n8n"
        fi
    else
        warn "HTTPS externo: $code"
        warnings=$((warnings + 1))
    fi
    
    echo ""
    
    # Resumen
    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        ok "${G}${BOLD}✓✓✓ TODAS LAS VALIDACIONES PASARON${NC}"
    elif [ $errors -eq 0 ]; then
        warn "Validación OK con $warnings advertencias"
    else
        err "$errors errores críticos detectados"
        
        echo ""
        header "DIAGNÓSTICO DE PROBLEMAS"
        
        info "Ejecuta estos comandos para más información:"
        echo ""
        echo -e "  ${C}docker logs n8n_app${NC}          Ver logs de n8n"
        echo -e "  ${C}docker logs n8n_postgres${NC}    Ver logs de PostgreSQL"
        echo -e "  ${C}docker compose ps${NC}            Ver estado"
        echo -e "  ${C}curl http://127.0.0.1:5678${NC}  Probar localmente"
        echo ""
    fi
}

# ============================================================================
# MANTENIMIENTO
# ============================================================================

create_maint() {
    done_step "maint" && { info "Mantenimiento OK (skip)"; return 0; }
    
    header "MANTENIMIENTO"
    
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOFB'
#!/bin/bash
D=$(date +%Y%m%d_%H%M%S)
docker exec n8n_postgres pg_dump -U n8n_user n8n_production | gzip > "/opt/n8n-production/backups/postgres/db_$D.sql.gz"
echo "Backup: $D"
EOFB
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    
    (crontab -l 2>/dev/null | grep -v n8n; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh") | crontab -
    
    # Crear alias GLOBALES
    cat > /etc/profile.d/n8n.sh << 'EOFA'
#!/bin/bash
alias n8n-logs='docker logs -f n8n_app'
alias n8n-status='cd /opt/n8n-production && docker compose ps'
alias n8n-restart='cd /opt/n8n-production && docker compose restart n8n'
alias n8n-backup='sudo /opt/n8n-production/scripts/backup.sh'
alias n8n-stop='cd /opt/n8n-production && docker compose down'
alias n8n-start='cd /opt/n8n-production && docker compose up -d'
alias n8n-diagnose='docker logs n8n_app --tail=50'
EOFA
    chmod +x /etc/profile.d/n8n.sh
    
    # Cargar en bash actual
    if [ -n "$SUDO_USER" ]; then
        echo 'source /etc/profile.d/n8n.sh' >> /home/$SUDO_USER/.bashrc
    fi
    echo 'source /etc/profile.d/n8n.sh' >> /root/.bashrc
    
    # Cargar ahora
    source /etc/profile.d/n8n.sh 2>/dev/null || true
    
    mark "maint"
    ok "Mantenimiento configurado"
}

# ============================================================================
# RESUMEN
# ============================================================================

save_creds() {
    cat > "$INSTALL_DIR/CREDENCIALES.txt" << EOFC
═══════════════════════════════════════════
N8N - CREDENCIALES
═══════════════════════════════════════════

URL:      https://$DOMAIN
Usuario:  $ADMIN_USER
Password: $ADMIN_PASS

PostgreSQL: $PGPASS
Encryption: $ENC_KEY

Recursos:
  n8n:        $N8N_CPU_LIMIT CPUs, $N8N_MEM_LIMIT
  PostgreSQL: $POSTGRES_CPU_LIMIT CPUs, $POSTGRES_MEM_LIMIT
  Redis:      $REDIS_CPU_LIMIT CPUs, $REDIS_MEM_LIMIT

═══════════════════════════════════════════
EOFC
    chmod 600 "$INSTALL_DIR/CREDENCIALES.txt"
}

summary() {
    header "¡COMPLETADO!"
    
    echo ""
    echo -e "${G}${BOLD}✅ INSTALACIÓN FINALIZADA${NC}"
    echo ""
    echo -e "${C}Acceso:${NC} ${G}https://$DOMAIN${NC}"
    echo -e "${C}Usuario:${NC} ${C}$ADMIN_USER${NC}"
    echo ""
    echo -e "${Y}Comandos disponibles:${NC}"
    echo -e "  ${C}n8n-logs${NC}      Ver logs en tiempo real"
    echo -e "  ${C}n8n-status${NC}    Ver estado de servicios"
    echo -e "  ${C}n8n-restart${NC}   Reiniciar n8n"
    echo -e "  ${C}n8n-diagnose${NC}  Ver últimos 50 logs"
    echo ""
    echo -e "${B}Cargar alias ahora:${NC}"
    echo -e "  ${C}source /etc/profile.d/n8n.sh${NC}"
    echo ""
    echo -e "${W}Credenciales:${NC} $INSTALL_DIR/CREDENCIALES.txt"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    mkdir -p "$LOG_DIR"
    banner
    log "=== N8N Installer v$SCRIPT_VERSION ==="
    
    [ "$EUID" -ne 0 ] && { err "Ejecuta: sudo bash $0"; exit 1; }
    
    load_state
    detect_resources
    calculate_limits
    
    install_deps
    get_creds
    create_struct
    config_nginx
    gen_ssl
    pull_imgs
    start_svcs
    create_maint
    
    validate_all
    save_creds
    summary
    
    log "=== Completado: $(date) ==="
}

main "$@"
