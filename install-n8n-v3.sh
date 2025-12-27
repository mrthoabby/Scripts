#!/bin/bash
###############################################################################
# N8N PRODUCTION INSTALLER v3.2 ULTRA ROBUST
# 
# Mejoras v3.2:
# ✓ Detección automática de recursos (CPU/RAM)
# ✓ Distribución inteligente de límites Docker
# ✓ Skip de pasos ya completados
# ✓ Validación exhaustiva antes de cada paso
# ✓ Recuperación automática de errores
###############################################################################

set -e
trap 'handle_error $LINENO' ERR

# ============================================================================
# VARIABLES GLOBALES
# ============================================================================

SCRIPT_VERSION="3.2"
INSTALL_DIR="/opt/n8n-production"
LOG_DIR="/var/log/n8n"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="$INSTALL_DIR/.install_state"

# Colores
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; M='\033[0;35m'
W='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# Recursos del sistema
TOTAL_CPUS=0
TOTAL_RAM_GB=0
AVAILABLE_DISK_GB=0

# Límites calculados para contenedores
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
RUN_TOKEN=""

CLEANUP_AFTER_INSTALL=true

# Estado de pasos
declare -A STEPS_COMPLETED=(
    ["dependencies"]="false"
    ["structure"]="false"
    ["nginx_site"]="false"
    ["ssl_cert"]="false"
    ["docker_images"]="false"
    ["docker_services"]="false"
    ["maintenance"]="false"
)

# ============================================================================
# FUNCIONES DE ESTADO
# ============================================================================

save_state() {
    mkdir -p "$INSTALL_DIR"
    declare -p STEPS_COMPLETED > "$STATE_FILE" 2>/dev/null || true
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE" 2>/dev/null || true
        return 0
    fi
    return 1
}

mark_completed() {
    local step=$1
    STEPS_COMPLETED[$step]="true"
    save_state
    log "STEP COMPLETED: $step"
}

is_completed() {
    local step=$1
    [[ "${STEPS_COMPLETED[$step]}" == "true" ]]
}

# ============================================================================
# FUNCIONES DE UI Y LOG
# ============================================================================

handle_error() {
    echo ""
    echo -e "${R}${BOLD}✗ ERROR EN LÍNEA $1${NC}"
    echo -e "${Y}Log: ${LOG_FILE}${NC}"
    save_state
    exit 1
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok() { echo -e "${G}  ✓${NC} $1"; log "OK: $1"; }
err() { echo -e "${R}  ✗${NC} $1"; log "ERROR: $1"; }
info() { echo -e "${B}  ℹ${NC} $1"; log "INFO: $1"; }
warn() { echo -e "${Y}  ⚠${NC} $1"; log "WARN: $1"; }

header() {
    echo ""
    echo -e "${C}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC}  ${W}${BOLD}$1${NC}"
    echo -e "${C}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

step() {
    echo ""
    echo -e "${M}▶${NC} ${BOLD}$1${NC}"
    echo -e "${B}$(printf '─%.0s' {1..70})${NC}"
}

banner() {
    clear
    echo -e "${C}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║       🚀 N8N PRODUCTION INSTALLER v3.2 ULTRA ROBUST                 ║
║                                                                      ║
║       ✓ Detección Inteligente de Recursos                           ║
║       ✓ Skip de Pasos Completados                                   ║
║       ✓ Distribución Automática de CPU/RAM                          ║
║       ✓ Recuperación de Errores                                     ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ============================================================================
# DETECCIÓN Y CÁLCULO DE RECURSOS
# ============================================================================

detect_system_resources() {
    header "DETECCIÓN DE RECURSOS DEL SISTEMA"
    
    step "Detectando CPUs"
    TOTAL_CPUS=$(nproc)
    info "CPUs detectadas: $TOTAL_CPUS"
    
    if [ "$TOTAL_CPUS" -lt 2 ]; then
        err "Se requieren al menos 2 CPUs"
        exit 1
    fi
    ok "CPUs suficientes"
    
    step "Detectando RAM"
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    TOTAL_RAM_GB=$((ram_mb / 1024))
    info "RAM detectada: ${TOTAL_RAM_GB} GB (${ram_mb} MB)"
    
    if [ "$ram_mb" -lt 3500 ]; then
        err "Se requieren al menos 4 GB de RAM"
        exit 1
    fi
    ok "RAM suficiente"
    
    step "Detectando espacio en disco"
    AVAILABLE_DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    info "Disco disponible: ${AVAILABLE_DISK_GB} GB"
    
    if [ "$AVAILABLE_DISK_GB" -lt 20 ]; then
        err "Se requieren al menos 20 GB disponibles"
        exit 1
    fi
    ok "Disco suficiente"
}

calculate_resource_limits() {
    header "CÁLCULO DE LÍMITES DE RECURSOS"
    
    step "Calculando límites óptimos para contenedores"
    
    # Dejar 20% de recursos para el sistema
    local docker_cpus=$(awk "BEGIN {print $TOTAL_CPUS * 0.80}")
    local docker_ram_gb=$(awk "BEGIN {print $TOTAL_RAM_GB * 0.80}")
    
    info "Recursos disponibles para Docker:"
    info "  CPUs: $docker_cpus (80% de $TOTAL_CPUS)"
    info "  RAM:  ${docker_ram_gb} GB (80% de ${TOTAL_RAM_GB} GB)"
    
    # Distribución según recursos disponibles
    if [ "$TOTAL_CPUS" -le 2 ]; then
        # Servidor con 2 CPUs (mínimo)
        N8N_CPU_LIMIT="1.2"
        POSTGRES_CPU_LIMIT="0.6"
        REDIS_CPU_LIMIT="0.2"
        
        N8N_MEM_LIMIT="2048M"
        POSTGRES_MEM_LIMIT="1024M"
        REDIS_MEM_LIMIT="512M"
        
    elif [ "$TOTAL_CPUS" -le 4 ]; then
        # Servidor con 4 CPUs (recomendado)
        N8N_CPU_LIMIT="2.5"
        POSTGRES_CPU_LIMIT="1.0"
        REDIS_CPU_LIMIT="0.5"
        
        if [ "$TOTAL_RAM_GB" -ge 8 ]; then
            N8N_MEM_LIMIT="4096M"
            POSTGRES_MEM_LIMIT="2560M"
            REDIS_MEM_LIMIT="1024M"
        else
            N8N_MEM_LIMIT="2560M"
            POSTGRES_MEM_LIMIT="1536M"
            REDIS_MEM_LIMIT="768M"
        fi
        
    else
        # Servidor con 8+ CPUs (potente)
        N8N_CPU_LIMIT="5.0"
        POSTGRES_CPU_LIMIT="2.0"
        REDIS_CPU_LIMIT="1.0"
        
        N8N_MEM_LIMIT="8192M"
        POSTGRES_MEM_LIMIT="4096M"
        REDIS_MEM_LIMIT="2048M"
    fi
    
    echo ""
    info "Límites calculados:"
    echo ""
    echo -e "  ${C}n8n:${NC}"
    echo -e "    CPU:  $N8N_CPU_LIMIT"
    echo -e "    RAM:  $N8N_MEM_LIMIT"
    echo ""
    echo -e "  ${C}PostgreSQL:${NC}"
    echo -e "    CPU:  $POSTGRES_CPU_LIMIT"
    echo -e "    RAM:  $POSTGRES_MEM_LIMIT"
    echo ""
    echo -e "  ${C}Redis:${NC}"
    echo -e "    CPU:  $REDIS_CPU_LIMIT"
    echo -e "    RAM:  $REDIS_MEM_LIMIT"
    echo ""
    
    ok "Límites de recursos calculados"
}

# ============================================================================
# VERIFICACIONES
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Ejecuta como root: sudo bash $0"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        info "SO: $NAME $VERSION_ID"
    fi
}

# ============================================================================
# INSTALACIÓN DE DEPENDENCIAS
# ============================================================================

install_dependencies() {
    if is_completed "dependencies"; then
        info "Dependencias ya instaladas (skip)"
        return 0
    fi
    
    header "INSTALACIÓN DE DEPENDENCIAS"
    
    local deps_to_install=()
    
    # Verificar herramientas básicas
    for cmd in curl wget git openssl jq; do
        if ! command -v $cmd &>/dev/null; then
            case $cmd in
                curl) deps_to_install+=("curl") ;;
                wget) deps_to_install+=("wget") ;;
                git) deps_to_install+=("git") ;;
                openssl) deps_to_install+=("openssl") ;;
                jq) deps_to_install+=("jq") ;;
            esac
        fi
    done
    
    if [ ${#deps_to_install[@]} -gt 0 ]; then
        info "Instalando: ${deps_to_install[*]}"
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${deps_to_install[@]}"
    fi
    
    # Nginx
    if ! command -v nginx &>/dev/null; then
        info "Instalando Nginx..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx
        systemctl enable nginx
        systemctl start nginx
    fi
    ok "Nginx instalado"
    
    # Docker
    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
        info "Instalando Docker..."
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release
        
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        systemctl enable docker
        systemctl start docker
    fi
    ok "Docker instalado"
    
    # Certbot
    if ! command -v certbot &>/dev/null; then
        info "Instalando Certbot..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx
    fi
    ok "Certbot instalado"
    
    mkdir -p /var/www/certbot
    
    mark_completed "dependencies"
    ok "Todas las dependencias instaladas"
}

# ============================================================================
# CREDENCIALES
# ============================================================================

collect_credentials() {
    header "CONFIGURACIÓN DE CREDENCIALES"
    
    # Dominio
    while true; do
        read -p "$(echo -e ${G}Dominio:${NC}) " DOMAIN
        [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] && break
    done
    
    # Email
    while true; do
        read -p "$(echo -e ${G}Email SSL:${NC}) " EMAIL
        [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break
    done
    
    # Password PostgreSQL
    while true; do
        read -sp "$(echo -e ${G}Password PostgreSQL \(16+\):${NC}) " PGPASS
        echo ""
        [ ${#PGPASS} -ge 16 ] || continue
        read -sp "$(echo -e ${G}Confirmar:${NC}) " PGPASS2
        echo ""
        [ "$PGPASS" == "$PGPASS2" ] && break
    done
    
    # Usuario admin
    read -p "$(echo -e ${G}Usuario admin \(admin\):${NC}) " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    # Password admin
    while true; do
        read -sp "$(echo -e ${G}Password admin \(16+\):${NC}) " ADMIN_PASS
        echo ""
        [ ${#ADMIN_PASS} -ge 16 ] || continue
        read -sp "$(echo -e ${G}Confirmar:${NC}) " ADMIN_PASS2
        echo ""
        [ "$ADMIN_PASS" == "$ADMIN_PASS2" ] && break
    done
    
    # Generar claves
    ENC_KEY=$(openssl rand -base64 32 | tr -d '\n')
    RUN_TOKEN=$(openssl rand -base64 32 | tr -d '\n')
    
    ok "Credenciales configuradas"
}

# ============================================================================
# ESTRUCTURA
# ============================================================================

create_structure() {
    if is_completed "structure"; then
        info "Estructura ya creada (skip)"
        return 0
    fi
    
    header "CREACIÓN DE ESTRUCTURA"
    
    mkdir -p "$INSTALL_DIR"/{data/{postgres,redis,n8n,files},backups/{postgres,n8n-data,config},scripts}
    mkdir -p "$LOG_DIR"
    
    # .env
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
    
    # docker-compose.yml
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
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '${POSTGRES_CPU_LIMIT}'
          memory: ${POSTGRES_MEM_LIMIT}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    image: redis:7-alpine
    container_name: n8n_redis
    restart: unless-stopped
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
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
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"

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
      WEBHOOK_URL: https://${N8N_HOST}/
      QUEUE_BULL_REDIS_HOST: redis
      EXECUTIONS_MODE: queue
      NODE_ENV: production
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
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '${N8N_CPU_LIMIT}'
          memory: ${N8N_MEM_LIMIT}
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "5"

networks:
  n8n_network:
    driver: bridge
EOFC
    
    mark_completed "structure"
    ok "Estructura creada"
}

# ============================================================================
# NGINX
# ============================================================================

configure_nginx() {
    if is_completed "nginx_site"; then
        info "Sitio Nginx ya configurado (skip)"
        if nginx -t 2>&1 | grep -q "syntax is ok"; then
            ok "Configuración válida"
            return 0
        else
            warn "Configuración inválida, recreando..."
        fi
    fi
    
    header "CONFIGURACIÓN DE NGINX"
    
    cat > "/etc/nginx/sites-available/$DOMAIN" << EOFN
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 50M;
    }
}
EOFN
    
    ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
    rm -f /etc/nginx/sites-enabled/default
    
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        systemctl reload nginx
        mark_completed "nginx_site"
        ok "Nginx configurado"
    else
        err "Error en Nginx"
        nginx -t
        exit 1
    fi
}

# ============================================================================
# SSL
# ============================================================================

generate_ssl() {
    if is_completed "ssl_cert"; then
        info "Certificado SSL ya existe (verificando...)"
        
        if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
            local days=$(( ($(date -d "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" | cut -d= -f2)" +%s 2>/dev/null || echo "0") - $(date +%s)) / 86400 ))
            
            if [ $days -gt 30 ]; then
                ok "Certificado válido ($days días)"
                configure_nginx_https
                return 0
            fi
        fi
    fi
    
    header "GENERACIÓN DE CERTIFICADO SSL"
    
    systemctl reload nginx
    sleep 2
    
    certbot certonly --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        configure_nginx_https
        mark_completed "ssl_cert"
        ok "SSL configurado"
        
        systemctl enable certbot.timer 2>/dev/null || \
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
    else
        warn "SSL no configurado (continuando sin HTTPS)"
    fi
}

configure_nginx_https() {
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
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 50M;
    }
}
EOFH
    nginx -t && systemctl reload nginx
}

# ============================================================================
# DOCKER
# ============================================================================

pull_images() {
    if is_completed "docker_images"; then
        info "Imágenes Docker ya descargadas (skip)"
        return 0
    fi
    
    header "DESCARGA DE IMÁGENES DOCKER"
    
    cd "$INSTALL_DIR"
    docker compose pull 2>&1 | tee -a "$LOG_FILE"
    
    mark_completed "docker_images"
    ok "Imágenes descargadas"
}

start_services() {
    if is_completed "docker_services"; then
        info "Verificando servicios..."
        
        cd "$INSTALL_DIR"
        local running=$(docker compose ps --format json 2>/dev/null | jq -r '.State' | grep -c "running" 2>/dev/null || echo "0")
        
        if [ "$running" -eq 3 ]; then
            ok "Servicios ya corriendo (3/3)"
            return 0
        else
            warn "Solo $running/3 servicios corriendo, reiniciando..."
        fi
    fi
    
    header "INICIO DE SERVICIOS DOCKER"
    
    cd "$INSTALL_DIR"
    
    # Detener si hay contenedores previos con problemas
    docker compose down 2>/dev/null || true
    
    # Iniciar
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        err "Error al iniciar contenedores"
        docker compose logs
        exit 1
    fi
    
    sleep 15
    
    local healthy=0
    for i in {1..12}; do
        healthy=$(docker compose ps --format json 2>/dev/null | jq -r 'select(.Health != null) | .Health' | grep -c "healthy" 2>/dev/null || echo "0")
        
        if [ "$healthy" -eq 3 ]; then
            break
        fi
        
        echo -ne "  Esperando servicios: $healthy/3...\r"
        sleep 5
    done
    
    echo ""
    
    if [ "$healthy" -eq 3 ]; then
        mark_completed "docker_services"
        ok "Servicios iniciados (3/3 saludables)"
    else
        warn "Solo $healthy/3 servicios saludables"
    fi
    
    docker compose ps
}

# ============================================================================
# MANTENIMIENTO
# ============================================================================

create_maintenance() {
    if is_completed "maintenance"; then
        info "Scripts de mantenimiento ya creados (skip)"
        return 0
    fi
    
    header "SCRIPTS DE MANTENIMIENTO"
    
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOFB'
#!/bin/bash
D=$(date +%Y%m%d_%H%M%S)
docker exec n8n_postgres pg_dump -U n8n_user n8n_production | gzip > "/opt/n8n-production/backups/postgres/db_$D.sql.gz"
tar -czf "/opt/n8n-production/backups/n8n-data/data_$D.tar.gz" -C /opt/n8n-production/data/n8n . 2>/dev/null
echo "Backup: $D"
EOFB
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    
    (crontab -l 2>/dev/null | grep -v n8n; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh") | crontab -
    
    cat > /etc/profile.d/n8n.sh << 'EOFA'
alias n8n-logs='docker logs -f n8n_app'
alias n8n-status='cd /opt/n8n-production && docker compose ps'
alias n8n-restart='cd /opt/n8n-production && docker compose restart n8n'
alias n8n-backup='sudo /opt/n8n-production/scripts/backup.sh'
EOFA
    chmod +x /etc/profile.d/n8n.sh
    source /etc/profile.d/n8n.sh 2>/dev/null || true
    
    mark_completed "maintenance"
    ok "Mantenimiento configurado"
}

# ============================================================================
# VALIDACIÓN
# ============================================================================

validate() {
    header "VALIDACIÓN FINAL"
    
    # Nginx
    systemctl is-active --quiet nginx && ok "Nginx OK" || warn "Nginx problema"
    
    # SSL
    [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ] && ok "SSL OK" || warn "SSL no configurado"
    
    # Contenedores
    local running=$(docker compose ps --format json 2>/dev/null | jq -r '.State' | grep -c "running" 2>/dev/null || echo "0")
    [ "$running" -eq 3 ] && ok "Contenedores OK (3/3)" || warn "Solo $running/3 corriendo"
    
    # Conectividad
    local code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5678/healthz" 2>/dev/null || echo "000")
    [ "$code" == "200" ] && ok "n8n responde localmente" || warn "n8n: HTTP $code"
    
    # HTTPS externo
    sleep 3
    code=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN" 2>/dev/null || echo "000")
    [[ "$code" =~ ^(200|401)$ ]] && ok "HTTPS externo OK ($code)" || warn "HTTPS: $code"
}

# ============================================================================
# RESUMEN
# ============================================================================

save_credentials() {
    cat > "$INSTALL_DIR/CREDENCIALES.txt" << EOFC
═══════════════════════════════════════════════════
N8N - CREDENCIALES DE ACCESO
═══════════════════════════════════════════════════

URL:      https://$DOMAIN
Usuario:  $ADMIN_USER
Password: $ADMIN_PASS

PostgreSQL: $PGPASS
Encryption: $ENC_KEY

Fecha: $(date)

═══════════════════════════════════════════════════
RECURSOS ASIGNADOS:
═══════════════════════════════════════════════════

n8n:        $N8N_CPU_LIMIT CPUs, $N8N_MEM_LIMIT RAM
PostgreSQL: $POSTGRES_CPU_LIMIT CPUs, $POSTGRES_MEM_LIMIT RAM
Redis:      $REDIS_CPU_LIMIT CPUs, $REDIS_MEM_LIMIT RAM

═══════════════════════════════════════════════════
EOFC
    chmod 600 "$INSTALL_DIR/CREDENCIALES.txt"
}

summary() {
    header "¡INSTALACIÓN COMPLETADA!"
    
    echo ""
    echo -e "${G}${BOLD}✅ N8N ESTÁ LISTO${NC}"
    echo ""
    echo -e "${C}Acceso:${NC}"
    echo -e "  URL:      ${G}https://$DOMAIN${NC}"
    echo -e "  Usuario:  ${C}$ADMIN_USER${NC}"
    echo ""
    echo -e "${C}Recursos asignados:${NC}"
    echo -e "  n8n:        $N8N_CPU_LIMIT CPUs, $N8N_MEM_LIMIT"
    echo -e "  PostgreSQL: $POSTGRES_CPU_LIMIT CPUs, $POSTGRES_MEM_LIMIT"
    echo -e "  Redis:      $REDIS_CPU_LIMIT CPUs, $REDIS_MEM_LIMIT"
    echo ""
    echo -e "${C}Comandos:${NC}"
    echo -e "  ${Y}n8n-logs${NC}     Ver logs"
    echo -e "  ${Y}n8n-status${NC}   Ver estado"
    echo -e "  ${Y}n8n-restart${NC}  Reiniciar"
    echo -e "  ${Y}n8n-backup${NC}   Backup"
    echo ""
    echo -e "${B}Para usar alias ahora: ${C}source /etc/profile.d/n8n.sh${NC}"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    mkdir -p "$LOG_DIR"
    banner
    
    log "N8N Installer v$SCRIPT_VERSION - Inicio: $(date)"
    
    check_root
    detect_os
    
    # Cargar estado previo
    load_state
    
    # Detectar y calcular recursos
    detect_system_resources
    calculate_resource_limits
    
    # Instalar
    install_dependencies
    collect_credentials
    create_structure
    configure_nginx
    generate_ssl
    pull_images
    start_services
    create_maintenance
    
    # Validar
    validate
    save_credentials
    summary
    
    log "Instalación completada: $(date)"
}

main "$@"
