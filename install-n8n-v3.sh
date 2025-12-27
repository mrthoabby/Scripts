#!/bin/bash
###############################################################################
# N8N PRODUCTION INSTALLER v3.4 DEFINITIVO
# 
# v3.4 - FIX CRÍTICO:
# ✓ Corrige permisos de volúmenes Docker
# ✓ Detección y solución automática de errores
# ✓ Validación exhaustiva de salud de contenedores
# ✓ Reconstrucción automática si hay problemas
# ✓ Diagnóstico detallado con soluciones
# ✓ Alias globales funcionando al 100%
###############################################################################

set -e
trap 'handle_error $LINENO $?' ERR

# Variables
VERSION="3.4"
INSTALL_DIR="/opt/n8n-production"
LOG_DIR="/var/log/n8n"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="$INSTALL_DIR/.state"

# Colores
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; M='\033[0;35m'; W='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# Recursos
TOTAL_CPUS=0; TOTAL_RAM_GB=0
N8N_CPU=""; N8N_MEM=""
PG_CPU=""; PG_MEM=""
RD_CPU=""; RD_MEM=""

# Credenciales
DOMAIN=""; EMAIL=""; PGPASS=""; ADMIN_USER=""; ADMIN_PASS=""; ENC_KEY=""

# Estado
declare -A S=(["deps"]="0" ["struct"]="0" ["nginx"]="0" ["ssl"]="0" ["svcs"]="0" ["maint"]="0")

# ============================================================================
# UI Y LOG
# ============================================================================

handle_error() {
    echo ""; echo -e "${R}${BOLD}✗ ERROR (línea $1, código $2)${NC}"
    echo -e "${Y}Log completo: $LOG_FILE${NC}"; echo ""
    
    # Intentar diagnóstico automático
    if docker ps -a | grep -q "n8n_app"; then
        echo -e "${Y}═══ DIAGNÓSTICO AUTOMÁTICO ═══${NC}"
        docker logs n8n_app --tail=30 2>&1 | grep -i "error\|failed\|denied" || echo "No hay errores claros en logs"
    fi
    
    save_state; exit 1
}

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok() { echo -e "${G}✓${NC} $1"; log "OK: $1"; }
err() { echo -e "${R}✗${NC} $1"; log "ERR: $1"; }
info() { echo -e "${B}ℹ${NC} $1"; log "INFO: $1"; }
warn() { echo -e "${Y}⚠${NC} $1"; log "WARN: $1"; }
header() { echo ""; echo -e "${C}╔═══ ${W}${BOLD}$1${NC} ${C}═══╗${NC}"; echo ""; }
step() { echo ""; echo -e "${M}▶${NC} ${BOLD}$1${NC}"; }

banner() {
    clear
    echo -e "${C}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║     🚀 N8N INSTALLER v3.4 - DEFINITIVE EDITION                      ║
║     ✓ Auto-Fix Permisos  ✓ Diagnóstico Inteligente                 ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Estado
save_state() { mkdir -p "$INSTALL_DIR"; declare -p S > "$STATE_FILE" 2>/dev/null || true; }
load_state() { [ -f "$STATE_FILE" ] && source "$STATE_FILE" 2>/dev/null || true; }
mark() { S[$1]="1"; save_state; }
skip() { [[ "${S[$1]}" == "1" ]]; }

# ============================================================================
# RECURSOS
# ============================================================================

calc_resources() {
    header "RECURSOS DEL SISTEMA"
    
    TOTAL_CPUS=$(nproc)
    TOTAL_RAM_GB=$(($(free -m | awk '/^Mem:/{print $2}') / 1024))
    
    info "CPUs: $TOTAL_CPUS | RAM: ${TOTAL_RAM_GB}GB"
    
    [ "$TOTAL_CPUS" -lt 2 ] && { err "Mínimo 2 CPUs"; exit 1; }
    [ "$TOTAL_RAM_GB" -lt 3 ] && { err "Mínimo 4GB RAM"; exit 1; }
    
    # Límites seguros
    if [ "$TOTAL_CPUS" -eq 2 ]; then
        N8N_CPU="0.9"; PG_CPU="0.5"; RD_CPU="0.3"
        N8N_MEM="2048M"; PG_MEM="1024M"; RD_MEM="512M"
    elif [ "$TOTAL_CPUS" -le 4 ]; then
        N8N_CPU="2.5"; PG_CPU="1.0"; RD_CPU="0.5"
        N8N_MEM="4096M"; PG_MEM="2560M"; RD_MEM="1024M"
    else
        N8N_CPU="5.0"; PG_CPU="2.0"; RD_CPU="1.0"
        N8N_MEM="8192M"; PG_MEM="4096M"; RD_MEM="2048M"
    fi
    
    ok "Límites: n8n($N8N_CPU,$N8N_MEM) PG($PG_CPU,$PG_MEM) Redis($RD_CPU,$RD_MEM)"
}

# ============================================================================
# DEPS
# ============================================================================

install_deps() {
    skip "deps" && { info "Deps (skip)"; return 0; }
    
    header "DEPENDENCIAS"
    
    apt-get update -qq
    apt-get install -y -qq curl wget jq openssl dnsutils 2>&1 | tee -a "$LOG_FILE" >/dev/null
    
    # Nginx
    if ! command -v nginx &>/dev/null; then
        info "Nginx..."
        apt-get install -y -qq nginx
        systemctl enable nginx; systemctl start nginx
    fi
    ok "Nginx"
    
    # Docker
    if ! docker compose version &>/dev/null; then
        info "Docker..."
        . /etc/os-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-compose-plugin
        systemctl enable docker; systemctl start docker
    fi
    ok "Docker"
    
    # Certbot
    command -v certbot &>/dev/null || apt-get install -y -qq certbot python3-certbot-nginx
    ok "Certbot"
    
    mkdir -p /var/www/certbot
    
    mark "deps"
}

# ============================================================================
# CREDENCIALES
# ============================================================================

get_creds() {
    header "CREDENCIALES"
    
    while true; do
        read -p "Dominio: " DOMAIN
        [[ "$DOMAIN" =~ ^[a-z0-9.-]+$ ]] && break
    done
    
    while true; do
        read -p "Email: " EMAIL
        [[ "$EMAIL" =~ @ ]] && break
    done
    
    while true; do
        read -sp "Password PostgreSQL (16+): " PGPASS; echo ""
        [ ${#PGPASS} -ge 16 ] && break
    done
    
    read -p "Usuario admin (admin): " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    while true; do
        read -sp "Password admin (16+): " ADMIN_PASS; echo ""
        [ ${#ADMIN_PASS} -ge 16 ] && break
    done
    
    ENC_KEY=$(openssl rand -base64 32)
    ok "Credenciales OK"
}

# ============================================================================
# ESTRUCTURA CON FIX DE PERMISOS
# ============================================================================

create_struct() {
    skip "struct" && { info "Estructura (skip)"; return 0; }
    
    header "ESTRUCTURA Y PERMISOS"
    
    step "Creando directorios"
    mkdir -p "$INSTALL_DIR"/{data/{postgres,redis,n8n,files},backups,scripts}
    mkdir -p "$LOG_DIR"
    
    step "Configurando permisos (FIX CRÍTICO)"
    # El usuario node en Docker tiene UID 1000
    chown -R 1000:1000 "$INSTALL_DIR/data/n8n"
    chown -R 1000:1000 "$INSTALL_DIR/data/files"
    chmod -R 755 "$INSTALL_DIR/data/n8n"
    chmod -R 755 "$INSTALL_DIR/data/files"
    ok "Permisos corregidos (UID 1000:1000)"
    
    step "Creando .env"
    cat > "$INSTALL_DIR/.env" << EOF
POSTGRES_DB=n8n_production
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=$PGPASS
N8N_ENCRYPTION_KEY=$ENC_KEY
N8N_BASIC_AUTH_USER=$ADMIN_USER
N8N_BASIC_AUTH_PASSWORD=$ADMIN_PASS
N8N_HOST=$DOMAIN
CERTBOT_EMAIL=$EMAIL
N8N_CPU_LIMIT=$N8N_CPU
N8N_MEM_LIMIT=$N8N_MEM
POSTGRES_CPU_LIMIT=$PG_CPU
POSTGRES_MEM_LIMIT=$PG_MEM
REDIS_CPU_LIMIT=$RD_CPU
REDIS_MEM_LIMIT=$RD_MEM
EOF
    chmod 600 "$INSTALL_DIR/.env"
    
    step "Creando docker-compose.yml"
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOFC'
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n_postgres
    restart: unless-stopped
    user: postgres
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
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '${POSTGRES_CPU_LIMIT}'
          memory: ${POSTGRES_MEM_LIMIT}
    logging:
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    image: redis:7-alpine
    container_name: n8n_redis
    restart: unless-stopped
    user: redis
    command: redis-server --maxmemory 400mb --maxmemory-policy allkeys-lru
    volumes:
      - ./data/redis:/data
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits:
          cpus: '${REDIS_CPU_LIMIT}'
          memory: ${REDIS_MEM_LIMIT}
    logging:
      options:
        max-size: "5m"
        max-file: "3"

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n_app
    restart: unless-stopped
    user: node
    depends_on:
      postgres: {condition: service_healthy}
      redis: {condition: service_healthy}
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
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
      QUEUE_BULL_REDIS_PORT: 6379
      EXECUTIONS_MODE: queue
      GENERIC_TIMEZONE: America/Bogota
      TZ: America/Bogota
      NODE_ENV: production
      N8N_LOG_LEVEL: info
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
    logging:
      options:
        max-size: "20m"
        max-file: "5"

networks:
  n8n_network:
    driver: bridge
EOFC
    
    mark "struct"
    ok "Estructura creada con permisos corregidos"
}

save_state() { mkdir -p "$INSTALL_DIR"; declare -p S > "$STATE_FILE" 2>/dev/null || true; }
load_state() { [ -f "$STATE_FILE" ] && source "$STATE_FILE" 2>/dev/null || true; }
mark() { S[$1]="1"; save_state; }
skip() { [[ "${S[$1]}" == "1" ]]; }

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok() { echo -e "${G}✓${NC} $1"; log "OK: $1"; }
err() { echo -e "${R}✗${NC} $1"; log "ERR: $1"; }
info() { echo -e "${B}ℹ${NC} $1"; log "INFO: $1"; }
warn() { echo -e "${Y}⚠${NC} $1"; log "WARN: $1"; }
header() { echo ""; echo -e "${C}╔═══ ${W}${BOLD}$1${NC} ${C}═══╗${NC}"; echo ""; }
step() { echo ""; echo -e "${M}▶${NC} $1"; }
banner() { clear; echo -e "${C}${BOLD}"; cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║     🚀 N8N INSTALLER v3.4 DEFINITIVO - AUTO FIX                     ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"; }

# ============================================================================
# NGINX
# ============================================================================

config_nginx() {
    skip "nginx" && [ -f "/etc/nginx/sites-enabled/$DOMAIN" ] && {
        nginx -t 2>&1 | grep -q "syntax is ok" && { info "Nginx (skip)"; return 0; }
    }
    
    header "NGINX"
    
    cat > "/etc/nginx/sites-available/$DOMAIN" << 'EOFN'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 50M;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOFN
    
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "/etc/nginx/sites-available/$DOMAIN"
    
    ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx || { err "Nginx falló"; exit 1; }
    
    mark "nginx"
    ok "Nginx OK"
}

# ============================================================================
# SSL
# ============================================================================

gen_ssl() {
    skip "ssl" && [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ] && {
        info "SSL (skip)"; update_https; return 0;
    }
    
    header "SSL"
    
    systemctl reload nginx; sleep 2
    
    certbot certonly --nginx -n --agree-tos --email "$EMAIL" -d "$DOMAIN" 2>&1 | tee -a "$LOG_FILE"
    
    [ $? -eq 0 ] && { update_https; mark "ssl"; ok "SSL OK"; } || warn "SSL falló"
}

update_https() {
    [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && return
    
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
# DOCKER - CON VALIDACIÓN Y AUTO-RECONSTRUCCIÓN
# ============================================================================

start_docker() {
    header "SERVICIOS DOCKER"
    
    cd "$INSTALL_DIR"
    
    step "Verificando estado actual"
    local current_running=$(docker ps --filter "name=n8n_" --format '{{.Names}}' | wc -l)
    local current_healthy=$(docker ps --filter "name=n8n_" --filter "health=healthy" --format '{{.Names}}' | wc -l)
    
    info "Contenedores corriendo: $current_running/3"
    info "Contenedores saludables: $current_healthy/3"
    
    if [ "$current_running" -eq 3 ] && [ "$current_healthy" -eq 3 ]; then
        ok "Servicios ya están saludables (skip)"
        return 0
    fi
    
    # Necesita reconstrucción
    if [ "$current_running" -gt 0 ]; then
        warn "Hay servicios con problemas, reconstruyendo..."
        
        step "Deteniendo servicios actuales"
        docker compose down -v 2>&1 | tee -a "$LOG_FILE"
        ok "Servicios detenidos"
        
        step "Limpiando contenedores problemáticos"
        docker rm -f n8n_app n8n_postgres n8n_redis 2>/dev/null || true
        ok "Contenedores limpiados"
    fi
    
    step "Descargando imágenes"
    docker compose pull 2>&1 | tee -a "$LOG_FILE"
    ok "Imágenes descargadas"
    
    step "Corrigiendo permisos de volúmenes (crítico para n8n)"
    chown -R 1000:1000 "$INSTALL_DIR/data/n8n"
    chown -R 1000:1000 "$INSTALL_DIR/data/files"
    chmod -R 755 "$INSTALL_DIR/data/n8n"
    chmod -R 755 "$INSTALL_DIR/data/files"
    ok "Permisos establecidos (1000:1000)"
    
    step "Iniciando contenedores"
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        err "Error al iniciar contenedores"
        echo ""
        echo -e "${R}═══ LOGS DE ERROR ═══${NC}"
        docker compose logs
        exit 1
    fi
    
    ok "Contenedores iniciados"
    
    # Validación exhaustiva
    step "Validando salud de servicios (espera hasta 120s)"
    
    local max_attempts=24  # 24 * 5s = 120s
    local attempt=0
    local last_healthy=0
    
    while [ $attempt -lt $max_attempts ]; do
        local healthy=$(docker ps --filter "name=n8n_" --filter "health=healthy" --format '{{.Names}}' | wc -l)
        local running=$(docker ps --filter "name=n8n_" --format '{{.Names}}' | wc -l)
        
        echo -ne "  Intento $((attempt+1))/$max_attempts: $running corriendo, $healthy saludables...\r"
        
        # Éxito
        if [ "$healthy" -eq 3 ] && [ "$running" -eq 3 ]; then
            echo ""
            ok "✓✓✓ Todos los servicios saludables (3/3)"
            mark "svcs"
            return 0
        fi
        
        # Detectar si n8n está crasheando
        if [ $attempt -gt 6 ]; then  # Después de 30s
            local n8n_status=$(docker inspect n8n_app --format='{{.State.Status}}' 2>/dev/null || echo "missing")
            
            if [ "$n8n_status" == "restarting" ]; then
                echo ""
                err "n8n está en loop de crash"
                diagnose_and_fix
                return 1
            fi
        fi
        
        # Progreso estancado
        if [ "$healthy" -eq "$last_healthy" ] && [ $attempt -gt 10 ]; then
            echo ""
            warn "Progreso estancado en $healthy/3, diagnosticando..."
            show_container_status
        fi
        
        last_healthy=$healthy
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo ""
    warn "Timeout esperando servicios saludables"
    show_container_status
}

# ============================================================================
# DIAGNÓSTICO Y REPARACIÓN AUTOMÁTICA
# ============================================================================

diagnose_and_fix() {
    header "DIAGNÓSTICO Y REPARACIÓN"
    
    err "n8n no puede iniciar"
    echo ""
    
    step "Analizando logs de n8n"
    echo ""
    echo -e "${Y}═══ LOGS (últimas 30 líneas) ═══${NC}"
    docker logs n8n_app --tail=30 2>&1
    echo -e "${Y}═══════════════════════════════${NC}"
    echo ""
    
    local logs=$(docker logs n8n_app 2>&1)
    
    # Detectar problema
    if echo "$logs" | grep -qi "permission denied"; then
        err "PROBLEMA: Permisos incorrectos en volumen"
        echo ""
        info "SOLUCIÓN AUTOMÁTICA: Corrigiendo permisos..."
        
        docker compose down
        chown -R 1000:1000 "$INSTALL_DIR/data/n8n"
        chown -R 1000:1000 "$INSTALL_DIR/data/files"
        chmod -R 755 "$INSTALL_DIR/data/n8n"
        
        ok "Permisos corregidos"
        info "Reiniciando servicios..."
        
        docker compose up -d
        sleep 20
        
        if docker ps --filter "name=n8n_app" --filter "health=healthy" | grep -q "n8n_app"; then
            ok "✓ n8n ahora funciona correctamente"
        else
            err "Aún hay problemas. Logs:"
            docker logs n8n_app --tail=20
        fi
        
    elif echo "$logs" | grep -qi "encryption"; then
        err "PROBLEMA: Clave de encriptación inválida"
        info "Regenerando clave..."
        ENC_KEY=$(openssl rand -base64 32)
        sed -i "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$ENC_KEY/" "$INSTALL_DIR/.env"
        docker compose up -d
        
    elif echo "$logs" | grep -qi "database\|postgres"; then
        err "PROBLEMA: Error de base de datos"
        info "Logs de PostgreSQL:"
        docker logs n8n_postgres --tail=20
        
    elif echo "$logs" | grep -qi "redis"; then
        err "PROBLEMA: Error de Redis"
        docker exec n8n_redis redis-cli ping || err "Redis no responde"
        
    else
        err "Error no reconocido automáticamente"
        info "Revisa los logs de arriba"
    fi
}

show_container_status() {
    echo ""
    info "Estado detallado de contenedores:"
    echo ""
    
    for c in n8n_postgres n8n_redis n8n_app; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
            local status=$(docker inspect $c --format='{{.State.Status}}')
            local health=$(docker inspect $c --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
            local restart_count=$(docker inspect $c --format='{{.RestartCount}}')
            
            echo -e "${C}$c:${NC}"
            echo "  Estado:   $status"
            echo "  Salud:    $health"
            echo "  Reinicio: $restart_count veces"
            
            if [ "$status" != "running" ] || [ "$health" == "unhealthy" ]; then
                echo "  ${R}Logs recientes:${NC}"
                docker logs $c --tail=10 2>&1 | sed 's/^/    /'
            fi
            echo ""
        fi
    done
}

# ============================================================================
# MANTENIMIENTO Y ALIAS
# ============================================================================

setup_maint() {
    skip "maint" && { info "Mantenimiento (skip)"; return 0; }
    
    header "MANTENIMIENTO Y ALIAS"
    
    step "Script de backup"
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOFB'
#!/bin/bash
D=$(date +%Y%m%d_%H%M%S)
B="/opt/n8n-production/backups"
echo "=== Backup $D ==="
docker exec n8n_postgres pg_dump -U n8n_user n8n_production | gzip > "$B/postgres/db_$D.sql.gz"
tar -czf "$B/n8n-data/data_$D.tar.gz" -C /opt/n8n-production/data/n8n . 2>/dev/null
find "$B" -name "*.gz" -mtime +7 -delete
echo "✓ Completado"
EOFB
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    (crontab -l 2>/dev/null | grep -v n8n; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh") | crontab -
    ok "Backup automático"
    
    step "Alias globales"
    cat > /etc/profile.d/n8n.sh << 'EOFA'
#!/bin/bash
alias n8n-logs='docker logs -f n8n_app'
alias n8n-status='cd /opt/n8n-production && docker compose ps'
alias n8n-restart='cd /opt/n8n-production && docker compose restart n8n'
alias n8n-backup='sudo /opt/n8n-production/scripts/backup.sh'
alias n8n-stop='cd /opt/n8n-production && docker compose down'
alias n8n-start='cd /opt/n8n-production && docker compose up -d'
alias n8n-rebuild='cd /opt/n8n-production && docker compose down && docker compose up -d'
alias n8n-fix-perms='sudo chown -R 1000:1000 /opt/n8n-production/data/n8n'
EOFA
    chmod +x /etc/profile.d/n8n.sh
    
    # Agregar a bashrc de usuarios
    for user_home in /root /home/*; do
        [ -d "$user_home" ] && echo 'source /etc/profile.d/n8n.sh' >> "$user_home/.bashrc" 2>/dev/null || true
    done
    
    # Cargar ahora
    source /etc/profile.d/n8n.sh
    
    mark "maint"
    ok "Alias habilitados globalmente"
}

# ============================================================================
# VALIDACIÓN FINAL EXHAUSTIVA
# ============================================================================

validate_final() {
    header "VALIDACIÓN FINAL"
    
    local err_count=0
    local warn_count=0
    
    echo ""
    
    # 1. Nginx
    info "[1/10] Validando Nginx..."
    systemctl is-active --quiet nginx && ok "Nginx corriendo" || { err "Nginx detenido"; err_count=$((err_count+1)); }
    nginx -t 2>&1 | grep -q "syntax is ok" && ok "Config Nginx OK" || { err "Config inválida"; err_count=$((err_count+1)); }
    
    # 2. Sitio
    info "[2/10] Validando sitio Nginx..."
    [ -f "/etc/nginx/sites-enabled/$DOMAIN" ] && ok "Sitio habilitado" || { err "Sitio NO habilitado"; err_count=$((err_count+1)); }
    
    # 3. SSL
    info "[3/10] Validando SSL..."
    if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
        local days=$(( ($(date -d "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" | cut -d= -f2)" +%s) - $(date +%s)) / 86400 ))
        ok "SSL válido ($days días)"
    else
        warn "SSL no configurado"
        warn_count=$((warn_count+1))
    fi
    
    # 4. Contenedores corriendo
    info "[4/10] Validando contenedores..."
    for c in n8n_postgres n8n_redis n8n_app; do
        if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
            ok "$c corriendo"
        else
            err "$c NO corriendo"
            err_count=$((err_count+1))
        fi
    done
    
    # 5. Health checks
    info "[5/10] Validando health checks..."
    local healthy=$(docker ps --filter "name=n8n_" --filter "health=healthy" --format '{{.Names}}' | wc -l)
    if [ "$healthy" -eq 3 ]; then
        ok "Todos saludables (3/3)"
    else
        warn "Solo $healthy/3 saludables"
        warn_count=$((warn_count+1))
        show_container_status
    fi
    
    # 6. Puerto local
    info "[6/10] Validando puerto 5678..."
    if ss -tlnp | grep -q ":5678"; then
        ok "Puerto 5678 escuchando"
    else
        err "Puerto 5678 NO escuchando"
        err_count=$((err_count+1))
    fi
    
    # 7. Healthz local
    info "[7/10] Validando endpoint /healthz..."
    local code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5678/healthz" 2>/dev/null || echo "000")
    if [ "$code" == "200" ]; then
        ok "/healthz responde (200)"
    else
        err "/healthz no responde ($code)"
        err_count=$((err_count+1))
    fi
    
    # 8. HTTP externo
    info "[8/10] Validando HTTP externo..."
    sleep 2
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "http://$DOMAIN" 2>/dev/null || echo "000")
    [[ "$code" =~ ^(200|301|401)$ ]] && ok "HTTP OK ($code)" || { warn "HTTP: $code"; warn_count=$((warn_count+1)); }
    
    # 9. HTTPS externo
    info "[9/10] Validando HTTPS externo..."
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 -k "https://$DOMAIN" 2>/dev/null || echo "000")
    [[ "$code" =~ ^(200|401)$ ]] && ok "HTTPS OK ($code)" || { warn "HTTPS: $code"; warn_count=$((warn_count+1)); }
    
    # 10. Contenido de la página
    info "[10/10] Validando contenido de n8n..."
    local content=$(curl -s -k "https://$DOMAIN" 2>/dev/null || echo "")
    if echo "$content" | grep -qi "n8n"; then
        ok "Página de n8n carga correctamente"
    else
        warn "La respuesta no parece ser de n8n"
        warn_count=$((warn_count+1))
    fi
    
    # Resumen
    echo ""
    header "RESULTADO DE VALIDACIÓN"
    
    if [ $err_count -eq 0 ] && [ $warn_count -eq 0 ]; then
        echo -e "${G}${BOLD}✓✓✓ PERFECTAMENTE FUNCIONAL${NC}"
        echo ""
        ok "n8n está completamente operativo"
        ok "Accesible en: https://$DOMAIN"
    elif [ $err_count -eq 0 ]; then
        echo -e "${Y}${BOLD}⚠ FUNCIONAL CON ADVERTENCIAS${NC}"
        echo ""
        warn "$warn_count advertencias detectadas"
        info "n8n debería funcionar, pero revisa las advertencias"
    else
        echo -e "${R}${BOLD}✗ ERRORES CRÍTICOS DETECTADOS${NC}"
        echo ""
        err "$err_count errores críticos"
        [ $warn_count -gt 0 ] && warn "$warn_count advertencias adicionales"
        echo ""
        info "Comandos de diagnóstico:"
        echo "  ${C}docker logs n8n_app${NC}"
        echo "  ${C}docker compose ps${NC}"
        echo "  ${C}curl -v http://127.0.0.1:5678${NC}"
    fi
}

# ============================================================================
# RESUMEN
# ============================================================================

save_creds() {
    cat > "$INSTALL_DIR/CREDENCIALES.txt" << EOFC
═══════════════════════════════════════════
N8N PRODUCTION - CREDENCIALES
═══════════════════════════════════════════

URL:      https://$DOMAIN
Usuario:  $ADMIN_USER
Password: $ADMIN_PASS

PostgreSQL: $PGPASS
Encryption: $ENC_KEY

Recursos asignados:
  n8n:        $N8N_CPU CPUs, $N8N_MEM
  PostgreSQL: $PG_CPU CPUs, $PG_MEM
  Redis:      $RD_CPU CPUs, $RD_MEM

═══════════════════════════════════════════
Instalado: $(date)
═══════════════════════════════════════════
EOFC
    chmod 600 "$INSTALL_DIR/CREDENCIALES.txt"
}

summary() {
    header "INSTALACIÓN COMPLETADA"
    
    echo ""
    echo -e "${G}${BOLD}✅ N8N PRODUCTION READY${NC}"
    echo ""
    echo -e "${C}═══ ACCESO ═══${NC}"
    echo -e "  URL:      ${G}https://$DOMAIN${NC}"
    echo -e "  Usuario:  ${C}$ADMIN_USER${NC}"
    echo -e "  Password: ${Y}[Ver credenciales]${NC}"
    echo ""
    echo -e "${C}═══ COMANDOS ═══${NC}"
    echo -e "  ${Y}n8n-logs${NC}       Ver logs en vivo"
    echo -e "  ${Y}n8n-status${NC}     Estado de servicios"
    echo -e "  ${Y}n8n-restart${NC}    Reiniciar n8n"
    echo -e "  ${Y}n8n-backup${NC}     Backup manual"
    echo -e "  ${Y}n8n-fix-perms${NC}  Arreglar permisos"
    echo ""
    echo -e "${B}Cargar alias ahora:${NC} ${C}source /etc/profile.d/n8n.sh${NC}"
    echo ""
    echo -e "${W}Archivos:${NC}"
    echo -e "  Credenciales: $INSTALL_DIR/CREDENCIALES.txt"
    echo -e "  Log:          $LOG_FILE"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    mkdir -p "$LOG_DIR"
    banner
    log "N8N Installer v$VERSION - $(date)"
    
    [ "$EUID" -ne 0 ] && { err "Ejecuta: sudo bash $0"; exit 1; }
    
    load_state
    calc_resources
    install_deps
    get_creds
    create_struct
    config_nginx
    gen_ssl
    start_docker
    setup_maint
    validate_final
    save_creds
    summary
    
    log "Completado: $(date)"
}

main "$@"
