#!/bin/bash
###############################################################################
# N8N INSTALLER v4.1 - FIX SSL + ALIAS
###############################################################################

set -e
trap 'echo -e "\033[0;31m✗ Error línea $LINENO\033[0m"; exit 1' ERR

# Config
VERSION="4.1"
DIR="/opt/n8n-production"
LOG="/var/log/n8n/install-$(date +%Y%m%d_%H%M%S).log"

# Colores
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; W='\033[1;37m'; NC='\033[0m'

# Recursos
CPUS=0; RAM=0
N8N_C=""; N8N_M=""; PG_C=""; PG_M=""; RD_C=""; RD_M=""

# Creds
DOM=""; MAIL=""; PGPW=""; USR=""; PASS=""; KEY=""

mkdir -p "$(dirname $LOG)"
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
ok() { echo -e "${G}✓${NC} $1"; log "$1"; }
err() { echo -e "${R}✗${NC} $1"; log "ERR: $1"; }
info() { echo -e "${B}ℹ${NC} $1"; }
warn() { echo -e "${Y}⚠${NC} $1"; }
hdr() { echo ""; echo -e "${C}╔═══ ${W}$1${NC} ${C}═══╗${NC}"; echo ""; }

banner() {
    clear
    echo -e "${C}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║          🚀 N8N INSTALLER v4.1 - SSL FIX + ALIAS                    ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Recursos
calc_res() {
    hdr "RECURSOS"
    
    CPUS=$(nproc)
    RAM=$(($(free -m | awk '/^Mem:/{print $2}') / 1024))
    
    info "Sistema: $CPUS CPUs, ${RAM}GB RAM"
    
    [ "$CPUS" -lt 2 ] && { err "Mínimo 2 CPUs"; exit 1; }
    [ "$RAM" -lt 3 ] && { err "Mínimo 4GB RAM"; exit 1; }
    
    # Límites SEGUROS
    if [ "$CPUS" -eq 2 ]; then
        N8N_C="0.9"; PG_C="0.5"; RD_C="0.3"
        [ "$RAM" -ge 8 ] && { N8N_M="3G"; PG_M="1536M"; RD_M="512M"; } || { N8N_M="2G"; PG_M="1G"; RD_M="512M"; }
    elif [ "$CPUS" -le 4 ]; then
        N8N_C="2.0"; PG_C="0.8"; RD_C="0.4"
        N8N_M="4G"; PG_M="2G"; RD_M="1G"
    else
        N8N_C="4.0"; PG_C="1.5"; RD_C="0.8"
        N8N_M="8G"; PG_M="4G"; RD_M="2G"
    fi
    
    ok "Límites: n8n($N8N_C,$N8N_M) PG($PG_C,$PG_M) Redis($RD_C,$RD_M)"
}

# Deps
inst_deps() {
    hdr "DEPENDENCIAS"
    
    apt-get update -qq
    apt-get install -y -qq curl wget jq openssl dnsutils 2>&1 | tee -a "$LOG" >/dev/null
    
    command -v nginx &>/dev/null || {
        apt-get install -y -qq nginx
        systemctl enable nginx; systemctl start nginx
    }
    ok "Nginx"
    
    docker compose version &>/dev/null || {
        . /etc/os-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-compose-plugin
        systemctl enable docker; systemctl start docker
    }
    ok "Docker"
    
    command -v certbot &>/dev/null || apt-get install -y -qq certbot python3-certbot-nginx
    ok "Certbot"
    
    mkdir -p /var/www/certbot
}

# Creds
get_creds() {
    hdr "CREDENCIALES"
    
    read -p "Dominio: " DOM
    read -p "Email: " MAIL
    
    while true; do
        read -sp "Password PostgreSQL (16+): " PGPW; echo ""
        [ ${#PGPW} -ge 16 ] || { err "Mínimo 16 chars"; continue; }
        read -sp "Confirmar: " P2; echo ""
        [ "$PGPW" == "$P2" ] && break
        err "No coinciden"
    done
    
    read -p "Usuario admin (admin): " USR
    USR=${USR:-admin}
    
    while true; do
        read -sp "Password admin (16+): " PASS; echo ""
        [ ${#PASS} -ge 16 ] || { err "Mínimo 16 chars"; continue; }
        read -sp "Confirmar: " P2; echo ""
        [ "$PASS" == "$P2" ] && break
        err "No coinciden"
    done
    
    KEY=$(openssl rand -base64 32)
    ok "Credenciales OK"
}

# Estructura
mk_str() {
    hdr "ESTRUCTURA"
    
    mkdir -p "$DIR"/{data/{postgres,redis,n8n,files},backups,scripts}
    mkdir -p /var/log/n8n
    
    chown -R 1000:1000 "$DIR/data/n8n" "$DIR/data/files"
    chmod -R 755 "$DIR/data/n8n"
    
    cat > "$DIR/.env" << EOF
POSTGRES_DB=n8n_db
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=$PGPW
N8N_ENCRYPTION_KEY=$KEY
N8N_BASIC_AUTH_USER=$USR
N8N_BASIC_AUTH_PASSWORD=$PASS
N8N_HOST=$DOM
CERTBOT_EMAIL=$MAIL
N8N_CPU_LIMIT=$N8N_C
N8N_MEM_LIMIT=$N8N_M
POSTGRES_CPU_LIMIT=$PG_C
POSTGRES_MEM_LIMIT=$PG_M
REDIS_CPU_LIMIT=$RD_C
REDIS_MEM_LIMIT=$RD_M
EOF
    chmod 600 "$DIR/.env"
    
    cat > "$DIR/docker-compose.yml" << 'EOFC'
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
      - n8n_net
    healthcheck:
      test: ['CMD', 'pg_isready', '-U', '${POSTGRES_USER}']
      interval: 10s
    deploy:
      resources:
        limits: {cpus: '${POSTGRES_CPU_LIMIT}', memory: ${POSTGRES_MEM_LIMIT}}

  redis:
    image: redis:7-alpine
    container_name: n8n_redis
    restart: unless-stopped
    command: redis-server --maxmemory 400mb --maxmemory-policy allkeys-lru
    volumes:
      - ./data/redis:/data
    networks:
      - n8n_net
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 10s
    deploy:
      resources:
        limits: {cpus: '${REDIS_CPU_LIMIT}', memory: ${REDIS_MEM_LIMIT}}

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
      NODE_ENV: production
    volumes:
      - ./data/n8n:/home/node/.n8n
      - ./data/files:/files
    networks:
      - n8n_net
    healthcheck:
      test: ['CMD-SHELL', 'wget -q --spider http://localhost:5678/healthz']
      interval: 30s
      start_period: 90s
    deploy:
      resources:
        limits: {cpus: '${N8N_CPU_LIMIT}', memory: ${N8N_MEM_LIMIT}}

networks:
  n8n_net:
EOFC
    
    ok "Estructura OK"
}

# Nginx con SSL MEJORADO
cfg_nginx() {
    hdr "NGINX + SSL MEJORADO"
    
    cat > "/etc/nginx/sites-available/$DOM" << EOFN
server {
    listen 80;
    listen [::]:80;
    server_name $DOM;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOM;
    
    # SSL
    ssl_certificate /etc/letsencrypt/live/$DOM/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOM/privkey.pem;
    
    # SSL Config mejorada
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOM/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Logs
    access_log /var/log/nginx/n8n_access.log;
    error_log /var/log/nginx/n8n_error.log;
    
    # Proxy a n8n
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        
        # Headers importantes
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # WebSocket
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_redirect off;
        
        client_max_body_size 50M;
    }
}
EOFN
    
    ln -sf "/etc/nginx/sites-available/$DOM" "/etc/nginx/sites-enabled/$DOM"
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx || { err "Nginx error"; exit 1; }
    ok "Nginx OK"
}

# SSL con validación
gen_ssl() {
    hdr "SSL"
    
    if [ -f "/etc/letsencrypt/live/$DOM/cert.pem" ]; then
        local d=$(( ($(date -d "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOM/cert.pem" | cut -d= -f2)" +%s) - $(date +%s)) / 86400 ))
        if [ $d -gt 30 ]; then
            ok "SSL válido ($d días)"
            return 0
        fi
        warn "Renovando certificado..."
    fi
    
    systemctl reload nginx; sleep 2
    
    certbot certonly --nginx -n --agree-tos --email "$MAIL" -d "$DOM" --rsa-key-size 4096 2>&1 | tee -a "$LOG"
    
    if [ $? -eq 0 ]; then
        ok "SSL generado"
        cfg_nginx  # Actualizar nginx con SSL
        systemctl enable certbot.timer 2>/dev/null || true
    else
        warn "SSL falló"
    fi
}

# Docker
start_dock() {
    hdr "DOCKER"
    
    cd "$DIR"
    
    docker compose down -v 2>/dev/null || true
    docker compose pull
    
    chown -R 1000:1000 "$DIR/data/n8n" "$DIR/data/files"
    
    docker compose up -d
    
    info "Esperando servicios..."
    for i in {1..24}; do
        local h=$(docker ps --filter "name=n8n_" --filter "health=healthy" | wc -l)
        h=$((h - 1))
        echo -ne "  $h/3 saludables...\r"
        [ $h -eq 3 ] && { echo ""; ok "3/3 OK"; return 0; }
        sleep 5
    done
    
    echo ""
    warn "Timeout, verificando..."
    docker compose ps
}

# ALIAS GLOBALES - FIX DEFINITIVO
setup_alias() {
    hdr "ALIAS GLOBALES"
    
    # Crear archivo de alias
    cat > /etc/profile.d/n8n-aliases.sh << 'EOFA'
#!/bin/bash
# N8N Aliases - Auto-load

alias n8n-logs='docker logs -f n8n_app'
alias n8n-status='cd /opt/n8n-production && docker compose ps'
alias n8n-restart='cd /opt/n8n-production && docker compose restart n8n'
alias n8n-backup='sudo /opt/n8n-production/scripts/backup.sh'
alias n8n-stop='cd /opt/n8n-production && docker compose down'
alias n8n-start='cd /opt/n8n-production && docker compose up -d'
alias n8n-fix='sudo chown -R 1000:1000 /opt/n8n-production/data/n8n && cd /opt/n8n-production && docker compose restart n8n'
alias n8n-diagnose='docker logs n8n_app --tail=100'
alias n8n-rebuild='cd /opt/n8n-production && docker compose down && docker compose up -d'

# Autocompletado
_n8n_completion() {
    local commands="logs status restart backup stop start fix diagnose rebuild"
    COMPREPLY=($(compgen -W "$commands" -- "${COMP_WORDS[1]}"))
}
complete -F _n8n_completion n8n-
EOFA
    
    chmod +x /etc/profile.d/n8n-aliases.sh
    ok "Alias creado"
    
    # Agregar a TODOS los .bashrc
    for bashrc in /root/.bashrc /home/*/.bashrc; do
        [ -f "$bashrc" ] && {
            grep -q "n8n-aliases.sh" "$bashrc" || \
                echo -e "\n# N8N Aliases\n[ -f /etc/profile.d/n8n-aliases.sh ] && . /etc/profile.d/n8n-aliases.sh" >> "$bashrc"
        }
    done
    ok "Alias agregado a .bashrc"
    
    # Cargar en sesión actual
    . /etc/profile.d/n8n-aliases.sh
    ok "Alias cargado en sesión actual"
    
    # Backup script
    cat > "$DIR/scripts/backup.sh" << 'EOFB'
#!/bin/bash
D=$(date +%Y%m%d_%H%M%S)
docker exec n8n_postgres pg_dump -U n8n_user n8n_db | gzip > "/opt/n8n-production/backups/postgres/db_$D.sql.gz"
echo "Backup: $D"
EOFB
    chmod +x "$DIR/scripts/backup.sh"
    
    (crontab -l 2>/dev/null | grep -v n8n; echo "0 2 * * * $DIR/scripts/backup.sh") | crontab -
    ok "Backup automático"
}

# Validación DETALLADA
validate() {
    hdr "VALIDACIÓN EXHAUSTIVA"
    
    local e=0; local w=0
    
    echo ""
    
    # 1. Nginx
    info "[1/12] Nginx running"
    systemctl is-active --quiet nginx && ok "Corriendo" || { err "Detenido"; e=$((e+1)); }
    
    info "[2/12] Nginx config"
    nginx -t 2>&1 | grep -q "syntax is ok" && ok "Válida" || { err "Inválida"; e=$((e+1)); }
    
    info "[3/12] Sitio habilitado"
    [ -L "/etc/nginx/sites-enabled/$DOM" ] && ok "Habilitado" || { err "NO habilitado"; e=$((e+1)); }
    
    info "[4/12] SSL instalado"
    if [ -f "/etc/letsencrypt/live/$DOM/cert.pem" ]; then
        local d=$(( ($(date -d "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOM/cert.pem" | cut -d= -f2)" +%s) - $(date +%s)) / 86400 ))
        ok "SSL OK ($d días)"
    else
        warn "SSL no instalado"
        w=$((w+1))
    fi
    
    info "[5/12] Contenedor n8n_postgres"
    docker ps | grep -q "n8n_postgres" && ok "Corriendo" || { err "Detenido"; e=$((e+1)); }
    
    info "[6/12] Contenedor n8n_redis"
    docker ps | grep -q "n8n_redis" && ok "Corriendo" || { err "Detenido"; e=$((e+1)); }
    
    info "[7/12] Contenedor n8n_app"
    docker ps | grep -q "n8n_app" && ok "Corriendo" || { err "Detenido"; e=$((e+1)); }
    
    info "[8/12] Health checks"
    local h=$(docker ps --filter "name=n8n_" --filter "health=healthy" | wc -l)
    h=$((h - 1))
    [ $h -eq 3 ] && ok "3/3 saludables" || { warn "$h/3 saludables"; w=$((w+1)); }
    
    info "[9/12] Puerto 5678"
    ss -tlnp | grep -q ":5678" && ok "Escuchando" || { err "NO escuchando"; e=$((e+1)); }
    
    info "[10/12] n8n local /healthz"
    local c=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5678/healthz")
    [ "$c" == "200" ] && ok "Responde (200)" || { err "No responde ($c)"; e=$((e+1)); }
    
    info "[11/12] HTTPS externo"
    c=$(curl -s -o /dev/null -w "%{http_code}" -k -m 10 "https://$DOM")
    if [[ "$c" =~ ^(200|401)$ ]]; then
        ok "HTTPS OK ($c)"
    else
        err "HTTPS error ($c)"
        info "  Probando sin -k (verificación SSL)..."
        c=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$DOM" 2>&1 || echo "SSL_ERROR")
        info "  Resultado: $c"
        e=$((e+1))
    fi
    
    info "[12/12] Contenido n8n"
    local cont=$(curl -s -k "https://$DOM" 2>/dev/null)
    if echo "$cont" | grep -qi "n8n\|workflow"; then
        ok "Página n8n carga"
    else
        warn "Respuesta no es n8n"
        info "  Primeras líneas:"
        echo "$cont" | head -3 | sed 's/^/    /'
        w=$((w+1))
    fi
    
    echo ""
    
    # Resumen
    if [ $e -eq 0 ] && [ $w -eq 0 ]; then
        echo -e "${G}${BOLD}✓✓✓ TODO PERFECTO${NC}"
    elif [ $e -eq 0 ]; then
        echo -e "${Y}⚠ FUNCIONAL ($w advertencias)${NC}"
    else
        echo -e "${R}✗ $e ERRORES${NC}"
        echo ""
        info "Comandos de diagnóstico:"
        echo "  docker logs n8n_app"
        echo "  curl -vk https://$DOM"
        echo "  sudo nginx -T | grep ssl"
    fi
}

# Test final de conectividad
test_conn() {
    hdr "TEST DE CONECTIVIDAD FINAL"
    
    info "Probando acceso completo al sitio..."
    echo ""
    
    info "1. Test local HTTP"
    curl -s -o /dev/null -w "   Status: %{http_code}\n" "http://127.0.0.1:5678"
    
    info "2. Test local HTTPS (ignorando SSL)"
    curl -s -o /dev/null -w "   Status: %{http_code}\n" -k "https://127.0.0.1"
    
    info "3. Test externo HTTP"
    curl -s -o /dev/null -w "   Status: %{http_code}\n" -m 10 "http://$DOM"
    
    info "4. Test externo HTTPS (ignorando SSL)"
    curl -s -o /dev/null -w "   Status: %{http_code}\n" -k -m 10 "https://$DOM"
    
    info "5. Test externo HTTPS (con verificación SSL)"
    curl -s -o /dev/null -w "   Status: %{http_code}\n" -m 10 "https://$DOM" 2>&1 || warn "Error de verificación SSL"
    
    echo ""
    
    info "Si ves 'Sitio peligroso' en Chrome:"
    echo "  1. El certificado SSL está bien instalado"
    echo "  2. Chrome está siendo extra cauteloso"
    echo "  3. Solución: Clic en 'Detalles' → 'Acceder al sitio'"
    echo "  4. O usa modo incógnito"
    echo ""
}

# Resumen
save_cr() {
    cat > "$DIR/CREDENCIALES.txt" << EOFC
═══════════════════════════════════════════
N8N PRODUCTION
═══════════════════════════════════════════

URL:      https://$DOM
Usuario:  $USR
Password: $PASS

PostgreSQL: $PGPW
Encryption: $KEY

Recursos:
  n8n:  $N8N_C CPU, $N8N_M
  PG:   $PG_C CPU, $PG_M
  Redis: $RD_C CPU, $RD_M

Instalado: $(date)
═══════════════════════════════════════════
EOFC
    chmod 600 "$DIR/CREDENCIALES.txt"
}

summ() {
    hdr "¡COMPLETADO!"
    
    echo -e "${G}${BOLD}✅ N8N FUNCIONANDO${NC}"
    echo ""
    echo -e "${C}URL:${NC} ${G}https://$DOM${NC}"
    echo -e "${C}Usuario:${NC} $USR"
    echo ""
    echo -e "${Y}ALIAS (ya cargados):${NC}"
    echo "  n8n-logs       n8n-status     n8n-restart"
    echo "  n8n-backup     n8n-fix        n8n-diagnose"
    echo ""
    echo -e "${B}Si los alias no funcionan:${NC}"
    echo -e "  ${C}source /etc/profile.d/n8n-aliases.sh${NC}"
    echo -e "  ${C}exec bash${NC}  (reiniciar shell)"
    echo ""
    echo -e "${Y}Sobre 'Sitio peligroso':${NC}"
    echo "  • El SSL está BIEN instalado"
    echo "  • Chrome es muy estricto"
    echo "  • Clic: Detalles → Acceder al sitio"
    echo ""
}

# Main
main() {
    mkdir -p "$LOG_DIR"
    banner
    log "v$VERSION - $(date)"
    
    [ "$EUID" -ne 0 ] && { err "Ejecuta: sudo bash $0"; exit 1; }
    
    calc_res
    inst_deps
    get_creds
    mk_str
    cfg_nginx
    gen_ssl
    start_dock
    setup_alias
    validate
    test_conn
    save_cr
    summ
    
    log "Completado"
}

main "$@"
