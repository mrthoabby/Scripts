#!/bin/bash

###############################################################################
#
#  N8N PRODUCTION INSTALLER v3.0 - ULTIMATE EDITION
#  
#  Características v3.0:
#  ✓ Solicita TODAS las credenciales al inicio
#  ✓ Detección inteligente de instalaciones previas
#  ✓ Re-ejecución segura (no duplica configuraciones)
#  ✓ Limpieza automática de archivos temporales
#  ✓ Validación exhaustiva en cada paso
#  ✓ Rollback automático en caso de error
#  
###############################################################################

set -e
trap 'handle_error $LINENO' ERR

# ============================================================================
# VARIABLES GLOBALES
# ============================================================================

SCRIPT_VERSION="3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/n8n-production"
LOG_DIR="/var/log/n8n"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d_%H%M%S).log"
TEMP_DIR="/tmp/n8n-install-$$"
STATE_FILE="${INSTALL_DIR}/.install_state"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Variables de usuario (se solicitan al inicio)
DOMAIN=""
CERTBOT_EMAIL=""
POSTGRES_PASSWORD=""
N8N_ADMIN_USER=""
N8N_ADMIN_PASSWORD=""
N8N_ENCRYPTION_KEY=""
N8N_RUNNERS_TOKEN=""

# Estado de instalación
declare -A INSTALL_STATUS=(
    ["system_check"]="pending"
    ["dependencies"]="pending"
    ["docker"]="pending"
    ["nginx"]="pending"
    ["certbot"]="pending"
    ["dns"]="pending"
    ["directories"]="pending"
    ["env_file"]="pending"
    ["docker_compose"]="pending"
    ["nginx_config"]="pending"
    ["ssl_cert"]="pending"
    ["docker_services"]="pending"
    ["maintenance"]="pending"
)

# ============================================================================
# FUNCIONES DE MANEJO DE ERRORES Y ESTADO
# ============================================================================

handle_error() {
    local line_no=$1
    echo ""
    echo -e "${RED}${BOLD}✗ ERROR EN LÍNEA $line_no${NC}"
    echo -e "${YELLOW}Revisa el log: ${LOG_FILE}${NC}"
    echo ""
    
    # Intentar limpiar archivos temporales
    cleanup_temp_files
    
    # Guardar estado
    save_install_state
    
    echo -e "${CYAN}Puedes volver a ejecutar el script para continuar desde donde se detuvo.${NC}"
    exit 1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "${RED}✗ ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

save_install_state() {
    mkdir -p "$INSTALL_DIR"
    declare -p INSTALL_STATUS > "$STATE_FILE" 2>/dev/null || true
    log "Estado de instalación guardado"
}

load_install_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE" 2>/dev/null || true
        log "Estado de instalación cargado"
        return 0
    fi
    return 1
}

update_status() {
    local step=$1
    local status=$2
    INSTALL_STATUS[$step]=$status
    save_install_state
}

check_status() {
    local step=$1
    echo "${INSTALL_STATUS[$step]:-pending}"
}

# ============================================================================
# FUNCIONES DE UI
# ============================================================================

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║       🚀 N8N PRODUCTION INSTALLER v3.0 - ULTIMATE EDITION 🚀        ║
║                                                                      ║
║       • Instalación Inteligente                                     ║
║       • Re-ejecución Segura                                         ║
║       • Limpieza Automática                                         ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}  ✗${NC} $1"
    log "ERROR: $1"
}

print_info() {
    echo -e "${BLUE}  ℹ${NC} $1"
    log "INFO: $1"
}

print_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
    log "WARNING: $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${WHITE}${BOLD}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${MAGENTA}▶${NC} ${BOLD}$1${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [${CYAN}%c${NC}]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ============================================================================
# LIMPIEZA DE ARCHIVOS TEMPORALES
# ============================================================================

cleanup_temp_files() {
    print_header "LIMPIEZA DE ARCHIVOS TEMPORALES"
    
    local cleaned=0
    
    # Limpiar directorio temporal de instalación
    if [ -d "$TEMP_DIR" ]; then
        print_step "Eliminando directorio temporal: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
        cleaned=$((cleaned + 1))
    fi
    
    # Limpiar archivos temporales de Docker
    if command -v docker &> /dev/null; then
        print_step "Limpiando caché de Docker"
        docker system prune -f > /dev/null 2>&1 || true
        cleaned=$((cleaned + 1))
    fi
    
    # Limpiar archivos de configuración temporal de Nginx
    if [ -d "/tmp/nginx-*" ]; then
        print_step "Eliminando archivos temporales de Nginx"
        rm -rf /tmp/nginx-* 2>/dev/null || true
        cleaned=$((cleaned + 1))
    fi
    
    # Limpiar logs antiguos de instalación
    if [ -d "$LOG_DIR" ]; then
        print_step "Limpiando logs antiguos (>30 días)"
        find "$LOG_DIR" -name "install-*.log" -mtime +30 -delete 2>/dev/null || true
        cleaned=$((cleaned + 1))
    fi
    
    # Limpiar apt cache
    print_step "Limpiando caché de apt"
    apt-get clean > /dev/null 2>&1 || true
    apt-get autoclean > /dev/null 2>&1 || true
    cleaned=$((cleaned + 1))
    
    if [ $cleaned -gt 0 ]; then
        print_success "Archivos temporales limpiados ($cleaned operaciones)"
    else
        print_info "No hay archivos temporales para limpiar"
    fi
}

# ============================================================================
# DETECCIÓN DE INSTALACIONES PREVIAS
# ============================================================================

detect_previous_installation() {
    print_header "DETECCIÓN DE INSTALACIÓN PREVIA"
    
    local has_installation=false
    local components_found=()
    
    # Verificar directorio de instalación
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Se encontró directorio de instalación: $INSTALL_DIR"
        components_found+=("Directorio")
        has_installation=true
    fi
    
    # Verificar contenedores Docker
    if command -v docker &> /dev/null; then
        if docker ps -a --format '{{.Names}}' | grep -q "n8n_"; then
            print_warning "Se encontraron contenedores de n8n existentes"
            components_found+=("Contenedores Docker")
            has_installation=true
            
            echo ""
            print_info "Contenedores encontrados:"
            docker ps -a --filter "name=n8n_" --format "  • {{.Names}} ({{.Status}})"
        fi
    fi
    
    # Verificar configuración de Nginx
    if [ -f "/etc/nginx/sites-available/$DOMAIN" ] || [ -f "/etc/nginx/sites-available/n8n.gedabengineers.dev" ]; then
        print_warning "Se encontró configuración de Nginx existente"
        components_found+=("Configuración Nginx")
        has_installation=true
    fi
    
    # Verificar certificado SSL
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ] || [ -d "/etc/letsencrypt/live/n8n.gedabengineers.dev" ]; then
        print_warning "Se encontró certificado SSL existente"
        components_found+=("Certificado SSL")
        has_installation=true
    fi
    
    # Verificar estado de instalación
    if [ -f "$STATE_FILE" ]; then
        print_warning "Se encontró archivo de estado de instalación previa"
        components_found+=("Estado de instalación")
        has_installation=true
        load_install_state
    fi
    
    if $has_installation; then
        echo ""
        print_header "INSTALACIÓN PREVIA DETECTADA"
        
        echo -e "${YELLOW}Se encontraron los siguientes componentes:${NC}"
        for component in "${components_found[@]}"; do
            echo -e "  ${CYAN}•${NC} $component"
        done
        echo ""
        
        echo -e "${CYAN}Opciones:${NC}"
        echo -e "  ${WHITE}[1]${NC} Continuar/Reparar instalación existente"
        echo -e "  ${WHITE}[2]${NC} Eliminar todo y hacer instalación limpia"
        echo -e "  ${WHITE}[3]${NC} Cancelar"
        echo ""
        
        read -p "$(echo -e ${YELLOW}Selecciona una opción \[1-3\]:${NC}) " option
        
        case $option in
            1)
                print_info "Continuando con instalación existente..."
                return 0
                ;;
            2)
                print_warning "Se eliminará la instalación existente"
                read -p "$(echo -e ${RED}¿Estás seguro? Esto eliminará TODOS los datos \(y/N\):${NC}) " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    remove_previous_installation
                else
                    print_info "Operación cancelada"
                    exit 0
                fi
                ;;
            3)
                print_info "Instalación cancelada por el usuario"
                exit 0
                ;;
            *)
                print_error "Opción inválida"
                exit 1
                ;;
        esac
    else
        print_success "No se detectó instalación previa"
    fi
}

remove_previous_installation() {
    print_header "ELIMINANDO INSTALACIÓN PREVIA"
    
    # Detener y eliminar contenedores
    if command -v docker &> /dev/null; then
        print_step "Deteniendo contenedores Docker"
        if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
            cd "$INSTALL_DIR"
            docker compose down -v 2>/dev/null || true
        fi
        
        print_step "Eliminando contenedores de n8n"
        docker rm -f n8n_app n8n_postgres n8n_redis 2>/dev/null || true
        
        print_step "Eliminando volúmenes de Docker"
        docker volume rm n8n-production_postgres_data n8n-production_redis_data n8n-production_n8n_data 2>/dev/null || true
    fi
    
    # Eliminar configuración de Nginx
    print_step "Eliminando configuración de Nginx"
    rm -f /etc/nginx/sites-enabled/n8n.* 2>/dev/null || true
    rm -f /etc/nginx/sites-available/n8n.* 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || true
    
    # Eliminar directorio de instalación
    print_step "Eliminando directorio de instalación"
    if [ -d "$INSTALL_DIR" ]; then
        # Hacer backup de credenciales si existen
        if [ -f "$INSTALL_DIR/CREDENCIALES.txt" ]; then
            mkdir -p /root/n8n-backups
            cp "$INSTALL_DIR/CREDENCIALES.txt" "/root/n8n-backups/CREDENCIALES_backup_$(date +%Y%m%d_%H%M%S).txt"
            print_info "Credenciales respaldadas en /root/n8n-backups/"
        fi
        
        rm -rf "$INSTALL_DIR"
    fi
    
    # Limpiar estado
    rm -f "$STATE_FILE" 2>/dev/null || true
    
    print_success "Instalación previa eliminada completamente"
    
    # Reinicializar estado
    for key in "${!INSTALL_STATUS[@]}"; do
        INSTALL_STATUS[$key]="pending"
    done
}

# ============================================================================
# RECOLECCIÓN DE CREDENCIALES AL INICIO
# ============================================================================

collect_all_credentials() {
    print_header "CONFIGURACIÓN INICIAL - CREDENCIALES"
    
    echo -e "${YELLOW}${BOLD}Por favor, proporciona TODA la información necesaria para la instalación.${NC}"
    echo -e "${CYAN}Esta información se solicitará solo una vez.${NC}"
    echo ""
    
    # ========================================================================
    # DOMINIO
    # ========================================================================
    print_step "1/5 - Dominio"
    echo -e "${CYAN}Ingresa el dominio donde se publicará n8n${NC}"
    echo -e "${WHITE}Ejemplo: n8n.tudominio.com${NC}"
    echo ""
    
    while true; do
        read -p "$(echo -e ${GREEN}Dominio:${NC}) " DOMAIN
        
        # Validar formato de dominio
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            print_success "Dominio válido: $DOMAIN"
            break
        else
            print_error "Formato de dominio inválido"
            echo -e "${YELLOW}El dominio debe tener un formato válido (ej: n8n.ejemplo.com)${NC}"
        fi
    done
    
    echo ""
    
    # ========================================================================
    # EMAIL PARA SSL
    # ========================================================================
    print_step "2/5 - Email para certificados SSL"
    echo -e "${CYAN}Email para notificaciones de Let's Encrypt${NC}"
    echo -e "${WHITE}Se usará para avisos de renovación de certificados${NC}"
    echo ""
    
    while true; do
        read -p "$(echo -e ${GREEN}Email:${NC}) " CERTBOT_EMAIL
        
        # Validar email
        if [[ "$CERTBOT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_success "Email válido: $CERTBOT_EMAIL"
            break
        else
            print_error "Formato de email inválido"
        fi
    done
    
    echo ""
    
    # ========================================================================
    # CONTRASEÑA DE POSTGRESQL
    # ========================================================================
    print_step "3/5 - Contraseña de PostgreSQL"
    echo -e "${CYAN}Contraseña para la base de datos PostgreSQL${NC}"
    echo -e "${YELLOW}Requisitos: Mínimo 16 caracteres, incluir mayúsculas, minúsculas, números${NC}"
    echo ""
    
    while true; do
        read -sp "$(echo -e ${GREEN}Password PostgreSQL:${NC}) " POSTGRES_PASSWORD
        echo ""
        
        # Validar longitud
        if [ ${#POSTGRES_PASSWORD} -lt 16 ]; then
            print_error "La contraseña debe tener al menos 16 caracteres"
            continue
        fi
        
        # Validar complejidad
        if [[ ! "$POSTGRES_PASSWORD" =~ [A-Z] ]] || [[ ! "$POSTGRES_PASSWORD" =~ [a-z] ]] || [[ ! "$POSTGRES_PASSWORD" =~ [0-9] ]]; then
            print_error "La contraseña debe incluir mayúsculas, minúsculas y números"
            continue
        fi
        
        read -sp "$(echo -e ${GREEN}Confirma password:${NC}) " POSTGRES_PASSWORD_CONFIRM
        echo ""
        
        if [ "$POSTGRES_PASSWORD" == "$POSTGRES_PASSWORD_CONFIRM" ]; then
            print_success "Contraseña de PostgreSQL configurada"
            break
        else
            print_error "Las contraseñas no coinciden"
        fi
    done
    
    echo ""
    
    # ========================================================================
    # USUARIO Y CONTRASEÑA DE N8N
    # ========================================================================
    print_step "4/5 - Credenciales de administrador n8n"
    echo -e "${CYAN}Usuario y contraseña para acceder a la interfaz web de n8n${NC}"
    echo ""
    
    # Usuario
    read -p "$(echo -e ${GREEN}Usuario admin \(default: admin\):${NC}) " N8N_ADMIN_USER
    N8N_ADMIN_USER=${N8N_ADMIN_USER:-admin}
    print_success "Usuario configurado: $N8N_ADMIN_USER"
    
    echo ""
    
    # Contraseña
    echo -e "${YELLOW}Requisitos: Mínimo 16 caracteres, incluir mayúsculas, minúsculas, números${NC}"
    echo ""
    
    while true; do
        read -sp "$(echo -e ${GREEN}Password admin n8n:${NC}) " N8N_ADMIN_PASSWORD
        echo ""
        
        # Validar longitud
        if [ ${#N8N_ADMIN_PASSWORD} -lt 16 ]; then
            print_error "La contraseña debe tener al menos 16 caracteres"
            continue
        fi
        
        # Validar complejidad
        if [[ ! "$N8N_ADMIN_PASSWORD" =~ [A-Z] ]] || [[ ! "$N8N_ADMIN_PASSWORD" =~ [a-z] ]] || [[ ! "$N8N_ADMIN_PASSWORD" =~ [0-9] ]]; then
            print_error "La contraseña debe incluir mayúsculas, minúsculas y números"
            continue
        fi
        
        read -sp "$(echo -e ${GREEN}Confirma password:${NC}) " N8N_ADMIN_PASSWORD_CONFIRM
        echo ""
        
        if [ "$N8N_ADMIN_PASSWORD" == "$N8N_ADMIN_PASSWORD_CONFIRM" ]; then
            print_success "Contraseña de n8n configurada"
            break
        else
            print_error "Las contraseñas no coinciden"
        fi
    done
    
    echo ""
    
    # ========================================================================
    # CLAVES DE ENCRIPTACIÓN
    # ========================================================================
    print_step "5/5 - Generación de claves de encriptación"
    echo -e "${CYAN}Generando claves seguras automáticamente...${NC}"
    echo ""
    
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n')
    N8N_RUNNERS_TOKEN=$(openssl rand -base64 32 | tr -d '\n')
    
    print_success "Clave de encriptación generada (32 bytes)"
    print_success "Token de runners generado (32 bytes)"
    
    echo ""
    
    # ========================================================================
    # RESUMEN
    # ========================================================================
    print_header "RESUMEN DE CONFIGURACIÓN"
    
    echo -e "${WHITE}Verifica que la información sea correcta:${NC}"
    echo ""
    echo -e "  ${CYAN}Dominio:${NC}                $DOMAIN"
    echo -e "  ${CYAN}Email SSL:${NC}              $CERTBOT_EMAIL"
    echo -e "  ${CYAN}Usuario n8n:${NC}            $N8N_ADMIN_USER"
    echo -e "  ${CYAN}Password PostgreSQL:${NC}    ${GREEN}[configurado]${NC}"
    echo -e "  ${CYAN}Password n8n:${NC}           ${GREEN}[configurado]${NC}"
    echo -e "  ${CYAN}Claves encriptación:${NC}    ${GREEN}[generadas]${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}¿Es correcta toda la información? \(Y/n\):${NC}) " confirm
    confirm=${confirm:-Y}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Configuración cancelada. Vuelve a ejecutar el script."
        exit 0
    fi
    
    print_success "Configuración confirmada. Procediendo con la instalación..."
    
    # Guardar credenciales en archivo temporal seguro
    mkdir -p "$TEMP_DIR"
    chmod 700 "$TEMP_DIR"
    
    cat > "$TEMP_DIR/credentials.env" << EOF
DOMAIN=$DOMAIN
CERTBOT_EMAIL=$CERTBOT_EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ADMIN_USER=$N8N_ADMIN_USER
N8N_ADMIN_PASSWORD=$N8N_ADMIN_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_RUNNERS_TOKEN=$N8N_RUNNERS_TOKEN
EOF
    
    chmod 600 "$TEMP_DIR/credentials.env"
    
    log "Credenciales recopiladas y guardadas temporalmente"
}

# ============================================================================
# VERIFICACIONES
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Este script debe ejecutarse como root"
        echo ""
        echo -e "${YELLOW}Ejecuta:${NC} ${CYAN}sudo bash $0${NC}"
        exit 1
    fi
}

detect_os() {
    print_step "Detectando sistema operativo"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
        OS_ID=$ID
        
        print_info "Sistema: $OS_NAME $OS_VERSION"
        
        case $OS_ID in
            debian|ubuntu)
                print_success "Sistema operativo compatible ✓"
                ;;
            *)
                print_warning "Sistema no oficialmente soportado: $OS_NAME"
                ;;
        esac
    fi
}

check_system_requirements() {
    if [ "$(check_status system_check)" == "completed" ]; then
        print_info "Verificación de sistema ya completada (omitiendo)"
        return 0
    fi
    
    print_header "VERIFICACIÓN DE REQUISITOS DEL SISTEMA"
    
    local all_ok=true
    
    # CPU
    local cpus=$(nproc)
    if [ "$cpus" -ge 2 ]; then
        print_success "CPUs: $cpus vCPUs ✓"
    else
        print_error "CPUs insuficientes: $cpus (mínimo 2)"
        all_ok=false
    fi
    
    # RAM
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local ram_gb=$((ram_mb / 1024))
    if [ "$ram_mb" -ge 3500 ]; then
        print_success "RAM: ${ram_gb} GB ✓"
    else
        print_error "RAM insuficiente: ${ram_gb} GB (mínimo 4 GB)"
        all_ok=false
    fi
    
    # Disco
    local disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_gb" -ge 20 ]; then
        print_success "Disco: ${disk_gb} GB disponibles ✓"
    else
        print_error "Espacio insuficiente: ${disk_gb} GB (mínimo 20 GB)"
        all_ok=false
    fi
    
    if ! $all_ok; then
        error_exit "El servidor no cumple con los requisitos mínimos"
    fi
    
    update_status "system_check" "completed"
}

# ============================================================================
# INSTALACIÓN DE COMPONENTES
# ============================================================================

install_docker() {
    if [ "$(check_status docker)" == "completed" ]; then
        print_info "Docker ya está instalado (omitiendo)"
        return 0
    fi
    
    print_header "INSTALACIÓN DE DOCKER"
    
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        print_success "Docker y Docker Compose ya están instalados"
        update_status "docker" "completed"
        return 0
    fi
    
    print_step "Instalando Docker Engine"
    
    # Remover versiones antiguas
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Instalar dependencias
    apt-get update -qq
    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Agregar clave GPG
    install -m 0755 -d /etc/apt/keyrings
    
    if [ "$OS_ID" == "debian" ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Instalar Docker
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Habilitar Docker
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker instalado correctamente"
    update_status "docker" "completed"
}

install_nginx() {
    if [ "$(check_status nginx)" == "completed" ]; then
        print_info "Nginx ya está instalado (omitiendo)"
        return 0
    fi
    
    print_header "INSTALACIÓN DE NGINX"
    
    if command -v nginx &> /dev/null; then
        print_success "Nginx ya está instalado"
        
        # Verificar que esté corriendo
        if ! systemctl is-active --quiet nginx; then
            systemctl start nginx
        fi
        
        update_status "nginx" "completed"
        return 0
    fi
    
    print_step "Instalando Nginx"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx
    
    systemctl enable nginx
    systemctl start nginx
    
    mkdir -p /var/www/certbot
    
    print_success "Nginx instalado correctamente"
    update_status "nginx" "completed"
}

install_certbot() {
    if [ "$(check_status certbot)" == "completed" ]; then
        print_info "Certbot ya está instalado (omitiendo)"
        return 0
    fi
    
    print_header "INSTALACIÓN DE CERTBOT"
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot ya está instalado"
        update_status "certbot" "completed"
        return 0
    fi
    
    print_step "Instalando Certbot"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx
    
    print_success "Certbot instalado correctamente"
    update_status "certbot" "completed"
}

# ============================================================================
# CREACIÓN DE ARCHIVOS
# ============================================================================

create_directory_structure() {
    if [ "$(check_status directories)" == "completed" ]; then
        print_info "Estructura de directorios ya existe (omitiendo)"
        return 0
    fi
    
    print_header "CREACIÓN DE ESTRUCTURA DE DIRECTORIOS"
    
    local dirs=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/data/postgres"
        "$INSTALL_DIR/data/redis"
        "$INSTALL_DIR/data/n8n"
        "$INSTALL_DIR/data/files"
        "$INSTALL_DIR/backups/postgres"
        "$INSTALL_DIR/backups/n8n-data"
        "$INSTALL_DIR/backups/config"
        "$INSTALL_DIR/scripts"
        "$LOG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    chmod -R 755 "$INSTALL_DIR"
    
    print_success "Estructura de directorios creada"
    update_status "directories" "completed"
}

create_env_file() {
    if [ "$(check_status env_file)" == "completed" ]; then
        print_info "Archivo .env ya existe (omitiendo)"
        return 0
    fi
    
    print_header "CREACIÓN DE ARCHIVO DE VARIABLES DE ENTORNO"
    
    cat > "$INSTALL_DIR/.env" << EOF
###############################################################################
# N8N PRODUCTION - CONFIGURACIÓN
# Generado: $(date)
# Versión: $SCRIPT_VERSION
###############################################################################

# Sistema
INSTALL_DIR=$INSTALL_DIR
DOMAIN=$DOMAIN

# PostgreSQL
POSTGRES_DB=n8n_production
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# n8n Security
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_BASIC_AUTH_USER=$N8N_ADMIN_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_ADMIN_PASSWORD
N8N_RUNNERS_AUTH_TOKEN=$N8N_RUNNERS_TOKEN

# Network
N8N_HOST=$DOMAIN
N8N_PROTOCOL=https
N8N_PORT=5678

# Timezone
GENERIC_TIMEZONE=America/Bogota
TZ=America/Bogota

# SSL
CERTBOT_EMAIL=$CERTBOT_EMAIL

# Docker Images
N8N_IMAGE=docker.n8n.io/n8nio/n8n:latest
POSTGRES_IMAGE=postgres:15-alpine
REDIS_IMAGE=redis:7-alpine
EOF
    
    chmod 600 "$INSTALL_DIR/.env"
    
    print_success "Archivo .env creado"
    update_status "env_file" "completed"
}

create_docker_compose() {
    if [ "$(check_status docker_compose)" == "completed" ]; then
        print_info "Docker Compose ya existe (omitiendo)"
        return 0
    fi
    
    print_header "CREACIÓN DE DOCKER COMPOSE"
    
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  postgres:
    image: ${POSTGRES_IMAGE:-postgres:15-alpine}
    container_name: n8n_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${POSTGRES_USER}']
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2560M
        reservations:
          cpus: '0.5'
          memory: 1536M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    image: ${REDIS_IMAGE:-redis:7-alpine}
    container_name: n8n_redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 768mb --maxmemory-policy allkeys-lru
    volumes:
      - ./data/redis:/data
    networks:
      - n8n_network
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1024M
        reservations:
          cpus: '0.25'
          memory: 512M
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"

  n8n:
    image: ${N8N_IMAGE:-docker.n8n.io/n8nio/n8n:latest}
    container_name: n8n_app
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
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
      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}
      TZ: ${TZ}
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 720
      N8N_METRICS: "true"
      NODE_ENV: production
      NODE_OPTIONS: "--max-old-space-size=3072"
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
          cpus: '2.5'
          memory: 4096M
        reservations:
          cpus: '1.5'
          memory: 2560M
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "5"

networks:
  n8n_network:
    driver: bridge
EOF
    
    print_success "Docker Compose creado"
    update_status "docker_compose" "completed"
}

configure_nginx_site() {
    if [ "$(check_status nginx_config)" == "completed" ]; then
        print_info "Configuración de Nginx ya existe (verificando)"
        
        if nginx -t 2>&1 | grep -q "syntax is ok"; then
            print_success "Configuración de Nginx OK"
            return 0
        else
            print_warning "Configuración de Nginx tiene errores, recreando..."
        fi
    fi
    
    print_header "CONFIGURACIÓN DE NGINX"
    
    # Crear configuración
    cat > "/etc/nginx/sites-available/$DOMAIN" << EOFNGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

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
EOFNGINX
    
    # Habilitar sitio
    ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
    
    # Deshabilitar default
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Verificar configuración
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        systemctl reload nginx
        print_success "Configuración de Nginx OK"
        update_status "nginx_config" "completed"
    else
        print_error "Error en configuración de Nginx"
        nginx -t
        return 1
    fi
}

generate_ssl_certificate() {
    if [ "$(check_status ssl_cert)" == "completed" ]; then
        print_info "Certificado SSL ya existe (verificando validez)"
        
        if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
            local days_left=$(( ($(date -d "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" | cut -d= -f2)" +%s 2>/dev/null || echo "0") - $(date +%s)) / 86400 ))
            
            if [ $days_left -gt 30 ]; then
                print_success "Certificado válido ($days_left días restantes)"
                return 0
            else
                print_warning "Certificado próximo a expirar ($days_left días), renovando..."
            fi
        fi
    fi
    
    print_header "GENERACIÓN DE CERTIFICADO SSL"
    
    # Asegurar que Nginx esté corriendo
    systemctl reload nginx
    sleep 2
    
    # Generar certificado
    certbot certonly \
        --nginx \
        --non-interactive \
        --agree-tos \
        --email "$CERTBOT_EMAIL" \
        --domains "$DOMAIN" \
        --rsa-key-size 4096 \
        2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        print_success "Certificado SSL generado"
        
        # Actualizar configuración de Nginx con HTTPS
        cat > "/etc/nginx/sites-available/$DOMAIN" << EOFSSL
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
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
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    
    add_header Strict-Transport-Security "max-age=31536000" always;

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
EOFSSL
        
        nginx -t && systemctl reload nginx
        
        # Configurar renovación automática
        if systemctl list-unit-files | grep -q "certbot.timer"; then
            systemctl enable certbot.timer
            systemctl start certbot.timer
        fi
        
        print_success "Certificado SSL configurado con HTTPS"
        update_status "ssl_cert" "completed"
    else
        print_warning "No se pudo generar certificado SSL (continuando sin HTTPS)"
        return 1
    fi
}

start_docker_services() {
    if [ "$(check_status docker_services)" == "completed" ]; then
        print_info "Servicios Docker ya están corriendo (verificando)"
        
        cd "$INSTALL_DIR"
        local running=$(docker compose ps --format json 2>/dev/null | jq -r '.State' | grep -c "running" || echo "0")
        
        if [ "$running" -eq 3 ]; then
            print_success "Todos los servicios están corriendo"
            return 0
        else
            print_warning "Algunos servicios no están corriendo, reiniciando..."
        fi
    fi
    
    print_header "INICIO DE SERVICIOS DOCKER"
    
    cd "$INSTALL_DIR"
    
    print_step "Descargando imágenes"
    docker compose pull 2>&1 | tee -a "$LOG_FILE"
    
    print_step "Iniciando contenedores"
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    print_step "Esperando servicios"
    sleep 20
    
    docker compose ps
    
    print_success "Servicios Docker iniciados"
    update_status "docker_services" "completed"
}

create_maintenance_scripts() {
    if [ "$(check_status maintenance)" == "completed" ]; then
        print_info "Scripts de mantenimiento ya existen (omitiendo)"
        return 0
    fi
    
    print_header "CREACIÓN DE SCRIPTS DE MANTENIMIENTO"
    
    # Script de backup
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOFBACKUP'
#!/bin/bash
BACKUP_DIR="/opt/n8n-production/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== Backup n8n - $DATE ==="

docker exec n8n_postgres pg_dump -U n8n_user n8n_production | gzip > "$BACKUP_DIR/postgres/n8n_db_$DATE.sql.gz"
tar -czf "$BACKUP_DIR/n8n-data/n8n_data_$DATE.tar.gz" -C /opt/n8n-production/data/n8n . 2>/dev/null

find "$BACKUP_DIR/postgres" -name "*.sql.gz" -mtime +7 -delete
find "$BACKUP_DIR/n8n-data" -name "*.tar.gz" -mtime +7 -delete

echo "✓ Backup completado"
EOFBACKUP
    
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    
    # Configurar cron
    (crontab -l 2>/dev/null | grep -v "n8n backup"; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh >> /var/log/n8n-backup.log 2>&1") | crontab -
    
    # Crear alias
    cat > /etc/profile.d/n8n-aliases.sh << 'EOFALIAS'
alias n8n-logs='docker logs -f n8n_app'
alias n8n-status='cd /opt/n8n-production && docker compose ps'
alias n8n-restart='cd /opt/n8n-production && docker compose restart n8n'
alias n8n-backup='sudo /opt/n8n-production/scripts/backup.sh'
EOFALIAS
    
    chmod +x /etc/profile.d/n8n-aliases.sh
    
    print_success "Scripts de mantenimiento creados"
    update_status "maintenance" "completed"
}

save_final_credentials() {
    print_step "Guardando credenciales finales"
    
    cat > "$INSTALL_DIR/CREDENCIALES.txt" << EOFCRED
╔══════════════════════════════════════════════════════════════════════╗
║                  CREDENCIALES N8N - PRODUCCIÓN                       ║
╚══════════════════════════════════════════════════════════════════════╝

Fecha: $(date)
Versión: $SCRIPT_VERSION

═══════════════════════════════════════════════════════════════════════
 ACCESO WEB
═══════════════════════════════════════════════════════════════════════

URL:      https://$DOMAIN
Usuario:  $N8N_ADMIN_USER
Password: $N8N_ADMIN_PASSWORD

═══════════════════════════════════════════════════════════════════════
 BASE DE DATOS
═══════════════════════════════════════════════════════════════════════

Database: n8n_production
User:     n8n_user
Password: $POSTGRES_PASSWORD

═══════════════════════════════════════════════════════════════════════
 CLAVES DE ENCRIPTACIÓN (¡NO PERDER!)
═══════════════════════════════════════════════════════════════════════

N8N_ENCRYPTION_KEY: $N8N_ENCRYPTION_KEY

═══════════════════════════════════════════════════════════════════════
 ARCHIVOS
═══════════════════════════════════════════════════════════════════════

Instalación: $INSTALL_DIR
Logs:        $LOG_DIR

═══════════════════════════════════════════════════════════════════════
⚠️  MANTÉN ESTE ARCHIVO SEGURO
═══════════════════════════════════════════════════════════════════════
EOFCRED
    
    chmod 600 "$INSTALL_DIR/CREDENCIALES.txt"
    print_success "Credenciales guardadas en: $INSTALL_DIR/CREDENCIALES.txt"
}

show_final_summary() {
    print_header "¡INSTALACIÓN COMPLETADA!"
    
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  ✅ N8N ESTÁ LISTO PARA USAR                                         ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}═══ ACCESO ═══${NC}"
    echo -e "  ${WHITE}URL:${NC}      ${GREEN}https://$DOMAIN${NC}"
    echo -e "  ${WHITE}Usuario:${NC}  ${CYAN}$N8N_ADMIN_USER${NC}"
    echo -e "  ${WHITE}Password:${NC} ${YELLOW}[Ver archivo de credenciales]${NC}"
    echo ""
    
    echo -e "${CYAN}═══ COMANDOS ÚTILES ═══${NC}"
    echo -e "  ${YELLOW}n8n-logs${NC}     Ver logs"
    echo -e "  ${YELLOW}n8n-status${NC}   Ver estado"
    echo -e "  ${YELLOW}n8n-restart${NC}  Reiniciar"
    echo -e "  ${YELLOW}n8n-backup${NC}   Backup manual"
    echo ""
    
    echo -e "${CYAN}═══ ARCHIVOS ═══${NC}"
    echo -e "  ${WHITE}Credenciales:${NC} ${YELLOW}$INSTALL_DIR/CREDENCIALES.txt${NC}"
    echo -e "  ${WHITE}Logs:${NC}         $LOG_FILE"
    echo ""
    
    print_success "¡Instalación completada exitosamente!"
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================

main() {
    # Crear directorio de logs
    mkdir -p "$LOG_DIR"
    
    # Banner
    print_banner
    
    log "════════════════════════════════════════════════════════════════════════"
    log "N8N PRODUCTION INSTALLER v$SCRIPT_VERSION"
    log "Inicio: $(date)"
    log "════════════════════════════════════════════════════════════════════════"
    
    # Verificaciones básicas
    check_root
    detect_os
    
    # Detectar instalación previa
    detect_previous_installation
    
    # Solicitar TODAS las credenciales al inicio
    collect_all_credentials
    
    # Verificar sistema
    check_system_requirements
    
    # Instalar componentes
    install_docker
    install_nginx
    install_certbot
    
    # Crear estructura
    create_directory_structure
    create_env_file
    create_docker_compose
    
    # Configurar servicios
    configure_nginx_site
    generate_ssl_certificate
    
    # Iniciar servicios
    start_docker_services
    
    # Mantenimiento
    create_maintenance_scripts
    
    # Guardar credenciales
    save_final_credentials
    
    # Limpiar archivos temporales
    cleanup_temp_files
    
    # Marcar instalación como completa
    touch "$INSTALL_DIR/.installation_complete"
    
    # Mostrar resumen
    show_final_summary
    
    log "════════════════════════════════════════════════════════════════════════"
    log "INSTALACIÓN COMPLETADA EXITOSAMENTE"
    log "Fin: $(date)"
    log "════════════════════════════════════════════════════════════════════════"
}

# Ejecutar
main "$@"
