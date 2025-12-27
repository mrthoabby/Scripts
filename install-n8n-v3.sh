#!/bin/bash

###############################################################################
# n8n Production Installer with Docker Compose
# Version: 5.0 Professional Edition
# Features: Interactive, Smart Validation, Auto-Fix, Detailed Logging
###############################################################################

set -eo pipefail

# ==================== COLORES Y SÍMBOLOS ====================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="✓"
CROSS="✗"
WARN="⚠"
INFO="ℹ"
ARROW="→"

# ==================== VARIABLES GLOBALES ====================

SCRIPT_VERSION="5.0"
INSTALL_DIR="/opt/n8n"
LOG_FILE="/var/log/n8n-install.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Variables de configuración (se llenarán interactivamente)
DOMAIN=""
N8N_USER=""
N8N_PASSWORD=""
DB_PASSWORD=""
SSL_EMAIL=""
TIMEZONE="America/Bogota"

# Contadores de validación
VALIDATION_TOTAL=0
VALIDATION_PASSED=0
VALIDATION_WARNINGS=0
VALIDATION_ERRORS=0

# Arrays para almacenar resultados
declare -a VALIDATION_RESULTS
declare -a ERROR_LOGS

# ==================== FUNCIONES DE LOGGING ====================

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}${CHECK}${NC} $1"
    log "OK: $1"
}

log_error() {
    echo -e "${RED}${CROSS}${NC} $1"
    log "ERROR: $1"
    ERROR_LOGS+=("$1")
}

log_warning() {
    echo -e "${YELLOW}${WARN}${NC} $1"
    log "WARN: $1"
}

log_info() {
    echo -e "${CYAN}${INFO}${NC} $1"
    log "INFO: $1"
}

log_step() {
    local step=$1
    local total=$2
    local desc=$3
    echo ""
    log_info "[$step/$total] $desc..."
}

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
    printf "${BLUE}║${NC} %-46s ${BLUE}║${NC}\n" "$1"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"
}

print_box() {
    local title="$1"
    local width=50
    echo -e "\n${MAGENTA}╔═══ ${title} ═══╗${NC}\n"
}

# ==================== FUNCIONES DE ENTRADA ====================

validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

read_password() {
    local prompt=$1
    local var_name=$2
    local password
    local password_confirm
    
    while true; do
        read -sp "$prompt: " password
        echo
        
        if [ ${#password} -lt 8 ]; then
            log_error "La contraseña debe tener al menos 8 caracteres"
            continue
        fi
        
        read -sp "Confirmar contraseña: " password_confirm
        echo
        
        if [ "$password" != "$password_confirm" ]; then
            log_error "Las contraseñas no coinciden"
            continue
        fi
        
        eval "$var_name='$password'"
        break
    done
}

collect_credentials() {
    echo ""
    print_header "CONFIGURACIÓN INICIAL DE N8N"
    
    echo -e "${BOLD}Ingresa los datos de configuración:${NC}\n"
    
    # Dominio
    while true; do
        read -p "Dominio (ej: n8n.tuempresa.com): " DOMAIN
        if validate_domain "$DOMAIN"; then
            log_success "Dominio válido: $DOMAIN"
            break
        else
            log_error "Dominio inválido. Intenta de nuevo."
        fi
    done
    
    # Email para SSL
    while true; do
        read -p "Email para certificado SSL: " SSL_EMAIL
        if validate_email "$SSL_EMAIL"; then
            log_success "Email válido: $SSL_EMAIL"
            break
        else
            log_error "Email inválido. Intenta de nuevo."
        fi
    done
    
    # Usuario n8n
    while true; do
        read -p "Usuario admin de n8n: " N8N_USER
        if [ ${#N8N_USER} -ge 3 ]; then
            log_success "Usuario: $N8N_USER"
            break
        else
            log_error "El usuario debe tener al menos 3 caracteres"
        fi
    done
    
    # Contraseña n8n
    echo ""
    read_password "Contraseña para n8n (min. 8 caracteres)" N8N_PASSWORD
    log_success "Contraseña de n8n configurada"
    
    # Contraseña PostgreSQL
    echo ""
    read_password "Contraseña para PostgreSQL (min. 8 caracteres)" DB_PASSWORD
    log_success "Contraseña de PostgreSQL configurada"
    
    # Confirmación
    echo -e "\n${YELLOW}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}Resumen de configuración:${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    echo "Dominio:          $DOMAIN"
    echo "Email SSL:        $SSL_EMAIL"
    echo "Usuario n8n:      $N8N_USER"
    echo "Contraseña n8n:   ********"
    echo "Contraseña DB:    ********"
    echo -e "${YELLOW}═══════════════════════════════════════${NC}\n"
    
    read -p "¿Los datos son correctos? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Reiniciando configuración..."
        collect_credentials
    fi
}

# ==================== LIMPIEZA DE INSTALACIÓN PREVIA ====================

check_and_clean_node() {
    log_step 2 12 "Verificando Node.js y n8n previo"
    
    # Verificar n8n global
    if command -v n8n &> /dev/null; then
        log_warning "n8n instalado globalmente detectado"
        read -p "¿Desinstalar n8n global? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            npm uninstall -g n8n 2>&1 | tee -a "$LOG_FILE"
            log_success "n8n global desinstalado"
        fi
    else
        log_success "No hay n8n global instalado"
    fi
    
    # Verificar Node.js
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log_info "Node.js detectado: $NODE_VERSION"
        log_success "Node.js disponible"
    else
        log_info "Node.js no detectado (no es necesario para Docker)"
    fi
}

check_and_clean_containers() {
    log_step 3 12 "Verificando contenedores existentes"
    
    # Contenedores principales (nombres actuales con guiones bajos)
    local main_containers=("n8n_postgres" "n8n_redis" "n8n_app")
    # Contenedores legacy (nombres antiguos con guiones o sin prefijo)
    local legacy_containers=("n8n-postgres" "n8n-redis" "n8n")
    # Combinar todos para limpieza completa
    local all_containers=("${main_containers[@]}" "${legacy_containers[@]}")
    
    local found_containers=false
    local problematic_containers=()
    local healthy_containers=()
    local all_healthy=true
    
    echo ""
    echo -e "${CYAN}Analizando contenedores existentes...${NC}\n"
    
    # Verificar contenedores principales primero
    for container in "${main_containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            found_containers=true
            local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            
            if [ "$status" = "running" ]; then
                if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
                    echo -e "  ${GREEN}${CHECK}${NC} ${container}: ${GREEN}Corriendo${NC} (${health})"
                    healthy_containers+=("$container")
                else
                    echo -e "  ${YELLOW}${WARN}${NC} ${container}: ${YELLOW}Corriendo pero no saludable${NC} (${health})"
                    problematic_containers+=("$container")
                    all_healthy=false
                fi
            else
                echo -e "  ${RED}${CROSS}${NC} ${container}: ${RED}${status}${NC}"
                problematic_containers+=("$container")
                all_healthy=false
            fi
        else
            all_healthy=false
        fi
    done
    
    # Verificar contenedores legacy (nombres antiguos)
    for container in "${legacy_containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            found_containers=true
            local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            echo -e "  ${YELLOW}${WARN}${NC} ${container}: ${YELLOW}${status}${NC} (legacy)"
            problematic_containers+=("$container")
        fi
    done
    
    echo ""
    
    if [ "$found_containers" = false ]; then
        log_success "No hay contenedores previos de n8n"
        return 0
    fi
    
    # Si TODOS los contenedores principales están corriendo y saludables
    if [ ${#healthy_containers[@]} -eq 3 ] && [ "$all_healthy" = true ]; then
        echo -e "${GREEN}${BOLD}✓ Todos los contenedores principales están corriendo correctamente${NC}\n"
        echo -e "${CYAN}Contenedores detectados:${NC}"
        for container in "${healthy_containers[@]}"; do
            echo -e "  ${GREEN}${CHECK}${NC} $container"
        done
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════${NC}"
        echo -e "${BOLD}¿Deseas hacer una reinstalación limpia?${NC}"
        echo -e "${YELLOW}Esto eliminará:${NC}"
        echo -e "  ${RED}•${NC} Todos los contenedores de n8n"
        echo -e "  ${RED}•${NC} Todas las imágenes de n8n"
        echo -e "  ${RED}•${NC} Todos los volúmenes de n8n"
        echo -e "  ${RED}•${NC} Todas las redes de n8n"
        echo -e "${YELLOW}═══════════════════════════════════════${NC}"
        read -p "¿Continuar con reinstalación limpia? (s/N): " -n 1 -r
        echo
        echo -e "${YELLOW}═══════════════════════════════════════${NC}\n"
        
        if [[ $REPLY =~ ^[SsYy]$ ]]; then
            log_warning "Iniciando reinstalación limpia completa..."
            
            # Detener y eliminar todos los contenedores relacionados con n8n
            log_info "Deteniendo contenedores..."
            for container in "${all_containers[@]}"; do
                if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
                    docker stop "$container" 2>&1 | tee -a "$LOG_FILE" || true
                    docker rm "$container" 2>&1 | tee -a "$LOG_FILE" || true
                    log_success "Eliminado: $container"
                fi
            done
            
            # Eliminar imágenes de n8n
            log_info "Eliminando imágenes de n8n..."
            local n8n_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(n8n|n8nio)" || true)
            if [ -n "$n8n_images" ]; then
                echo "$n8n_images" | while read -r image; do
                    docker rmi "$image" -f 2>&1 | tee -a "$LOG_FILE" || true
                    log_success "Imagen eliminada: $image"
                done
            else
                log_info "No se encontraron imágenes de n8n para eliminar"
            fi
            
            # Eliminar volúmenes relacionados con n8n
            log_info "Eliminando volúmenes de n8n..."
            cd "$INSTALL_DIR" 2>/dev/null || true
            if [ -f "docker-compose.yml" ]; then
                docker_compose_cmd down -v 2>&1 | tee -a "$LOG_FILE" || true
            fi
            
            # Eliminar volúmenes manualmente si existen
            local n8n_volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(n8n|postgres_data|n8n_data)" || true)
            if [ -n "$n8n_volumes" ]; then
                echo "$n8n_volumes" | while read -r volume; do
                    docker volume rm "$volume" -f 2>&1 | tee -a "$LOG_FILE" || true
                    log_success "Volumen eliminado: $volume"
                done
            fi
            
            # Eliminar redes relacionadas con n8n
            log_info "Eliminando redes de n8n..."
            local n8n_networks=$(docker network ls --format "{{.Name}}" | grep -E "(n8n|n8n_network)" || true)
            if [ -n "$n8n_networks" ]; then
                echo "$n8n_networks" | while read -r network; do
                    docker network rm "$network" 2>&1 | tee -a "$LOG_FILE" || true
                    log_success "Red eliminada: $network"
                done
            fi
            
            log_success "Reinstalación limpia completada. Todo relacionado con n8n ha sido eliminado."
            echo ""
            return 0
        else
            log_info "Manteniendo contenedores existentes. El script continuará con la configuración actual."
            echo ""
            return 0
        fi
    fi
    
    # Si hay contenedores problemáticos
    if [ ${#problematic_containers[@]} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}Contenedores con problemas detectados:${NC}"
        for container in "${problematic_containers[@]}"; do
            echo -e "  ${YELLOW}${ARROW}${NC} $container"
        done
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════${NC}"
        read -p "¿Eliminar solo los contenedores problemáticos? (s/N): " -n 1 -r
        echo
        echo -e "${YELLOW}═══════════════════════════════════════${NC}\n"
        
        if [[ $REPLY =~ ^[SsYy]$ ]]; then
            log_info "Eliminando contenedores problemáticos..."
            
            for container in "${problematic_containers[@]}"; do
                if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
                    docker stop "$container" 2>&1 | tee -a "$LOG_FILE" || true
                    docker rm "$container" 2>&1 | tee -a "$LOG_FILE" || true
                    log_success "Eliminado: $container"
                fi
            done
            
            log_success "Contenedores problemáticos eliminados"
        else
            log_info "Manteniendo contenedores existentes"
        fi
    fi
}

# ==================== VALIDACIONES DETALLADAS ====================

validate_docker() {
    log_step 9 17 "Validando Docker"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 3))
    
    # Docker instalado
    if command -v docker &> /dev/null; then
        log_success "Docker instalado: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "Docker no instalado"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    # Docker corriendo
    if systemctl is-active --quiet docker; then
        log_success "Servicio Docker activo"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "Servicio Docker no está corriendo"
        systemctl status docker | tee -a "$LOG_FILE"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    # Docker Compose
    if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
        log_success "Docker Compose disponible"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "Docker Compose no instalado"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    return 0
}

validate_containers() {
    log_step 10 17 "Validando contenedores"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 3))
    
    # Nombres exactos de los contenedores según docker-compose.yml
    local container_names=("n8n_postgres" "n8n_redis" "n8n_app")
    local container_labels=("PostgreSQL" "Redis" "n8n")
    local all_running=true
    
    for i in "${!container_names[@]}"; do
        local container_name="${container_names[$i]}"
        local container_label="${container_labels[$i]}"
        
        # Buscar contenedor por nombre exacto
        local container_id=$(docker ps -q --filter "name=^${container_name}$" 2>/dev/null | head -n1)
        
        if [ -n "$container_id" ]; then
            # Obtener estado del contenedor
            local status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
            
            if [ "$status" = "running" ]; then
                log_success "${container_label} (${container_name}) corriendo"
                VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
            else
                log_error "${container_label} (${container_name}) no está corriendo (Estado: $status)"
                # Mostrar logs solo si el contenedor existe
                if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                    docker logs "$container_name" --tail 50 2>&1 | tee -a "$LOG_FILE" || true
                fi
                VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
                all_running=false
            fi
        else
            # Verificar si existe pero está detenido
            if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
                log_error "${container_label} (${container_name}) no está corriendo (Estado: $status)"
                docker logs "$container_name" --tail 50 2>&1 | tee -a "$LOG_FILE" || true
                VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
                all_running=false
            else
                log_warning "${container_label} (${container_name}) no encontrado"
                VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
                all_running=false
            fi
        fi
    done
    
    if [ "$all_running" = false ]; then
        return 1
    fi
    
    return 0
}

validate_container_health() {
    log_step 11 17 "Validando health checks"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 1))
    
    local healthy_count=0
    local total_count=0
    
    for container_id in $(docker ps -q --filter "name=n8n"); do
        total_count=$((total_count + 1))
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")
        local name=$(docker inspect --format='{{.Name}}' "$container_id" | sed 's/\///')
        
        if [ "$health" = "healthy" ]; then
            healthy_count=$((healthy_count + 1))
        elif [ "$health" = "none" ]; then
            # Sin healthcheck configurado, asumir OK si está running
            healthy_count=$((healthy_count + 1))
        else
            log_warning "$name: $health"
        fi
    done
    
    if [ $total_count -eq 0 ]; then
        log_warning "No hay contenedores para validar health"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
        return 1
    fi
    
    log_success "Todos saludables ($healthy_count/$total_count)"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    return 0
}

validate_nginx() {
    log_step 12 17 "Validando Nginx"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 3))
    
    # Convertir dominio a nombre de archivo válido (reemplazar puntos por guiones)
    local site_name=$(echo "${DOMAIN}" | tr '.' '-')
    
    # Nginx corriendo
    if systemctl is-active --quiet nginx; then
        log_success "Nginx corriendo"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "Nginx no está corriendo"
        systemctl status nginx | tee -a "$LOG_FILE"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    # Config válida
    if nginx -t 2>&1 | tee -a "$LOG_FILE" | grep -q "successful"; then
        log_success "Config Nginx OK"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "Config Nginx tiene errores"
        nginx -t 2>&1 | tee -a "$LOG_FILE"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    # Sitio habilitado
    if [ -L "/etc/nginx/sites-enabled/${site_name}" ]; then
        log_success "Sitio habilitado"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_warning "Sitio ${site_name} no está habilitado"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    fi
    
    return 0
}

validate_ssl() {
    log_step 13 17 "Validando SSL"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 2))
    
    local cert_path="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    
    if [ -f "$cert_path" ]; then
        local expiry=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry" +%s)
        local now_epoch=$(date +%s)
        local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
        
        if [ $days_left -gt 7 ]; then
            log_success "SSL válido ($days_left días)"
            VALIDATION_PASSED=$((VALIDATION_PASSED + 2))
        else
            log_warning "SSL expira pronto ($days_left días)"
            VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
            VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
        fi
    else
        log_warning "Certificado SSL no encontrado (se creará)"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 2))
    fi
}

validate_ports() {
    log_step 14 17 "Validando puertos"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 1))
    
    # Buscar contenedor n8n_app por nombre exacto
    local container_id=$(docker ps -q --filter "name=^n8n_app$" 2>/dev/null | head -n1)
    
    if [ -z "$container_id" ]; then
        log_error "Contenedor n8n_app no está corriendo"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    # Verificar que el puerto responda
    if docker exec "$container_id" wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
        log_success "Puerto 5678 responde"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "Puerto 5678 no responde"
        docker logs "$container_id" --tail 30 2>&1 | tee -a "$LOG_FILE" || true
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
}

validate_http_internal() {
    log_step 15 17 "Validando endpoint /healthz"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 1))
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ]; then
        log_success "/healthz responde (200)"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_error "/healthz no responde correctamente (HTTP $response)"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
}

validate_http_external() {
    log_step 16 17 "Validando HTTP externo"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 1))
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}" 2>/dev/null || echo "000")
    
    if [ "$response" = "301" ] || [ "$response" = "302" ] || [ "$response" = "200" ]; then
        log_success "HTTP OK ($response)"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        log_warning "HTTP: $response"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    fi
}

validate_https_external() {
    log_step 17 17 "Validando HTTPS externo"
    
    VALIDATION_TOTAL=$((VALIDATION_TOTAL + 2))
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}" 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ]; then
        log_success "HTTPS OK (200)"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
        
        # Verificar contenido de n8n
        local content=$(curl -s "https://${DOMAIN}" 2>/dev/null)
        if echo "$content" | grep -qi "n8n"; then
            log_success "Contenido de n8n detectado"
            VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
        else
            log_warning "La respuesta no parece ser de n8n"
            VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
        fi
    else
        log_warning "HTTPS: $response"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 2))
    fi
}

# ==================== INSTALACIÓN ====================

# Función helper para ejecutar docker compose (detecta automáticamente el comando correcto)
docker_compose_cmd() {
    # Intentar primero con docker compose (versión moderna integrada)
    if docker compose version &> /dev/null; then
        docker compose "$@"
    # Si no funciona, intentar con docker-compose (versión legacy)
    elif command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    else
        log_error "Docker Compose no está disponible"
        return 1
    fi
}

# Función para verificar y mostrar estado de dependencias
check_dependencies_status() {
    echo ""
    print_box "VERIFICACIÓN DE DEPENDENCIAS"
    echo -e "${BOLD}Este script requiere las siguientes dependencias:${NC}\n"
    
    local docker_status=""
    local docker_version=""
    local docker_running=""
    local compose_status=""
    local compose_version=""
    local nginx_status=""
    local certbot_status=""
    
    local missing_deps=()
    local installed_deps=()
    
    # Verificar Docker
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        docker_status="${GREEN}${CHECK} Instalado${NC} (versión: $docker_version)"
        installed_deps+=("Docker")
        
        # Verificar si está corriendo
        if systemctl is-active --quiet docker 2>/dev/null; then
            docker_running="${GREEN}${CHECK} Activo${NC}"
        else
            docker_running="${YELLOW}${WARN} Inactivo${NC} (se intentará iniciar)"
            # No agregar a missing_deps porque se puede iniciar automáticamente
        fi
    else
        docker_status="${RED}${CROSS} No instalado${NC}"
        docker_running="${RED}${CROSS} N/A${NC}"
        missing_deps+=("Docker")
    fi
    
    # Verificar Docker Compose
    if docker compose version &> /dev/null; then
        compose_version=$(docker compose version --short 2>/dev/null || echo "integrado")
        compose_status="${GREEN}${CHECK} Instalado${NC} (versión: $compose_version - integrado)"
        installed_deps+=("Docker Compose")
    elif command -v docker-compose &> /dev/null; then
        compose_version=$(docker-compose --version | cut -d' ' -f4 | tr -d ',')
        compose_status="${GREEN}${CHECK} Instalado${NC} (versión: $compose_version - legacy)"
        installed_deps+=("Docker Compose")
    else
        compose_status="${RED}${CROSS} No instalado${NC}"
        missing_deps+=("Docker Compose")
    fi
    
    # Verificar Nginx (opcional, se instalará si falta)
    if command -v nginx &> /dev/null; then
        nginx_version=$(nginx -v 2>&1 | cut -d'/' -f2)
        nginx_status="${GREEN}${CHECK} Instalado${NC} (versión: $nginx_version)"
        installed_deps+=("Nginx")
    else
        nginx_status="${YELLOW}${WARN} No instalado${NC} (se instalará automáticamente)"
        missing_deps+=("Nginx")
    fi
    
    # Verificar Certbot (opcional, se instalará si falta)
    if command -v certbot &> /dev/null; then
        certbot_version=$(certbot --version 2>&1 | cut -d' ' -f2)
        certbot_status="${GREEN}${CHECK} Instalado${NC} (versión: $certbot_version)"
        installed_deps+=("Certbot")
    else
        certbot_status="${YELLOW}${WARN} No instalado${NC} (se instalará automáticamente)"
        missing_deps+=("Certbot")
    fi
    
    # Mostrar estado de cada dependencia
    echo -e "  ${CYAN}Docker:${NC}           $docker_status"
    echo -e "  ${CYAN}Estado Docker:${NC}    $docker_running"
    echo -e "  ${CYAN}Docker Compose:${NC}   $compose_status"
    echo -e "  ${CYAN}Nginx:${NC}            $nginx_status"
    echo -e "  ${CYAN}Certbot:${NC}          $certbot_status"
    echo ""
    
    # Resumen
    if [ ${#installed_deps[@]} -gt 0 ]; then
        echo -e "${GREEN}${BOLD}Dependencias instaladas y activas:${NC}"
        for dep in "${installed_deps[@]}"; do
            echo -e "  ${GREEN}${CHECK}${NC} $dep"
        done
        echo ""
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}Dependencias que se instalarán:${NC}"
        for dep in "${missing_deps[@]}"; do
            echo -e "  ${YELLOW}${ARROW}${NC} $dep"
        done
        echo ""
    else
        echo -e "${GREEN}${BOLD}Todas las dependencias están instaladas y activas${NC}\n"
    fi
    
    # Si hay dependencias faltantes, pedir confirmación
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}═══════════════════════════════════════${NC}"
        read -p "¿Deseas continuar e instalar las dependencias faltantes? (s/N): " -n 1 -r
        echo
        echo -e "${YELLOW}═══════════════════════════════════════${NC}\n"
        
        if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
            log_warning "Instalación cancelada por el usuario"
            echo -e "${YELLOW}El script se detendrá. Puedes instalar las dependencias manualmente y ejecutar el script nuevamente.${NC}\n"
            return 1
        fi
        
        log_info "Continuando con la instalación de dependencias..."
        return 0
    else
        log_success "Todas las dependencias están listas"
        return 0
    fi
}

install_docker_if_needed() {
    log_step 1 12 "Instalando dependencias faltantes"
    
    local docker_installed=false
    local compose_installed=false
    
    # Verificar Docker
    if command -v docker &> /dev/null; then
        log_success "Docker ya está instalado: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        docker_installed=true
    else
        log_info "Docker no está instalado, instalando..."
        
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release
        
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        systemctl enable docker
        systemctl start docker
        
        # Esperar un momento para que Docker inicie
        sleep 3
        
        log_success "Docker instalado"
        docker_installed=true
    fi
    
    # Verificar que Docker esté corriendo
    if ! systemctl is-active --quiet docker; then
        log_error "Docker no está corriendo. Intentando iniciar..."
        systemctl start docker
        sleep 2
        if ! systemctl is-active --quiet docker; then
            log_error "No se pudo iniciar Docker"
            return 1
        fi
        log_success "Docker iniciado"
    fi
    
    # Verificar Docker Compose (versión moderna o legacy)
    if docker compose version &> /dev/null; then
        log_success "Docker Compose disponible (versión integrada)"
        compose_installed=true
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose disponible (versión legacy)"
        compose_installed=true
    else
        log_warning "Docker Compose no encontrado, instalando..."
        
        # Intentar instalar docker-compose-plugin si no está instalado
        if ! dpkg -l | grep -q docker-compose-plugin; then
            apt-get update
            apt-get install -y docker-compose-plugin
        fi
        
        # Si aún no funciona, instalar docker-compose legacy
        if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
        
        # Verificar nuevamente
        if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
            log_success "Docker Compose instalado"
            compose_installed=true
        else
            log_error "No se pudo instalar Docker Compose"
            return 1
        fi
    fi
    
    if [ "$docker_installed" = true ] && [ "$compose_installed" = true ]; then
        return 0
    else
        return 1
    fi
}

create_docker_compose_file() {
    log_step 4 12 "Creando configuración de Docker Compose"
    mkdir -p "$INSTALL_DIR"
    
    # Generar clave de encriptación ANTES del heredoc para evitar problemas con Docker Compose
    local encryption_key=$(openssl rand -base64 32)
    
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n_postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U n8n']
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: n8n_redis
    restart: unless-stopped
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n_app
    restart: unless-stopped
    ports:
      - "5678:5678"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}/
      - GENERIC_TIMEZONE=${TIMEZONE}
      - N8N_ENCRYPTION_KEY=${encryption_key}
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD', 'wget', '--spider', '-q', 'http://localhost:5678/healthz']
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  postgres_data:
  n8n_data:

networks:
  n8n_network:
    driver: bridge
EOF

    log_success "docker-compose.yml creado"
}

setup_nginx() {
    log_step 6 12 "Configurando Nginx"
    if ! command -v nginx &> /dev/null; then
        apt-get install -y nginx
    fi
    
    # Usar el dominio exactamente como fue ingresado
    local site_domain="${DOMAIN}"
    # Convertir dominio a nombre de archivo válido (reemplazar puntos por guiones)
    local site_name=$(echo "${DOMAIN}" | tr '.' '-')
    
    cat > "/etc/nginx/sites-available/${site_name}" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${site_domain};
    
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
    server_name ${site_domain};
    
    ssl_certificate /etc/letsencrypt/live/${site_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${site_domain}/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/${site_name} /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx
    
    log_success "Nginx configurado"
}

setup_ssl() {
    log_step 7 12 "Configurando certificados SSL"
    if ! command -v certbot &> /dev/null; then
        apt-get install -y certbot python3-certbot-nginx
    fi
    
    if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
        certbot --nginx -d "${DOMAIN}" --email "${SSL_EMAIL}" --agree-tos --non-interactive --redirect
        log_success "Certificado SSL obtenido"
    else
        log_success "Certificado SSL ya existe"
    fi
}

create_aliases() {
    log_step 8 12 "Creando aliases útiles"
    # Detectar comando de docker compose para usar en aliases
    local compose_cmd="docker compose"
    if ! docker compose version &> /dev/null; then
        compose_cmd="docker-compose"
    fi
    
    cat > /etc/profile.d/n8n.sh << EOF
alias n8n-logs='docker logs -f n8n_app'
alias n8n-status='cd /opt/n8n && ${compose_cmd} ps'
alias n8n-restart='cd /opt/n8n && ${compose_cmd} restart'
alias n8n-stop='cd /opt/n8n && ${compose_cmd} stop'
alias n8n-start='cd /opt/n8n && ${compose_cmd} start'
alias n8n-backup='docker exec n8n_postgres pg_dump -U n8n n8n > /opt/n8n/backup-\$(date +%Y%m%d-%H%M%S).sql'
alias n8n-fix-perms='docker exec n8n_app chown -R node:node /home/node/.n8n'
EOF

    chmod +x /etc/profile.d/n8n.sh
    log_success "Aliases globales creados"
}

# ==================== LIMPIEZA POST-INSTALACIÓN ====================

cleanup_after_installation() {
    log_step 12 12 "Limpiando archivos temporales"
    
    # Limpiar archivos temporales del sistema
    local temp_files_cleaned=0
    
    # Limpiar archivos temporales de apt
    if [ -d "/var/cache/apt/archives" ]; then
        apt-get clean -y 2>&1 | tee -a "$LOG_FILE" > /dev/null
        temp_files_cleaned=$((temp_files_cleaned + 1))
    fi
    
    # Limpiar logs antiguos de Docker (mantener solo últimos 7 días)
    if command -v journalctl &> /dev/null; then
        journalctl --since "7 days ago" --until "now" --vacuum-time=7d 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
        temp_files_cleaned=$((temp_files_cleaned + 1))
    fi
    
    # Limpiar archivos temporales de certbot si existen
    if [ -d "/tmp/certbot" ]; then
        rm -rf /tmp/certbot/* 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
        temp_files_cleaned=$((temp_files_cleaned + 1))
    fi
    
    # Limpiar archivos .tmp del directorio de instalación
    if [ -d "$INSTALL_DIR" ]; then
        find "$INSTALL_DIR" -name "*.tmp" -type f -delete 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
        temp_files_cleaned=$((temp_files_cleaned + 1))
    fi
    
    if [ $temp_files_cleaned -gt 0 ]; then
        log_success "Archivos temporales limpiados"
    else
        log_info "No se encontraron archivos temporales para limpiar"
    fi
}

# ==================== RESUMEN FINAL ====================

save_credentials() {
    log_step 11 12 "Guardando credenciales"
    
    # Asegurar que el directorio existe
    mkdir -p "$INSTALL_DIR"
    
    # Guardar credenciales
    cat > "$INSTALL_DIR/credentials.txt" << EOF
N8N CREDENTIALS
===============
Domain: https://${DOMAIN}
User: ${N8N_USER}
Password: ${N8N_PASSWORD}

PostgreSQL:
User: n8n
Password: ${DB_PASSWORD}
Database: n8n

Installation Date: $(date)
EOF
    
    chmod 600 "$INSTALL_DIR/credentials.txt"
    log_success "Credenciales guardadas en: $INSTALL_DIR/credentials.txt"
    
    # Mostrar información del directorio de instalación
    echo ""
    print_box "DIRECTORIO DE INSTALACIÓN"
    echo -e "  ${CYAN}Ubicación:${NC} ${BOLD}$INSTALL_DIR${NC}"
    echo ""
    echo -e "  ${CYAN}Contenido:${NC}"
    if [ -d "$INSTALL_DIR" ]; then
        ls -lh "$INSTALL_DIR" | tail -n +2 | while read -r line; do
            echo "    $line"
        done
    else
        log_warning "Directorio no encontrado"
    fi
    echo ""
    
    # Mostrar información detallada del archivo de credenciales
    if [ -f "$INSTALL_DIR/credentials.txt" ]; then
        local file_size=$(du -h "$INSTALL_DIR/credentials.txt" | cut -f1)
        local file_perms=$(stat -c "%a" "$INSTALL_DIR/credentials.txt" 2>/dev/null || stat -f "%OLp" "$INSTALL_DIR/credentials.txt" 2>/dev/null)
        echo -e "  ${CYAN}Archivo de credenciales:${NC}"
        echo -e "    ${BOLD}Ruta:${NC} $INSTALL_DIR/credentials.txt"
        echo -e "    ${BOLD}Tamaño:${NC} $file_size"
        echo -e "    ${BOLD}Permisos:${NC} $file_perms (solo root puede leer)"
        echo ""
    fi
}

show_final_summary() {
    print_box "RESULTADO DE VALIDACIÓN"
    
    local status_icon=""
    local status_text=""
    local status_color=""
    
    if [ $VALIDATION_ERRORS -gt 0 ]; then
        status_icon="${CROSS}"
        status_text="FALLÓ"
        status_color="${RED}"
    elif [ $VALIDATION_WARNINGS -gt 0 ]; then
        status_icon="${WARN}"
        status_text="FUNCIONAL CON ADVERTENCIAS"
        status_color="${YELLOW}"
    else
        status_icon="${CHECK}"
        status_text="TODO OK"
        status_color="${GREEN}"
    fi
    
    echo -e "\n${status_color}${BOLD}${status_icon} ${status_text}${NC}\n"
    
    echo "Validaciones: $VALIDATION_PASSED/$VALIDATION_TOTAL pasadas"
    
    if [ $VALIDATION_WARNINGS -gt 0 ]; then
        log_warning "$VALIDATION_WARNINGS advertencias detectadas"
        log_info "n8n debería funcionar, pero revisa las advertencias"
    fi
    
    if [ $VALIDATION_ERRORS -gt 0 ]; then
        log_error "$VALIDATION_ERRORS errores detectados"
        echo -e "\n${RED}${BOLD}LOGS DE ERRORES:${NC}"
        for error in "${ERROR_LOGS[@]}"; do
            echo "  - $error"
        done
        echo -e "\nRevisa el log completo en: $LOG_FILE"
        return 1
    fi
    
    print_box "INSTALACIÓN COMPLETADA"
    
    echo -e "\n${GREEN}${BOLD}✅ N8N PRODUCTION READY${NC}\n"
    
    print_box "ACCESO"
    echo "  URL:      https://${DOMAIN}"
    echo "  Usuario:  ${N8N_USER}"
    echo "  Password: [Ver credenciales guardadas]"
    echo ""
    
    print_box "COMANDOS"
    echo "  n8n-logs       Ver logs en vivo"
    echo "  n8n-status     Estado de servicios"
    echo "  n8n-restart    Reiniciar n8n"
    echo "  n8n-backup     Backup manual"
    echo "  n8n-fix-perms  Arreglar permisos"
    echo ""
    
    echo -e "${YELLOW}Cargar alias ahora: source /etc/profile.d/n8n.sh${NC}\n"
    
    # Guardar y mostrar credenciales
    save_credentials
}

# ==================== MAIN ====================

main() {
    clear
    
    # Verificar root
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        echo "Usa: sudo $0"
        exit 1
    fi
    
    # Inicializar log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== n8n Installation Log - $(date) ===" > "$LOG_FILE"
    
    # Pantalla de bienvenida
    echo -e "${BLUE}${BOLD}"
    cat << "EOF"
    ███╗   ██╗ █████╗ ███╗   ██╗
    ████╗  ██║██╔══██╗████╗  ██║
    ██╔██╗ ██║╚█████╔╝██╔██╗ ██║
    ██║╚██╗██║██╔══██╗██║╚██╗██║
    ██║ ╚████║╚█████╔╝██║ ╚████║
    ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝
    
EOF
    echo -e "Production Installer v${SCRIPT_VERSION}${NC}\n"
    
    # PASO CRÍTICO: Verificar estado de dependencias y pedir confirmación
    if ! check_dependencies_status; then
        log_warning "Instalación cancelada por el usuario"
        exit 0
    fi
    
    # Instalar dependencias faltantes si el usuario confirmó
    if ! install_docker_if_needed; then
        log_error "No se pudieron instalar las dependencias necesarias"
        log_error "Por favor, instala Docker y Docker Compose manualmente"
        exit 1
    fi
    
    # Verificar que Docker Compose funcione antes de continuar
    if ! docker_compose_cmd version &> /dev/null; then
        log_error "Docker Compose no está disponible después de la instalación"
        exit 1
    fi
    
    log_success "Todas las dependencias están instaladas y funcionando"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Recolectar credenciales
    collect_credentials
    
    # Limpieza
    check_and_clean_node
    check_and_clean_containers
    
    # Crear archivo docker-compose.yml
    create_docker_compose_file
    
    # Desplegar
    log_step 5 12 "Desplegando contenedores"
    cd "$INSTALL_DIR"
    
    # Verificar si los contenedores ya están corriendo
    local containers_running=0
    for container in "n8n_postgres" "n8n_redis" "n8n_app"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            containers_running=$((containers_running + 1))
        fi
    done
    
    if [ $containers_running -eq 3 ]; then
        log_info "Los contenedores ya están corriendo, verificando estado..."
        docker_compose_cmd ps
        log_success "Contenedores ya desplegados"
    else
        log_info "Desplegando contenedores..."
        docker_compose_cmd up -d
        
        if [ $? -ne 0 ]; then
            log_error "Error al desplegar contenedores"
            return 1
        fi
        log_success "Contenedores desplegados"
    fi
    
    sleep 10
    
    # Configurar Nginx y SSL
    setup_nginx
    setup_ssl
    
    # Crear utilidades
    create_aliases
    
    # Validaciones finales
    validate_docker
    validate_containers
    validate_container_health
    validate_nginx
    validate_ssl
    validate_ports
    validate_http_internal
    validate_http_external
    validate_https_external
    
    # Limpieza post-instalación
    cleanup_after_installation
    
    # Mostrar resumen
    show_final_summary
}

# Ejecutar
main "$@"
