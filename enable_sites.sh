#!/bin/bash

###############################################################################
# Script para gestionar Docker containers y configuración de Nginx
# Muestra información de Docker, sitios Nginx y permite configurar SSL
###############################################################################

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Separador visual
SEPARATOR="════════════════════════════════════════════════════════════"

# Variables globales
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_DIR="/etc/nginx/conf.d"
DOCKER_CONTAINERS=()
NGINX_SITES=()
SELECTED_CONTAINERS=()
DELETE_SITES_LIST=()
RENAME_SITES_LIST=()
CHANGE_TYPE_SITES_LIST=()
OPERATION_COUNT=0

# Función para limpiar pantalla cada 3 operaciones
increment_operation() {
    ((OPERATION_COUNT++))
    if [ $((OPERATION_COUNT % 3)) -eq 0 ]; then
        clear
        echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}"
        echo -e "${BLUE}${BOLD}     ENABLE SITES - Gestión de Sitios Nginx${NC}"
        echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    fi
}

###############################################################################
# FUNCIONES DE VALIDACIÓN
###############################################################################

check_dependencies() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           VALIDACIÓN DE DEPENDENCIAS${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local missing_deps=()
    
    # Verificar Docker
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker está instalado: $(docker --version)"
    else
        echo -e "${RED}✗${NC} Docker NO está instalado"
        missing_deps+=("docker")
    fi
    
    # Verificar Nginx
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}✓${NC} Nginx está instalado: $(nginx -v 2>&1)"
    else
        echo -e "${RED}✗${NC} Nginx NO está instalado"
        missing_deps+=("nginx")
    fi
    
    # Verificar Certbot
    if command -v certbot &> /dev/null; then
        echo -e "${GREEN}✓${NC} Certbot está instalado: $(certbot --version 2>&1 | head -n1)"
    else
        echo -e "${RED}✗${NC} Certbot NO está instalado"
        missing_deps+=("certbot")
    fi
    
    echo ""
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Dependencias faltantes: ${missing_deps[*]}${NC}"
        read -p "¿Deseas instalar las dependencias faltantes? (s/n): " install_choice
        
        if [[ "$install_choice" =~ ^[Ss]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            echo -e "${RED}No se pueden continuar sin las dependencias necesarias.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}${BOLD}Todas las dependencias están instaladas.${NC}\n"
    fi
}

install_dependencies() {
    echo -e "\n${CYAN}Instalando dependencias...${NC}\n"
    
    # Detectar sistema operativo
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo apt-get update
        
        for dep in "$@"; do
            case $dep in
                docker)
                    echo -e "${CYAN}Instalando Docker...${NC}"
                    sudo apt-get install -y docker.io docker-compose
                    sudo systemctl enable docker
                    sudo systemctl start docker
                    ;;
                nginx)
                    echo -e "${CYAN}Instalando Nginx...${NC}"
                    sudo apt-get install -y nginx
                    sudo systemctl enable nginx
                    sudo systemctl start nginx
                    ;;
                certbot)
                    echo -e "${CYAN}Instalando Certbot...${NC}"
                    sudo apt-get install -y certbot python3-certbot-nginx
                    ;;
            esac
        done
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS
        for dep in "$@"; do
            case $dep in
                docker)
                    echo -e "${CYAN}Instalando Docker...${NC}"
                    sudo yum install -y docker docker-compose
                    sudo systemctl enable docker
                    sudo systemctl start docker
                    ;;
                nginx)
                    echo -e "${CYAN}Instalando Nginx...${NC}"
                    sudo yum install -y nginx
                    sudo systemctl enable nginx
                    sudo systemctl start nginx
                    ;;
                certbot)
                    echo -e "${CYAN}Instalando Certbot...${NC}"
                    sudo yum install -y certbot python3-certbot-nginx
                    ;;
            esac
        done
    else
        echo -e "${RED}No se pudo detectar el sistema operativo. Instala las dependencias manualmente.${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}Dependencias instaladas correctamente.${NC}\n"
}

###############################################################################
# FUNCIONES DE INFORMACIÓN
###############################################################################

get_docker_containers() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           CONTENEDORES DOCKER EN EJECUCIÓN${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    if ! docker ps &> /dev/null; then
        echo -e "${RED}Error: No se puede acceder a Docker. Verifica que Docker esté corriendo y tengas permisos.${NC}"
        exit 1
    fi
    
    local containers=$(docker ps --format "{{.Names}}|{{.Ports}}|{{.ID}}|{{.Status}}")
    
    if [ -z "$containers" ]; then
        echo -e "${YELLOW}No hay contenedores Docker en ejecución.${NC}\n"
        return
    fi
    
    local index=1
    while IFS='|' read -r name ports id status; do
        echo -e "${CYAN}${BOLD}Contenedor #$index:${NC}"
        echo -e "  ${GREEN}Nombre:${NC} $name"
        echo -e "  ${GREEN}ID:${NC} $id"
        echo -e "  ${GREEN}Puertos:${NC} $ports"
        echo -e "  ${GREEN}Estado:${NC} $status"
        
        # Obtener tiempo de ejecución
        local uptime=$(docker inspect "$name" --format='{{.State.StartedAt}}' 2>/dev/null)
        if [ -n "$uptime" ]; then
            # Intentar parsear la fecha (formato ISO 8601)
            local start_time=""
            # Linux: date -d
            if date -d "$uptime" +%s &>/dev/null; then
                start_time=$(date -d "$uptime" +%s 2>/dev/null)
            # macOS: date -j -f
            elif date -j -f "%Y-%m-%dT%H:%M:%S" "${uptime%.*}" +%s &>/dev/null 2>&1; then
                start_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${uptime%.*}" +%s 2>/dev/null)
            # Alternativa: usar docker stats o docker ps
            else
                # Usar docker ps para obtener el tiempo de ejecución
                local status_uptime=$(docker ps --filter "name=$name" --format "{{.Status}}" 2>/dev/null | grep -oE 'Up [0-9]+' | grep -oE '[0-9]+' || echo "")
                if [ -n "$status_uptime" ]; then
                    echo -e "  ${GREEN}Tiempo corriendo:${NC} ${status_uptime} (desde status)"
                fi
            fi
            
            if [ -n "$start_time" ] && [[ "$start_time" =~ ^[0-9]+$ ]]; then
                local current_time=$(date +%s)
                local diff=$((current_time - start_time))
                
                if [ $diff -gt 0 ]; then
                    local days=$((diff / 86400))
                    local hours=$(((diff % 86400) / 3600))
                    local minutes=$(((diff % 3600) / 60))
                    
                    if [ $days -gt 0 ]; then
                        echo -e "  ${GREEN}Tiempo corriendo:${NC} ${days}d ${hours}h ${minutes}m"
                    elif [ $hours -gt 0 ]; then
                        echo -e "  ${GREEN}Tiempo corriendo:${NC} ${hours}h ${minutes}m"
                    else
                        echo -e "  ${GREEN}Tiempo corriendo:${NC} ${minutes}m"
                    fi
                fi
            fi
        fi
        
        # Extraer puertos expuestos (mejorado)
        local exposed_ports=""
        # Buscar puertos en formato 0.0.0.0:8080->3000/tcp o 127.0.0.1:8080->3000/tcp
        if echo "$ports" | grep -qE '->'; then
            exposed_ports=$(echo "$ports" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+->' | grep -oE '[0-9]+:' | grep -oE '[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')
        fi
        # Si no se encontró, buscar formato alternativo
        if [ -z "$exposed_ports" ]; then
            exposed_ports=$(echo "$ports" | grep -oE ':[0-9]+->' | grep -oE '[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')
        fi
        # Si aún no se encontró, intentar con docker inspect
        if [ -z "$exposed_ports" ]; then
            exposed_ports=$(docker inspect "$name" --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}{{end}}{{end}}' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        fi
        
        if [ -n "$exposed_ports" ] && [ "$exposed_ports" != "" ]; then
            echo -e "  ${GREEN}Puertos expuestos:${NC} $exposed_ports"
        else
            echo -e "  ${YELLOW}Sin puertos expuestos al host${NC}"
        fi
        
        # Mostrar últimos 5 logs
        echo -e "  ${CYAN}Últimos 5 logs:${NC}"
        local logs=$(docker logs --tail 5 --timestamps "$name" 2>&1)
        if [ -n "$logs" ] && [ "$logs" != "" ]; then
            # Limitar el ancho de los logs para mejor visualización
            echo "$logs" | while IFS= read -r line; do
                # Truncar líneas muy largas
                if [ ${#line} -gt 100 ]; then
                    echo -e "    ${YELLOW}${line:0:97}...${NC}"
                else
                    echo -e "    ${YELLOW}$line${NC}"
                fi
            done
        else
            echo -e "    ${YELLOW}(Sin logs disponibles)${NC}"
        fi
        
        DOCKER_CONTAINERS+=("$name|$ports|$id|$exposed_ports")
        echo ""
        ((index++))
    done <<< "$containers"
}

get_nginx_sites() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SITIOS NGINX CONFIGURADOS${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    # Buscar en sites-available (si existe)
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        echo -e "${CYAN}Sitios disponibles (sites-available):${NC}"
        for site in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site" ] && [[ ! "$site" =~ default$ ]]; then
                local site_name=$(basename "$site")
                local enabled=""
                if [ -L "$NGINX_SITES_ENABLED/$site_name" ]; then
                    enabled="${GREEN}[ACTIVO]${NC}"
                else
                    enabled="${RED}[INACTIVO]${NC}"
                fi
                echo -e "  $site_name $enabled"
                NGINX_SITES+=("$site_name|$enabled")
            fi
        done
        echo ""
    fi
    
    # Buscar en conf.d (si existe) - todos los archivos, no solo .conf
    if [ -d "$NGINX_CONF_DIR" ]; then
        echo -e "${CYAN}Sitios en conf.d:${NC}"
        for site in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site" ]; then
                local site_name=$(basename "$site")
                echo -e "  $site_name ${GREEN}[ACTIVO]${NC}"
                NGINX_SITES+=("$site_name|ACTIVO")
            fi
        done
        echo ""
    fi
    
    if [ ${#NGINX_SITES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios configurados en Nginx.${NC}\n"
    fi
}

match_containers_to_sites() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           CORRESPONDENCIA DOCKER ↔ NGINX${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local containers_with_sites=()
    local containers_without_sites=()
    
    for container_info in "${DOCKER_CONTAINERS[@]}"; do
        IFS='|' read -r name ports id exposed_ports <<< "$container_info"
        local found=false
        local matched_site=""
        local site_status=""
        
        # Buscar si hay un sitio de nginx que apunte a este contenedor
        for site_info in "${NGINX_SITES[@]}"; do
            IFS='|' read -r site_name status <<< "$site_info"
            local site_file=""
            
            if [ -d "$NGINX_SITES_AVAILABLE" ] && [ -f "$NGINX_SITES_AVAILABLE/$site_name" ]; then
                site_file="$NGINX_SITES_AVAILABLE/$site_name"
            elif [ -d "$NGINX_CONF_DIR" ] && [ -f "$NGINX_CONF_DIR/$site_name" ]; then
                site_file="$NGINX_CONF_DIR/$site_name"
            fi
            
            if [ -n "$site_file" ] && [ -f "$site_file" ]; then
                # Buscar referencias al nombre del contenedor o puertos
                if grep -q "$name" "$site_file" || grep -q "localhost:$exposed_ports" "$site_file" 2>/dev/null; then
                    found=true
                    matched_site="$site_name"
                    if [[ "$status" =~ ACTIVO ]]; then
                        site_status="${GREEN}ACTIVO${NC}"
                    else
                        site_status="${RED}INACTIVO${NC}"
                    fi
                    break
                fi
            fi
        done
        
        if [ "$found" = true ]; then
            containers_with_sites+=("$name|$matched_site|$site_status")
            echo -e "${GREEN}✓${NC} ${BOLD}$name${NC} → Sitio: $matched_site ($site_status)"
        else
            containers_without_sites+=("$name|$exposed_ports")
            if [ -z "$exposed_ports" ] || [ "$exposed_ports" = "" ]; then
                echo -e "${RED}✗${NC} ${BOLD}$name${NC} → Sin sitio configurado | ${YELLOW}Sin puertos expuestos${NC}"
            else
                echo -e "${YELLOW}⚠${NC} ${BOLD}$name${NC} → Sin sitio configurado | Puertos: $exposed_ports"
            fi
        fi
    done
    
    echo ""
    echo -e "${CYAN}Resumen:${NC}"
    echo -e "  ${GREEN}Contenedores con sitio:${NC} ${#containers_with_sites[@]}"
    echo -e "  ${YELLOW}Contenedores sin sitio:${NC} ${#containers_without_sites[@]}"
    echo ""
    
    # Guardar contenedores sin sitio para la selección
    SELECTED_CONTAINERS=("${containers_without_sites[@]}")
}

###############################################################################
# FUNCIONES DE CONFIGURACIÓN
###############################################################################

select_containers() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SELECCIÓN DE CONTENEDORES${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    if [ ${#SELECTED_CONTAINERS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No hay contenedores sin sitio configurado.${NC}\n"
        return 1
    fi
    
    echo -e "${CYAN}¿Qué deseas hacer?${NC}"
    echo -e "  1) Configurar todos los contenedores sin sitio"
    echo -e "  2) Seleccionar contenedores específicos"
    echo -e "  3) Cancelar"
    echo ""
    read -p "Opción (1-3): " option
    
    case $option in
        1)
            echo -e "\n${GREEN}Se configurarán todos los contenedores sin sitio.${NC}\n"
            return 0
            ;;
        2)
            echo -e "\n${CYAN}Contenedores disponibles:${NC}\n"
            local index=1
            local selected_indices=()
            
            for container_info in "${SELECTED_CONTAINERS[@]}"; do
                IFS='|' read -r name exposed_ports <<< "$container_info"
                echo -e "  $index) $name (Puertos: ${exposed_ports:-N/A})"
                ((index++))
            done
            
            echo ""
            read -p "Ingresa los números de los contenedores separados por comas (ej: 1,3,5): " selection
            
            # Procesar selección
            IFS=',' read -ra indices <<< "$selection"
            local temp_selected=()
            
            for idx in "${indices[@]}"; do
                idx=$(echo "$idx" | tr -d ' ')
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#SELECTED_CONTAINERS[@]} ]; then
                    temp_selected+=("${SELECTED_CONTAINERS[$((idx-1))]}")
                fi
            done
            
            if [ ${#temp_selected[@]} -gt 0 ]; then
                SELECTED_CONTAINERS=("${temp_selected[@]}")
                echo -e "\n${GREEN}Contenedores seleccionados:${NC}"
                for container_info in "${SELECTED_CONTAINERS[@]}"; do
                    IFS='|' read -r name exposed_ports <<< "$container_info"
                    echo -e "  - $name"
                done
                echo ""
                return 0
            else
                echo -e "${RED}Selección inválida.${NC}\n"
                return 1
            fi
            ;;
        3)
            echo -e "\n${YELLOW}Operación cancelada.${NC}\n"
            return 1
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}\n"
            return 1
            ;;
    esac
}

get_container_info() {
    local container_name=$1
    for container_info in "${DOCKER_CONTAINERS[@]}"; do
        IFS='|' read -r name ports id exposed_ports <<< "$container_info"
        if [ "$name" = "$container_name" ]; then
            # Si hay múltiples puertos, tomar el primero
            if [ -n "$exposed_ports" ] && [ "$exposed_ports" != "" ]; then
                echo "$exposed_ports" | cut -d',' -f1
            else
                # Intentar obtener desde docker inspect como fallback
                docker inspect "$container_name" --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}{{break}}{{end}}{{end}}' 2>/dev/null
            fi
            return
        fi
    done
    echo ""
}

check_site_exists() {
    local domain=$1
    
    # Verificar con nombre estándar (solo dominio, sin .conf)
    if [ -d "$NGINX_SITES_AVAILABLE" ] && [ -f "$NGINX_SITES_AVAILABLE/$domain" ]; then
        echo "$NGINX_SITES_AVAILABLE/$domain"
        return 0
    fi
    
    if [ -d "$NGINX_CONF_DIR" ] && [ -f "$NGINX_CONF_DIR/$domain" ]; then
        echo "$NGINX_CONF_DIR/$domain"
        return 0
    fi
    
    # Verificar también con .conf (por compatibilidad)
    local site_name="${domain}.conf"
    if [ -d "$NGINX_SITES_AVAILABLE" ] && [ -f "$NGINX_SITES_AVAILABLE/$site_name" ]; then
        echo "$NGINX_SITES_AVAILABLE/$site_name"
        return 0
    fi
    
    if [ -d "$NGINX_CONF_DIR" ] && [ -f "$NGINX_CONF_DIR/$site_name" ]; then
        echo "$NGINX_CONF_DIR/$site_name"
        return 0
    fi
    
    # Buscar por dominio en todos los archivos
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && grep -qE "server_name\s+.*$domain" "$site_file" 2>/dev/null; then
                echo "$site_file"
                return 0
            fi
        done
    fi
    
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ] && grep -qE "server_name\s+.*$domain" "$site_file" 2>/dev/null; then
                echo "$site_file"
                return 0
            fi
        done
    fi
    
        return 1
}

select_site_type() {
    # Mostrar opciones
    echo -e "\n${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  SELECCIÓN DE TIPO DE SITIO${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}\n"
    echo -e "${CYAN}¿Qué tipo de sitio deseas configurar?${NC}\n"
    
    echo -e "${GREEN}1) API/BACKEND${NC}"
    echo -e "   ${YELLOW}→${NC} Configuración estándar para APIs REST, GraphQL, microservicios"
    echo -e "   ${YELLOW}→${NC} Proxy reverso básico con soporte WebSockets"
    echo -e "   ${YELLOW}→${NC} Timeouts: 60 segundos"
    echo -e "   ${YELLOW}→${NC} Ideal para: Backend APIs, servicios, microservicios\n"
    
    echo -e "${GREEN}2) WEB NEXT.JS${NC}"
    echo -e "   ${YELLOW}→${NC} Configuración optimizada para aplicaciones Next.js/React"
    echo -e "   ${YELLOW}→${NC} Gzip compression, caché inteligente, soporte ISR"
    echo -e "   ${YELLOW}→${NC} Timeouts extendidos: 120 segundos (para SSR)"
    echo -e "   ${YELLOW}→${NC} Buffers aumentados para páginas grandes"
    echo -e "   ${YELLOW}→${NC} Ideal para: Next.js, React SSR, aplicaciones web modernas\n"
    
    echo -e "${CYAN}3) Por defecto (API)${NC}\n"
    
    read -p "Opción (1-3) [Por defecto: 1]: " site_type_choice
    
    # Limpiar espacios y convertir a número
    site_type_choice=$(echo "$site_type_choice" | tr -d ' ')
    
    # Retornar el valor sin mensajes adicionales
    case "$site_type_choice" in
        2)
            echo "nextjs"
            ;;
        1|3|"")
            echo "api"
            ;;
        *)
            # Si es algo inválido, usar por defecto
            echo -e "${YELLOW}Opción inválida, usando API por defecto${NC}"
            echo "api"
            ;;
    esac
}

get_nextjs_config() {
    local domain=$1
    
    # Mostrar mensajes en stderr para que no interfieran con la captura del valor
    echo -e "\n${CYAN}${BOLD}Configuración adicional para Next.js:${NC}\n" >&2
    
    # Preguntar por directorio público
    read -p "¿Ruta del directorio público? [Por defecto: /public]: " public_dir >&2
    public_dir="${public_dir:-/public}"
    
    # Preguntar por caché de assets estáticos
    echo "" >&2
    read -p "¿Habilitar caché de assets estáticos? (s/n) [Por defecto: s]: " enable_cache >&2
    enable_cache="${enable_cache:-s}"
    
    # Preguntar por tamaño máximo de upload
    echo "" >&2
    read -p "¿Tamaño máximo de upload en MB? [Por defecto: 10]: " max_upload >&2
    max_upload="${max_upload:-10}"
    
    # Validar que sea un número válido
    if ! [[ "$max_upload" =~ ^[0-9]+$ ]] || [ "$max_upload" -le 0 ]; then
        echo -e "${YELLOW}Valor inválido, usando 10MB por defecto${NC}" >&2
        max_upload="10"
    fi
    
    # Preguntar por ISR (Incremental Static Regeneration)
    echo "" >&2
    read -p "¿Habilitar soporte para ISR (Incremental Static Regeneration)? (s/n) [Por defecto: s]: " enable_isr >&2
    enable_isr="${enable_isr:-s}"
    
    # Retornar solo los valores separados por |
    echo "$public_dir|$enable_cache|$max_upload|$enable_isr"
}

create_api_config() {
    local site_path=$1
    local domain=$2
    local port=$3
    
    sudo tee "$site_path" > /dev/null << EOF
# Configuración para API/Backend
# Tipo: API
# Dominio: $domain
# Puerto: $port

server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    location / {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # Certificados SSL (serán configurados por Certbot)
    # ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    location / {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
}

create_nextjs_config() {
    local site_path=$1
    local domain=$2
    local port=$3
    local public_dir=$4
    local enable_cache=$5
    local max_upload=$6
    local enable_isr=$7
    
    # Validar y sanitizar max_upload
    if [ -z "$max_upload" ] || ! [[ "$max_upload" =~ ^[0-9]+$ ]] || [ "$max_upload" -le 0 ]; then
        echo -e "${YELLOW}⚠ Valor inválido para max_upload ($max_upload), usando 10MB por defecto${NC}" >&2
        max_upload="10"
    fi
    
    local cache_config=""
    local isr_config=""
    
    if [[ "$enable_cache" =~ ^[Ss]$ ]]; then
        cache_config="
    # Caché para assets estáticos de Next.js
    location /_next/static {
        proxy_pass http://localhost:$port;
        proxy_cache_valid 60m;
        add_header X-Cache-Status \$upstream_cache_status;
        add_header Cache-Control \"public, max-age=31536000, immutable\";
    }
    
    # Caché para imágenes optimizadas de Next.js
    location /_next/image {
        proxy_pass http://localhost:$port;
        proxy_cache_valid 60m;
        add_header X-Cache-Status \$upstream_cache_status;
    }
    
    # Archivos estáticos públicos
    location /static {
        proxy_pass http://localhost:$port;
        add_header Cache-Control \"public, max-age=31536000, immutable\";
    }"
    fi
    
    if [[ "$enable_isr" =~ ^[Ss]$ ]]; then
        isr_config="
    # Soporte para ISR (Incremental Static Regeneration)
    proxy_cache_revalidate on;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    proxy_cache_background_update on;
    proxy_cache_lock on;"
    fi
    
    sudo tee "$site_path" > /dev/null << EOF
# Configuración para Next.js Web App
# Tipo: Next.js
# Dominio: $domain
# Puerto: $port
# Directorio público: $public_dir

server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    # Tamaño máximo de upload
    client_max_body_size ${max_upload}M;
    
    # Gzip compression para mejor rendimiento
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
    
    location / {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Headers para Next.js
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Timeouts extendidos para SSR
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        
        # Buffer sizes para páginas grandes
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
$cache_config
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # Certificados SSL (serán configurados por Certbot)
    # ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # Tamaño máximo de upload
    client_max_body_size ${max_upload}M;
    
    # Gzip compression para mejor rendimiento
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
$isr_config

    location / {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Headers para Next.js
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Timeouts extendidos para SSR
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        
        # Buffer sizes para páginas grandes
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
$cache_config
}
EOF
}

create_nginx_config() {
    local container_name=$1
    local domain=$2
    local port=$3
    local site_type=${4:-""}
    
    # Verificar si el sitio ya existe
    local existing_site=$(check_site_exists "$domain")
    if [ -n "$existing_site" ]; then
        echo -e "${YELLOW}⚠ El sitio para el dominio '$domain' ya existe:${NC}"
        echo -e "${CYAN}  Archivo: $existing_site${NC}"
        echo -e "${YELLOW}  No se creará una nueva configuración.${NC}"
        return 2  # Código especial para indicar que ya existe
    fi
    
    # Seleccionar tipo de sitio si no se proporcionó
    if [ -z "$site_type" ]; then
        # Mostrar opciones primero
        echo -e "\n${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}${BOLD}  SELECCIÓN DE TIPO DE SITIO${NC}"
        echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}\n"
        echo -e "${CYAN}¿Qué tipo de sitio deseas configurar?${NC}\n"
        
        echo -e "${GREEN}1) API/BACKEND${NC}"
        echo -e "   ${YELLOW}→${NC} Configuración estándar para APIs REST, GraphQL, microservicios"
        echo -e "   ${YELLOW}→${NC} Proxy reverso básico con soporte WebSockets"
        echo -e "   ${YELLOW}→${NC} Timeouts: 60 segundos"
        echo -e "   ${YELLOW}→${NC} Ideal para: Backend APIs, servicios, microservicios\n"
        
        echo -e "${GREEN}2) WEB NEXT.JS${NC}"
        echo -e "   ${YELLOW}→${NC} Configuración optimizada para aplicaciones Next.js/React"
        echo -e "   ${YELLOW}→${NC} Gzip compression, caché inteligente, soporte ISR"
        echo -e "   ${YELLOW}→${NC} Timeouts extendidos: 120 segundos (para SSR)"
        echo -e "   ${YELLOW}→${NC} Buffers aumentados para páginas grandes"
        echo -e "   ${YELLOW}→${NC} Ideal para: Next.js, React SSR, aplicaciones web modernas\n"
        
        echo -e "${CYAN}3) Por defecto (API)${NC}\n"
        
        read -p "Opción (1-3) [Por defecto: 1]: " site_type_choice
        
        # Limpiar espacios
        site_type_choice=$(echo "$site_type_choice" | tr -d ' ')
        
        # Determinar tipo según selección
        case "$site_type_choice" in
            2)
                site_type="nextjs"
                echo -e "${GREEN}✓ Tipo seleccionado: Web Next.js${NC}"
                ;;
            1|3|"")
                site_type="api"
                echo -e "${GREEN}✓ Tipo seleccionado: API/Backend${NC}"
                ;;
            *)
                site_type="api"
                echo -e "${YELLOW}Opción inválida, usando API por defecto${NC}"
                ;;
        esac
        echo ""
    fi
    
    # Usar el dominio como nombre del archivo (formato estándar: solo dominio, sin .conf)
    local site_name="$domain"
    local site_path=""
    
    # Determinar dónde crear el archivo
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        site_path="$NGINX_SITES_AVAILABLE/$site_name"
    elif [ -d "$NGINX_CONF_DIR" ]; then
        site_path="$NGINX_CONF_DIR/$site_name"
    else
        echo -e "${RED}Error: No se encontró directorio de configuración de Nginx.${NC}"
        return 1
    fi
    
    # Crear configuración según el tipo
    case $site_type in
        nextjs)
            echo -e "\n${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
            echo -e "${BLUE}${BOLD}  CONFIGURANDO SITIO WEB NEXT.JS${NC}"
            echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
            echo -e "${CYAN}Tipo:${NC} Web Application (Next.js/React)"
            echo -e "${CYAN}Dominio:${NC} $domain"
            echo -e "${CYAN}Puerto:${NC} $port"
            echo ""
            local nextjs_options=$(get_nextjs_config "$domain")
            
            # Limpiar y leer los valores
            nextjs_options=$(echo "$nextjs_options" | tr -d '\n\r')
            IFS='|' read -r public_dir enable_cache max_upload enable_isr <<< "$nextjs_options"
            
            # Limpiar espacios de cada variable
            public_dir=$(echo "$public_dir" | tr -d ' ')
            enable_cache=$(echo "$enable_cache" | tr -d ' ')
            max_upload=$(echo "$max_upload" | tr -d ' ')
            enable_isr=$(echo "$enable_isr" | tr -d ' ')
            
            # Validar max_upload antes de usar
            if [ -z "$max_upload" ] || ! [[ "$max_upload" =~ ^[0-9]+$ ]] || [ "$max_upload" -le 0 ]; then
                echo -e "${YELLOW}Valor inválido para max_upload ($max_upload), usando 10MB por defecto${NC}"
                max_upload="10"
            fi
            
            # Asegurar valores por defecto si están vacíos
            public_dir="${public_dir:-/public}"
            enable_cache="${enable_cache:-s}"
            enable_isr="${enable_isr:-s}"
            
            echo -e "${CYAN}Opciones configuradas:${NC}"
            echo -e "  • Directorio público: $public_dir"
            echo -e "  • Caché de assets: $([ "$enable_cache" = "s" ] && echo "Habilitado" || echo "Deshabilitado")"
            echo -e "  • Tamaño máximo upload: ${max_upload}MB"
            echo -e "  • Soporte ISR: $([ "$enable_isr" = "s" ] && echo "Habilitado" || echo "Deshabilitado")"
            echo ""
            
            create_nextjs_config "$site_path" "$domain" "$port" "$public_dir" "$enable_cache" "$max_upload" "$enable_isr"
            echo -e "${GREEN}✓ Configuración Next.js creada exitosamente${NC}"
            echo -e "${CYAN}Características incluidas:${NC}"
            echo -e "  • Gzip compression habilitado"
            echo -e "  • Timeouts extendidos (120s) para SSR"
            echo -e "  • Buffers aumentados para páginas grandes"
            echo -e "  • Headers optimizados para Next.js"
            if [ "$enable_cache" = "s" ]; then
                echo -e "  • Caché inteligente para assets estáticos"
            fi
            if [ "$enable_isr" = "s" ]; then
                echo -e "  • Soporte para Incremental Static Regeneration"
            fi
            ;;
        *)
            echo -e "\n${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
            echo -e "${BLUE}${BOLD}  CONFIGURANDO SITIO API/BACKEND${NC}"
            echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
            echo -e "${CYAN}Tipo:${NC} API/Backend (REST API, GraphQL, etc.)"
            echo -e "${CYAN}Dominio:${NC} $domain"
            echo -e "${CYAN}Puerto:${NC} $port"
            echo ""
            
            create_api_config "$site_path" "$domain" "$port"
            echo -e "${GREEN}✓ Configuración API creada exitosamente${NC}"
            echo -e "${CYAN}Características incluidas:${NC}"
            echo -e "  • Proxy reverso estándar"
            echo -e "  • Headers de proxy configurados"
            echo -e "  • Timeouts de 60 segundos"
            echo -e "  • Soporte para WebSockets (upgrade)"
            ;;
    esac
    
    echo -e "${GREEN}Configuración creada: $site_path${NC}"
    echo -e "${CYAN}Certbot agregará automáticamente la redirección HTTP → HTTPS al configurar SSL${NC}"
    
    # Crear enlace simbólico si es necesario
    if [ -d "$NGINX_SITES_ENABLED" ] && [ ! -L "$NGINX_SITES_ENABLED/$site_name" ]; then
        sudo ln -s "$site_path" "$NGINX_SITES_ENABLED/$site_name"
        echo -e "${GREEN}Sitio habilitado: $site_name${NC}"
    fi
    
    return 0
}

configure_ssl() {
    local domain=$1
    local email=$2
    
    echo -e "\n${CYAN}Configurando SSL para $domain...${NC}"
    
    # Verificar si ya existe certificado SSL
    if check_certbot_certificates "$domain"; then
        echo -e "${GREEN}✓ El sitio ya tiene certificado SSL configurado${NC}"
        echo -e "${CYAN}Verificando validez del certificado...${NC}"
        
        # Verificar si el certificado está configurado en Nginx
        local certbot_certs=$(sudo certbot certificates 2>/dev/null | grep -A 5 "$domain")
        if [ -n "$certbot_certs" ]; then
            echo -e "${GREEN}✓ Certificado SSL válido y configurado${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Certificado existe pero puede no estar configurado en Nginx${NC}"
            echo -e "${CYAN}Intentando reconfigurar...${NC}"
        fi
    fi
    
    # Verificar configuración de Nginx antes de continuar
    if ! sudo nginx -t &> /dev/null; then
        echo -e "${RED}Error: La configuración de Nginx tiene errores.${NC}"
        echo -e "${YELLOW}Ejecutando: sudo nginx -t${NC}"
        sudo nginx -t
        return 1
    fi
    
    # Recargar Nginx para asegurar que la configuración esté activa
    echo -e "${CYAN}Recargando Nginx...${NC}"
    if sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null; then
        echo -e "${GREEN}✓ Nginx recargado${NC}"
    else
        echo -e "${YELLOW}⚠ Advertencia: No se pudo recargar Nginx${NC}"
    fi
    
    # Ejecutar certbot con opciones mejoradas
    echo -e "${CYAN}Ejecutando Certbot para obtener/configurar certificado SSL...${NC}"
    local certbot_output=$(sudo certbot --nginx -d "$domain" \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --redirect \
        --keep-until-expiring 2>&1 | tee /tmp/certbot_${domain}.log)
    local certbot_exit=$?
    
    if [ $certbot_exit -eq 0 ]; then
        echo -e "${GREEN}✓ SSL configurado correctamente para $domain${NC}"
        
        # Encontrar el archivo de configuración
        local site_config_file=""
        if [ -d "$NGINX_SITES_AVAILABLE" ] && [ -f "$NGINX_SITES_AVAILABLE/$domain" ]; then
            site_config_file="$NGINX_SITES_AVAILABLE/$domain"
        elif [ -d "$NGINX_CONF_DIR" ] && [ -f "$NGINX_CONF_DIR/$domain" ]; then
            site_config_file="$NGINX_CONF_DIR/$domain"
        fi
        
        # Verificar si las directivas SSL están configuradas (especialmente importante para Next.js)
        if [ -n "$site_config_file" ] && [ -f "$site_config_file" ]; then
            local has_ssl_cert=$(grep -qE "^\s*ssl_certificate\s+" "$site_config_file" 2>/dev/null && echo "yes" || echo "no")
            
            if [ "$has_ssl_cert" = "no" ]; then
                echo -e "${YELLOW}⚠ Certbot completó pero no se detectaron directivas SSL en la configuración${NC}"
                echo -e "${CYAN}Verificando si el certificado existe y agregando directivas SSL manualmente...${NC}"
                
                # Verificar si el certificado existe
                local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
                local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
                
                if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
                    echo -e "${CYAN}Certificado encontrado. Agregando directivas SSL a la configuración...${NC}"
                    
                    # Crear backup
                    local backup_file="${site_config_file}.backup.$(date +%Y%m%d_%H%M%S)"
                    sudo cp "$site_config_file" "$backup_file" 2>/dev/null
                    
                    # Buscar el bloque server con listen 443 y agregar SSL si no está
                    if grep -qE "^\s*listen\s+443" "$site_config_file" 2>/dev/null; then
                        # Verificar si hay directivas SSL comentadas
                        if grep -qE "^\s*#\s*ssl_certificate" "$site_config_file" 2>/dev/null; then
                            # Descomentar las líneas SSL
                            sudo sed -i "s|^\s*#\s*ssl_certificate\s\+/etc/letsencrypt/live/$domain/fullchain.pem;|    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|g" "$site_config_file"
                            sudo sed -i "s|^\s*#\s*ssl_certificate_key\s\+/etc/letsencrypt/live/$domain/privkey.pem;|    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|g" "$site_config_file"
                            echo -e "${GREEN}✓ Directivas SSL descomentadas${NC}"
                        else
                            # Agregar directivas SSL después de server_name
                            sudo sed -i "/^\s*server_name\s\+$domain;/a\\
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;\\
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers HIGH:!aNULL:!MD5;\\
    ssl_prefer_server_ciphers on;" "$site_config_file"
                            echo -e "${GREEN}✓ Directivas SSL agregadas${NC}"
                        fi
                    fi
                    
                    # Validar configuración
                    if sudo nginx -t &> /dev/null; then
                        echo -e "${GREEN}✓ Configuración validada después de agregar SSL${NC}"
                    else
                        echo -e "${RED}✗ Error en configuración después de agregar SSL${NC}"
                        sudo nginx -t
                        # Restaurar backup
                        sudo mv "$backup_file" "$site_config_file" 2>/dev/null
                        echo -e "${YELLOW}Configuración restaurada desde backup${NC}"
                        return 1
                    fi
                else
                    echo -e "${YELLOW}⚠ Certificado no encontrado en las rutas esperadas${NC}"
                fi
            fi
        fi
        
        # Verificar que la configuración SSL esté correcta
        if sudo nginx -t &> /dev/null; then
            echo -e "${GREEN}✓ Configuración de Nginx validada${NC}"
            sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
            
            # Esperar un momento para que Nginx se recargue
            sleep 2
            
            # Verificar configuración SSL
            echo -e "\n${CYAN}Verificando configuración SSL...${NC}"
            if [ -n "$site_config_file" ]; then
                verify_ssl_certificate_config "$domain" "$site_config_file"
                local verify_result=$?
                
                if [ $verify_result -eq 0 ]; then
                    echo -e "\n${CYAN}Probando conexión HTTPS...${NC}"
                    test_ssl_connection "$domain"
                fi
            fi
            
            return 0
        else
            echo -e "${YELLOW}⚠ Advertencia: Certbot completó pero hay errores en la configuración${NC}"
            sudo nginx -t
            return 1
        fi
    else
        echo -e "${RED}✗ Error al configurar SSL para $domain${NC}"
        echo -e "${YELLOW}Logs del error:${NC}"
        cat /tmp/certbot_${domain}.log 2>/dev/null | tail -20 | sed 's/^/  /'
        echo -e "${YELLOW}Revisa los logs completos en /tmp/certbot_${domain}.log${NC}"
        return 1
    fi
}

###############################################################################
# FUNCIONES DE VALIDACIÓN SSL
###############################################################################

get_certificate_expiry_info() {
    local domain=$1
    
    # Intentar obtener información del certificado desde Certbot
    local cert_info=$(sudo certbot certificates 2>/dev/null | grep -A 20 "$domain" | grep -E "(Certificate Name|Expiry Date|Certificate Path)" | head -5)
    
    # Intentar obtener desde el archivo de certificado directamente
    local cert_path=""
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    fi
    
    # Si no encontramos el path desde Certbot, intentar desde Nginx
    if [ -z "$cert_path" ] || [ ! -f "$cert_path" ]; then
        # Buscar en sites-available y conf.d
        for config_dir in "$NGINX_SITES_AVAILABLE" "$NGINX_CONF_DIR"; do
            if [ -d "$config_dir" ]; then
                for config_file in "$config_dir"/*; do
                    if [ -f "$config_file" ] && grep -q "server_name.*$domain" "$config_file" 2>/dev/null; then
                        local found_cert_path=$(grep -E "^\s*ssl_certificate\s+" "$config_file" 2>/dev/null | head -1 | sed 's/.*ssl_certificate\s\+\([^;]*\);.*/\1/' | tr -d ' ')
                        if [ -n "$found_cert_path" ] && [ -f "$found_cert_path" ]; then
                            cert_path="$found_cert_path"
                            break 2
                        fi
                    fi
                done
            fi
        done
    fi
    
    if [ -z "$cert_path" ] || [ ! -f "$cert_path" ]; then
        return 1
    fi
    
    # Obtener fecha de expiración usando openssl
    local expiry_date=$(sudo openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [ -z "$expiry_date" ]; then
        return 1
    fi
    
    # Convertir fecha a timestamp (funciona en Linux y macOS)
    local expiry_timestamp=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        expiry_timestamp=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" "+%s" 2>/dev/null)
        if [ -z "$expiry_timestamp" ]; then
            expiry_timestamp=$(date -j -f "%b %d %H:%M:%S %Y" "$expiry_date" "+%s" 2>/dev/null)
        fi
    else
        # Linux
        expiry_timestamp=$(date -d "$expiry_date" "+%s" 2>/dev/null)
    fi
    
    if [ -z "$expiry_timestamp" ]; then
        return 1
    fi
    
    # Obtener timestamp actual
    local current_timestamp=$(date "+%s")
    
    # Calcular días restantes
    local seconds_remaining=$((expiry_timestamp - current_timestamp))
    local days_remaining=$((seconds_remaining / 86400))
    
    # Formatear fecha de expiración para mostrar
    local expiry_formatted=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        expiry_formatted=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" "+%Y-%m-%d" 2>/dev/null)
        if [ -z "$expiry_formatted" ]; then
            expiry_formatted=$(date -j -f "%b %d %H:%M:%S %Y" "$expiry_date" "+%Y-%m-%d" 2>/dev/null)
        fi
    else
        expiry_formatted=$(date -d "$expiry_date" "+%Y-%m-%d" 2>/dev/null)
    fi
    
    if [ -z "$expiry_formatted" ]; then
        expiry_formatted="$expiry_date"
    fi
    
    echo "$days_remaining|$expiry_formatted|$expiry_date"
    return 0
}

verify_ssl_certificate_config() {
    local domain=$1
    local config_file=$2
    
    echo -e "${CYAN}Verificando configuración SSL para $domain...${NC}"
    
    local ssl_configured=false
    local cert_exists=false
    local key_exists=false
    local nginx_listening=false
    
    # Verificar si el certificado está configurado en Nginx
    if [ -f "$config_file" ]; then
        if grep -qE "^\s*ssl_certificate\s+" "$config_file" 2>/dev/null; then
            ssl_configured=true
            local cert_path=$(grep -E "^\s*ssl_certificate\s+" "$config_file" | head -1 | sed 's/.*ssl_certificate\s\+\([^;]*\);.*/\1/' | tr -d ' ')
            
            if [ -f "$cert_path" ]; then
                cert_exists=true
            fi
            
            local key_path=$(grep -E "^\s*ssl_certificate_key\s+" "$config_file" | head -1 | sed 's/.*ssl_certificate_key\s\+\([^;]*\);.*/\1/' | tr -d ' ')
            
            if [ -f "$key_path" ]; then
                key_exists=true
            fi
        fi
    fi
    
    # Verificar certificado en Certbot
    if check_certbot_certificates "$domain"; then
        echo -e "  ${GREEN}✓${NC} Certificado encontrado en Certbot"
        
        # Obtener información de expiración
        local expiry_info=$(get_certificate_expiry_info "$domain")
        if [ -n "$expiry_info" ]; then
            IFS='|' read -r days_remaining expiry_formatted expiry_date <<< "$expiry_info"
            
            if [ "$days_remaining" -gt 0 ]; then
                if [ "$days_remaining" -lt 30 ]; then
                    echo -e "  ${RED}⚠${NC} Certificado expira en ${days_remaining} días (${expiry_formatted})"
                elif [ "$days_remaining" -lt 60 ]; then
                    echo -e "  ${YELLOW}⚠${NC} Certificado expira en ${days_remaining} días (${expiry_formatted})"
                else
                    echo -e "  ${GREEN}✓${NC} Certificado válido por ${days_remaining} días más (expira: ${expiry_formatted})"
                fi
            else
                echo -e "  ${RED}✗${NC} Certificado EXPIRADO o expira hoy"
            fi
        fi
    else
        echo -e "  ${RED}✗${NC} Certificado NO encontrado en Certbot"
    fi
    
    # Verificar configuración en Nginx
    local has_https_block=false
    if [ -f "$config_file" ]; then
        if grep -qE "^\s*listen\s+443" "$config_file" 2>/dev/null; then
            has_https_block=true
        fi
    fi
    
    if [ "$ssl_configured" = true ]; then
        echo -e "  ${GREEN}✓${NC} SSL configurado en Nginx"
        if [ "$cert_exists" = true ]; then
            echo -e "  ${GREEN}✓${NC} Archivo de certificado existe"
            
            # Verificar si el certificado corresponde al dominio
            local cert_subject=$(sudo openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/.*CN=\([^/]*\).*/\1/' | tr -d ' ')
            local cert_sans=$(sudo openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | grep "DNS:" | sed 's/.*DNS:\([^,]*\).*/\1/' | tr -d ' ' | head -5)
            
            if [ -n "$cert_subject" ]; then
                echo -e "  ${CYAN}  Certificado CN: $cert_subject${NC}"
                
                # Verificar si corresponde al dominio
                local cert_matches=false
                
                # Verificar CN (puede ser wildcard o dominio específico)
                if [ "$cert_subject" = "$domain" ]; then
                    # Coincide exactamente
                    cert_matches=true
                elif [[ "$cert_subject" == *.* ]]; then
                    # Verificar si es wildcard (empieza con *)
                    if [[ "$cert_subject" == *.* ]]; then
                        local cert_base="${cert_subject#*.}"
                        # Si es wildcard (*.dominio.com)
                        if [[ "$cert_subject" == *.$cert_base ]]; then
                            # Verificar si el dominio coincide con el wildcard
                            local domain_base="${domain#*.}"
                            if [ "$domain_base" = "$cert_base" ]; then
                                cert_matches=true
                            fi
                        # Si no es wildcard, verificar coincidencia exacta
                        elif [ "$cert_subject" = "$domain" ]; then
                            cert_matches=true
                        fi
                    fi
                fi
                
                # Verificar SANs
                if [ -n "$cert_sans" ] && [ "$cert_matches" = false ]; then
                    echo -e "  ${CYAN}  Certificado SANs:${NC}"
                    while IFS= read -r san; do
                        if [ -n "$san" ]; then
                            echo -e "    • $san"
                            # Verificar coincidencia exacta
                            if [ "$san" = "$domain" ]; then
                                cert_matches=true
                            # Verificar wildcard en SAN
                            elif [[ "$san" == *.* ]]; then
                                local san_base="${san#*.}"
                                if [[ "$san" == *.$san_base ]]; then
                                    # Es wildcard (*.dominio.com)
                                    local domain_base="${domain#*.}"
                                    if [ "$domain_base" = "$san_base" ]; then
                                        cert_matches=true
                                    fi
                                fi
                            fi
                        fi
                    done <<< "$cert_sans"
                fi
                
                if [ "$cert_matches" = false ]; then
                    echo -e "  ${RED}✗${NC} Certificado NO corresponde al dominio '$domain'"
                    echo -e "    ${YELLOW}El certificado es para otro dominio. Esto puede causar error 526 en Cloudflare.${NC}"
                else
                    echo -e "  ${GREEN}✓${NC} Certificado corresponde al dominio"
                fi
            fi
        else
            echo -e "  ${RED}✗${NC} Archivo de certificado NO existe"
            if [ -n "$cert_path" ]; then
                echo -e "    ${YELLOW}Ruta esperada: $cert_path${NC}"
            fi
        fi
        if [ "$key_exists" = true ]; then
            echo -e "  ${GREEN}✓${NC} Archivo de clave existe"
        else
            echo -e "  ${RED}✗${NC} Archivo de clave NO existe"
            if [ -n "$key_path" ]; then
                echo -e "    ${YELLOW}Ruta esperada: $key_path${NC}"
            fi
        fi
    else
        if [ "$has_https_block" = true ]; then
            echo -e "  ${RED}✗${NC} SSL NO configurado en Nginx"
            echo -e "    ${YELLOW}Problema detectado:${NC}"
            echo -e "    • Existe un bloque server con 'listen 443' pero sin directivas SSL"
            echo -e "    • El certificado existe en Certbot pero no está vinculado en Nginx"
            echo -e "    ${CYAN}Solución:${NC} Ejecutar reparación SSL para este sitio"
        else
            echo -e "  ${RED}✗${NC} SSL NO configurado en Nginx"
            echo -e "    ${YELLOW}No hay bloque HTTPS configurado en Nginx${NC}"
        fi
    fi
    
    # Verificar que Nginx esté escuchando en 443
    if sudo netstat -tlnp 2>/dev/null | grep -q ":443 " || sudo ss -tlnp 2>/dev/null | grep -q ":443 "; then
        nginx_listening=true
        echo -e "  ${GREEN}✓${NC} Nginx está escuchando en puerto 443"
    else
        echo -e "  ${YELLOW}⚠${NC} Nginx NO está escuchando en puerto 443"
    fi
    
    if [ "$ssl_configured" = true ] && [ "$cert_exists" = true ] && [ "$key_exists" = true ] && [ "$nginx_listening" = true ]; then
        return 0
    else
        return 1
    fi
}

test_ssl_connection() {
    local domain=$1
    
    echo -e "${CYAN}Probando conexión HTTPS a $domain...${NC}"
    
    # Verificar si curl está disponible
    if ! command -v curl &> /dev/null; then
        echo -e "  ${YELLOW}⚠${NC} curl no está instalado, no se puede probar la conexión HTTPS"
        return 2
    fi
    
    # Primero probar conexión básica (sin verificar certificado)
    local https_test=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 -k "https://$domain" 2>/dev/null)
    local https_exit=$?
    
    # Verificar código HTTP - 000 significa problema de conexión
    if [ "$https_test" = "000" ]; then
        echo -e "  ${RED}✗${NC} No se pudo conectar vía HTTPS"
        echo -e "    ${YELLOW}Posibles causas:${NC}"
        echo -e "    • El servidor no está respondiendo en el puerto 443"
        echo -e "    • Firewall bloqueando la conexión"
        echo -e "    • El dominio no está apuntando correctamente al servidor"
        echo -e "    • Nginx no está escuchando en el puerto 443 para este dominio"
        return 1
    fi
    
    if [ $https_exit -ne 0 ]; then
        echo -e "  ${RED}✗${NC} Error al conectar vía HTTPS (código de salida: $https_exit)"
        return 1
    fi
    
    # Verificar códigos HTTP específicos que indican problemas SSL/Cloudflare
    local has_ssl_issue=false
    case "$https_test" in
        526)
            echo -e "  ${RED}✗${NC} Error Cloudflare 526: Invalid SSL Certificate"
            echo -e "    ${YELLOW}Diagnóstico:${NC}"
            echo -e "    • Cloudflare no puede validar el certificado SSL del servidor de origen"
            echo -e "    • El certificado puede no estar configurado en Nginx"
            echo -e "    • El certificado puede no coincidir con el dominio"
            echo -e "    • Cloudflare está en modo 'Full' o 'Full (strict)' pero el servidor no tiene SSL válido"
            echo -e "    ${CYAN}Solución:${NC} Configurar SSL en Nginx o cambiar Cloudflare a modo 'Flexible'"
            has_ssl_issue=true
            ;;
        502)
            echo -e "  ${RED}✗${NC} Error 502: Bad Gateway"
            echo -e "    ${YELLOW}Diagnóstico:${NC}"
            echo -e "    • Cloudflare no puede conectarse al servidor de origen"
            echo -e "    • Puede ser un problema de SSL entre Cloudflare y el servidor"
            echo -e "    • El servidor puede estar caído o no responder"
            has_ssl_issue=true
            ;;
        503)
            echo -e "  ${YELLOW}⚠${NC} Error 503: Service Unavailable"
            echo -e "    ${YELLOW}El servidor puede estar sobrecargado o en mantenimiento${NC}"
            ;;
        520|521|522|523|524|525)
            echo -e "  ${RED}✗${NC} Error Cloudflare $https_test"
            echo -e "    ${YELLOW}Error específico de Cloudflare. Revisa la configuración del servidor de origen.${NC}"
            has_ssl_issue=true
            ;;
        404)
            echo -e "  ${GREEN}✓${NC} Conexión HTTPS exitosa (código HTTP: 404)"
            echo -e "    ${CYAN}Nota:${NC} El código 404 es normal si la ruta no existe, pero SSL funciona correctamente"
            ;;
        200|201|202|301|302|307|308)
            echo -e "  ${GREEN}✓${NC} Conexión HTTPS exitosa (código HTTP: $https_test)"
            ;;
        *)
            if [[ "$https_test" =~ ^[45][0-9][0-9]$ ]]; then
                echo -e "  ${YELLOW}⚠${NC} Conexión HTTPS con código HTTP: $https_test"
                echo -e "    ${CYAN}Nota:${NC} El servidor responde pero con un código de error HTTP"
            else
                echo -e "  ${GREEN}✓${NC} Conexión HTTPS exitosa (código HTTP: $https_test)"
            fi
            ;;
    esac
    
    # Si hay un problema SSL detectado por código HTTP, no continuar con verificación SSL
    if [ "$has_ssl_issue" = true ]; then
        return 1
    fi
    
    # Ahora verificar el certificado SSL (sin -k)
    local ssl_verify=$(curl -s -o /dev/null -w "%{ssl_verify_result}" --max-time 10 --connect-timeout 5 "https://$domain" 2>/dev/null)
    local ssl_exit=$?
    
    # Obtener más detalles del error SSL si hay problema
    local ssl_error_detail=""
    if [ "$ssl_verify" != "0" ] && [ $ssl_exit -eq 0 ]; then
        ssl_error_detail=$(curl -s -o /dev/null -w "%{ssl_verify_result}" --max-time 10 --connect-timeout 5 "https://$domain" 2>&1 | grep -i "ssl\|certificate\|verify" | head -1)
    fi
    
    # ssl_verify_result: 0 = éxito, otros valores = error
    if [ $ssl_exit -eq 0 ] && [ "$ssl_verify" = "0" ]; then
        echo -e "  ${GREEN}✓${NC} Certificado SSL válido y verificado"
        
        # Obtener información del certificado
        local cert_info=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null)
        if [ -n "$cert_info" ]; then
            local cert_subject=$(echo "$cert_info" | grep "subject=" | sed 's/.*subject=//')
            local cert_valid_from=$(echo "$cert_info" | grep "notBefore=" | sed 's/.*notBefore=//')
            local cert_valid_to=$(echo "$cert_info" | grep "notAfter=" | sed 's/.*notAfter=//')
            
            if [ -n "$cert_subject" ]; then
                echo -e "  ${CYAN}  Certificado para: $cert_subject${NC}"
            fi
            if [ -n "$cert_valid_to" ]; then
                # Calcular días restantes
                local expiry_info=$(get_certificate_expiry_info "$domain")
                if [ -n "$expiry_info" ]; then
                    IFS='|' read -r days_remaining expiry_formatted expiry_date <<< "$expiry_info"
                    
                    if [ "$days_remaining" -gt 0 ]; then
                        if [ "$days_remaining" -lt 30 ]; then
                            echo -e "  ${RED}  ⚠ Expira en ${days_remaining} días (${expiry_formatted})${NC}"
                        elif [ "$days_remaining" -lt 60 ]; then
                            echo -e "  ${YELLOW}  ⚠ Expira en ${days_remaining} días (${expiry_formatted})${NC}"
                        else
                            echo -e "  ${GREEN}  ✓ Válido por ${days_remaining} días más (expira: ${expiry_formatted})${NC}"
                        fi
                    else
                        echo -e "  ${RED}  ✗ Certificado EXPIRADO o expira hoy${NC}"
                    fi
                else
                    echo -e "  ${CYAN}  Válido hasta: $cert_valid_to${NC}"
                fi
            fi
        fi
        
        return 0
    else
        echo -e "  ${RED}✗${NC} Certificado SSL tiene problemas"
        if [ "$ssl_verify" != "0" ]; then
            case "$ssl_verify" in
                1) 
                    echo -e "    ${RED}Error: Certificado no verificado${NC}"
                    echo -e "    ${YELLOW}Diagnóstico:${NC}"
                    echo -e "    • El certificado puede no estar correctamente configurado en Nginx"
                    echo -e "    • El certificado puede no coincidir con el dominio"
                    echo -e "    • Puede haber un problema con la cadena de certificados"
                    ;;
                2) 
                    echo -e "    ${RED}Error: No se pudo verificar el certificado${NC}"
                    echo -e "    ${YELLOW}Diagnóstico:${NC}"
                    echo -e "    • Problema de conectividad durante la verificación"
                    echo -e "    • El certificado puede estar corrupto"
                    ;;
                3) 
                    echo -e "    ${RED}Error: Certificado expirado${NC}"
                    echo -e "    ${YELLOW}Diagnóstico:${NC}"
                    echo -e "    • El certificado ha expirado y necesita renovación"
                    ;;
                4) 
                    echo -e "    ${RED}Error: Certificado auto-firmado${NC}"
                    echo -e "    ${YELLOW}Diagnóstico:${NC}"
                    echo -e "    • El certificado no es de una autoridad certificadora confiable"
                    ;;
                5) 
                    echo -e "    ${RED}Error: Certificado no confiable${NC}"
                    echo -e "    ${YELLOW}Diagnóstico:${NC}"
                    echo -e "    • Problema con la cadena de confianza del certificado"
                    ;;
                *) 
                    echo -e "    ${RED}Error de verificación SSL (código: $ssl_verify)${NC}"
                    ;;
            esac
        fi
        if [ -n "$ssl_error_detail" ]; then
            echo -e "    ${CYAN}Detalle adicional: $ssl_error_detail${NC}"
        fi
        return 1
    fi
}

###############################################################################
# FUNCIONES DE REPARACIÓN SSL
###############################################################################

diagnose_ssl_issue() {
    local domain=$1
    local config_file=$2
    
    local issues=()
    local issue_descriptions=()
    
    # Verificar si certificado existe en Certbot
    local certbot_has_cert=false
    if check_certbot_certificates "$domain"; then
        certbot_has_cert=true
    else
        issues+=("no_certbot_cert")
        issue_descriptions+=("Certificado no encontrado en Certbot")
    fi
    
    # Verificar si SSL está configurado en Nginx
    local ssl_configured=false
    local has_ssl_block=false
    if [ -f "$config_file" ]; then
        # Verificar si hay bloque server con listen 443
        if grep -qE "^\s*listen\s+443" "$config_file" 2>/dev/null; then
            has_ssl_block=true
        fi
        
        # Verificar si hay directiva ssl_certificate
        if grep -qE "^\s*ssl_certificate\s+" "$config_file" 2>/dev/null; then
            ssl_configured=true
        fi
    fi
    
    # Caso especial: Certificado existe en Certbot pero no está configurado en Nginx
    if [ "$certbot_has_cert" = true ] && [ "$ssl_configured" = false ]; then
        issues+=("no_nginx_config")
        if [ "$has_ssl_block" = true ]; then
            issue_descriptions+=("Certificado existe en Certbot pero SSL no está configurado en bloque HTTPS de Nginx")
        else
            issue_descriptions+=("Certificado existe en Certbot pero no hay bloque HTTPS configurado en Nginx")
        fi
    elif [ "$ssl_configured" = false ]; then
        issues+=("no_nginx_config")
        issue_descriptions+=("SSL no configurado en Nginx")
    fi
    
    # Verificar si los archivos de certificado existen y si el certificado corresponde al dominio
    if [ "$ssl_configured" = true ]; then
        local cert_path=$(grep -E "^\s*ssl_certificate\s+" "$config_file" 2>/dev/null | head -1 | sed 's/.*ssl_certificate\s\+\([^;]*\);.*/\1/' | tr -d ' ')
        if [ -n "$cert_path" ] && [ ! -f "$cert_path" ]; then
            issues+=("cert_file_missing")
            issue_descriptions+=("Archivo de certificado no existe: $cert_path")
        elif [ -n "$cert_path" ] && [ -f "$cert_path" ]; then
            # Verificar si el certificado corresponde al dominio
            local cert_subject=$(sudo openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/.*CN=\([^/]*\).*/\1/' | tr -d ' ')
            local cert_sans=$(sudo openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | grep "DNS:" | sed 's/.*DNS:\([^,]*\).*/\1/' | tr -d ' ')
            
            local cert_matches=false
            local cert_domains=()
            
            # Verificar CN
            if [ -n "$cert_subject" ]; then
                cert_domains+=("$cert_subject")
                # Verificar si es wildcard
                if [[ "$cert_subject" == *.* ]]; then
                    local base_domain="${cert_subject#*.}"
                    if [[ "$domain" == *"$base_domain" ]] || [[ "$cert_subject" == "*.$base_domain" ]]; then
                        cert_matches=true
                    fi
                elif [ "$cert_subject" = "$domain" ]; then
                    cert_matches=true
                fi
            fi
            
            # Verificar SANs
            if [ -n "$cert_sans" ]; then
                while IFS= read -r san; do
                    if [ -n "$san" ]; then
                        cert_domains+=("$san")
                        if [[ "$san" == *.* ]]; then
                            local san_base="${san#*.}"
                            if [[ "$domain" == *"$san_base" ]] || [[ "$san" == "*.$san_base" ]]; then
                                cert_matches=true
                            fi
                        elif [ "$san" = "$domain" ]; then
                            cert_matches=true
                        fi
                    fi
                done <<< "$cert_sans"
            fi
            
            # Si el certificado no corresponde al dominio
            if [ "$cert_matches" = false ] && [ ${#cert_domains[@]} -gt 0 ]; then
                issues+=("cert_domain_mismatch")
                local cert_domains_str=$(IFS=', '; echo "${cert_domains[*]}")
                issue_descriptions+=("Certificado no corresponde al dominio. Certificado para: $cert_domains_str, pero dominio es: $domain")
            fi
        fi
        
        local key_path=$(grep -E "^\s*ssl_certificate_key\s+" "$config_file" 2>/dev/null | head -1 | sed 's/.*ssl_certificate_key\s\+\([^;]*\);.*/\1/' | tr -d ' ')
        if [ -n "$key_path" ] && [ ! -f "$key_path" ]; then
            issues+=("key_file_missing")
            issue_descriptions+=("Archivo de clave no existe: $key_path")
        fi
    fi
    
    # Verificar expiración
    local expiry_info=$(get_certificate_expiry_info "$domain")
    if [ -n "$expiry_info" ]; then
        IFS='|' read -r days_remaining expiry_formatted expiry_date <<< "$expiry_info"
        if [ "$days_remaining" -le 0 ]; then
            issues+=("cert_expired")
            issue_descriptions+=("Certificado expirado")
        elif [ "$days_remaining" -lt 30 ]; then
            issues+=("cert_expiring_soon")
            issue_descriptions+=("Certificado expira pronto (${days_remaining} días)")
        fi
    fi
    
    # Probar conexión HTTPS para detectar problemas como código 526
    if command -v curl &> /dev/null; then
        local https_test=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 -k "https://$domain" 2>/dev/null)
        
        # Detectar códigos HTTP que indican problemas SSL
        case "$https_test" in
            526)
                # Error específico de Cloudflare: Invalid SSL Certificate
                if [ "$ssl_configured" = false ]; then
                    # Si no está configurado, ya lo detectamos arriba
                    if [[ ! " ${issues[@]} " =~ " no_nginx_config " ]]; then
                        issues+=("no_nginx_config")
                        issue_descriptions+=("Error Cloudflare 526: SSL no configurado correctamente en Nginx")
                    fi
                else
                    # Está configurado pero Cloudflare no lo acepta
                    issues+=("cloudflare_526_error")
                    issue_descriptions+=("Error Cloudflare 526: Certificado no válido para Cloudflare (puede ser problema de configuración SSL)")
                fi
                ;;
            502|520|521|522|523|524|525)
                issues+=("cloudflare_ssl_error")
                issue_descriptions+=("Error Cloudflare $https_test: Problema de SSL entre Cloudflare y servidor de origen")
                ;;
        esac
    fi
    
    # Retornar issues como string separado por |
    if [ ${#issues[@]} -gt 0 ]; then
        echo "${issues[*]}|${issue_descriptions[*]}"
        return 1
    else
        return 0
    fi
}

repair_ssl_configuration() {
    local domain=$1
    local config_file=$2
    local issue_type=$3
    
    echo -e "\n${CYAN}${BOLD}Intentando reparar: $issue_type${NC}\n"
    
    case "$issue_type" in
        no_nginx_config)
            echo -e "${CYAN}El certificado existe pero no está configurado en Nginx.${NC}"
            
            # Verificar si hay un bloque server con listen 443
            local has_https_block=false
            local is_nextjs_config=false
            if [ -f "$config_file" ]; then
                if grep -qE "^\s*listen\s+443" "$config_file" 2>/dev/null; then
                    has_https_block=true
                    echo -e "${YELLOW}Se detectó un bloque HTTPS pero sin configuración SSL${NC}"
                    
                    # Verificar si es configuración de Next.js
                    if grep -qE "# Tipo: Next.js|# Configuración para Next.js" "$config_file" 2>/dev/null; then
                        is_nextjs_config=true
                        echo -e "${CYAN}Detectada configuración de Next.js con SSL sin configurar${NC}"
                    fi
                fi
            fi
            
            echo -e "${CYAN}Reconfigurando SSL con Certbot...${NC}"
            
            # Obtener email del certificado existente o pedirlo
            local email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$domain" | grep "Account" | awk '{print $3}' | head -1)
            if [ -z "$email" ]; then
                # Intentar obtener de otros certificados del mismo dominio base
                local base_domain=$(echo "$domain" | sed 's/^[^.]*\.//')
                email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$base_domain" | grep "Account" | awk '{print $3}' | head -1)
            fi
            
            if [ -z "$email" ]; then
                read -p "Ingresa el email para certificados SSL: " email
                if [ -z "$email" ]; then
                    email="admin@$domain"
                fi
            fi
            
            # Si hay bloque HTTPS pero sin SSL, Certbot puede tener problemas
            # Intentar primero reconfigurar, si falla, puede necesitarse configuración manual
            echo -e "${CYAN}Ejecutando Certbot para configurar SSL...${NC}"
            local certbot_output=$(sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" --redirect --keep-until-expiring 2>&1 | tee /tmp/certbot_repair_${domain}.log)
            local certbot_exit=$?
            
            if [ $certbot_exit -eq 0 ]; then
                echo -e "${GREEN}✓ SSL reconfigurado correctamente${NC}"
                
                # Si es configuración Next.js, verificar que las directivas SSL estén presentes
                if [ "$is_nextjs_config" = true ]; then
                    echo -e "${CYAN}Verificando configuración SSL en Next.js...${NC}"
                    local has_ssl_cert=$(grep -qE "^\s*ssl_certificate\s+" "$config_file" 2>/dev/null && echo "yes" || echo "no")
                    
                    if [ "$has_ssl_cert" = "no" ]; then
                        echo -e "${YELLOW}⚠ Certbot completó pero no se detectaron directivas SSL. Agregándolas manualmente...${NC}"
                        
                        local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
                        local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
                        
                        if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
                            # Crear backup
                            local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
                            sudo cp "$config_file" "$backup_file" 2>/dev/null
                            
                            # Descomentar o agregar directivas SSL
                            if grep -qE "^\s*#\s*ssl_certificate" "$config_file" 2>/dev/null; then
                                sudo sed -i "s|^\s*#\s*ssl_certificate\s\+/etc/letsencrypt/live/$domain/fullchain.pem;|    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|g" "$config_file"
                                sudo sed -i "s|^\s*#\s*ssl_certificate_key\s\+/etc/letsencrypt/live/$domain/privkey.pem;|    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|g" "$config_file"
                                echo -e "${GREEN}✓ Directivas SSL descomentadas${NC}"
                            else
                                # Agregar después de server_name
                                sudo sed -i "/^\s*server_name\s\+$domain;/a\\
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;\\
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers HIGH:!aNULL:!MD5;\\
    ssl_prefer_server_ciphers on;" "$config_file"
                                echo -e "${GREEN}✓ Directivas SSL agregadas${NC}"
                            fi
                        fi
                    fi
                fi
                
                # Validar y recargar Nginx
                if sudo nginx -t &> /dev/null; then
                    sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
                    echo -e "${GREEN}✓ Nginx recargado${NC}"
                    
                    # Esperar un momento y verificar
                    sleep 2
                    echo -e "${CYAN}Verificando configuración después de reparación...${NC}"
                    verify_ssl_certificate_config "$domain" "$config_file"
                    
                    return 0
                else
                    echo -e "${RED}✗ Error en configuración de Nginx después de reparación${NC}"
                    sudo nginx -t
                    return 1
                fi
            else
                echo -e "${RED}✗ Error al reconfigurar SSL${NC}"
                echo -e "${YELLOW}Logs del error:${NC}"
                cat /tmp/certbot_repair_${domain}.log 2>/dev/null | tail -30 | sed 's/^/  /'
                
                # Si Certbot falla, intentar agregar SSL manualmente si es Next.js
                if [ "$has_https_block" = true ] && [ "$is_nextjs_config" = true ]; then
                    echo -e "\n${CYAN}Intentando agregar SSL manualmente para configuración Next.js...${NC}"
                    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
                    local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
                    
                    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
                        local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
                        sudo cp "$config_file" "$backup_file" 2>/dev/null
                        
                        # Descomentar o agregar directivas SSL
                        if grep -qE "^\s*#\s*ssl_certificate" "$config_file" 2>/dev/null; then
                            sudo sed -i "s|^\s*#\s*ssl_certificate\s\+/etc/letsencrypt/live/$domain/fullchain.pem;|    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|g" "$config_file"
                            sudo sed -i "s|^\s*#\s*ssl_certificate_key\s\+/etc/letsencrypt/live/$domain/privkey.pem;|    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|g" "$config_file"
                            
                            if sudo nginx -t &> /dev/null; then
                                sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
                                echo -e "${GREEN}✓ SSL configurado manualmente${NC}"
                                return 0
                            else
                                sudo mv "$backup_file" "$config_file" 2>/dev/null
                            fi
                        fi
                    fi
                fi
                
                echo -e "\n${YELLOW}Posible solución manual:${NC}"
                echo -e "El bloque HTTPS existe pero Certbot no pudo configurarlo automáticamente."
                echo -e "Puede ser necesario agregar manualmente las directivas SSL al bloque server."
                
                return 1
            fi
            ;;
        cert_file_missing|key_file_missing)
            echo -e "${CYAN}Archivos de certificado faltantes. Reconfigurando SSL...${NC}"
            repair_ssl_configuration "$domain" "$config_file" "no_nginx_config"
            ;;
        cert_expired|cert_expiring_soon)
            echo -e "${CYAN}Renovando certificado expirado o próximo a expirar...${NC}"
            
            # Intentar renovar
            if sudo certbot renew --cert-name "$domain" --force-renewal 2>&1 | tee /tmp/certbot_renew_${domain}.log; then
                echo -e "${GREEN}✓ Certificado renovado${NC}"
                
                # Reconfigurar en Nginx si es necesario
                local email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$domain" | grep "Account" | awk '{print $3}' | head -1)
                if [ -z "$email" ]; then
                    email="admin@$domain"
                fi
                
                sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" --redirect --keep-until-expiring 2>&1 | tee /tmp/certbot_reconfig_${domain}.log
                
                if sudo nginx -t &> /dev/null; then
                    sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
                    echo -e "${GREEN}✓ Nginx recargado${NC}"
                    return 0
                else
                    echo -e "${RED}✗ Error en configuración después de renovación${NC}"
                    return 1
                fi
            else
                echo -e "${RED}✗ Error al renovar certificado${NC}"
                cat /tmp/certbot_renew_${domain}.log 2>/dev/null | tail -20
                return 1
            fi
            ;;
        no_certbot_cert)
            echo -e "${CYAN}No se encontró certificado en Certbot. Creando nuevo certificado...${NC}"
            
            read -p "Ingresa el email para certificados SSL: " email
            if [ -z "$email" ]; then
                email="admin@$domain"
            fi
            
            configure_ssl "$domain" "$email"
            return $?
            ;;
        cloudflare_526_error)
            echo -e "${CYAN}Error Cloudflare 526 detectado.${NC}"
            echo -e "${CYAN}El certificado está configurado pero Cloudflare no lo acepta.${NC}"
            echo -e "${CYAN}Reconfigurando SSL para asegurar compatibilidad con Cloudflare...${NC}"
            
            # Obtener email
            local email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$domain" | grep "Account" | awk '{print $3}' | head -1)
            if [ -z "$email" ]; then
                local base_domain=$(echo "$domain" | sed 's/^[^.]*\.//')
                email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$base_domain" | grep "Account" | awk '{print $3}' | head -1)
            fi
            
            if [ -z "$email" ]; then
                read -p "Ingresa el email para certificados SSL: " email
                if [ -z "$email" ]; then
                    email="admin@$domain"
                fi
            fi
            
            # Verificar que el certificado esté correctamente configurado
            echo -e "${CYAN}Verificando configuración actual...${NC}"
            verify_ssl_certificate_config "$domain" "$config_file"
            
            # Intentar reconfigurar con Certbot
            echo -e "${CYAN}Reconfigurando SSL con Certbot...${NC}"
            if sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" --redirect --keep-until-expiring 2>&1 | tee /tmp/certbot_repair_526_${domain}.log; then
                echo -e "${GREEN}✓ SSL reconfigurado${NC}"
                
                if sudo nginx -t &> /dev/null; then
                    sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
                    echo -e "${GREEN}✓ Nginx recargado${NC}"
                    
                    sleep 2
                    echo -e "${CYAN}Verificando después de reparación...${NC}"
                    verify_ssl_certificate_config "$domain" "$config_file"
                    return 0
                else
                    echo -e "${RED}✗ Error en configuración de Nginx${NC}"
                    sudo nginx -t
                    return 1
                fi
            else
                echo -e "${RED}✗ Error al reconfigurar SSL${NC}"
                cat /tmp/certbot_repair_526_${domain}.log 2>/dev/null | tail -30 | sed 's/^/  /'
                return 1
            fi
            ;;
        cloudflare_ssl_error)
            echo -e "${CYAN}Error de Cloudflare detectado. Reconfigurando SSL...${NC}"
            repair_ssl_configuration "$domain" "$config_file" "no_nginx_config"
            ;;
        cert_domain_mismatch)
            echo -e "${CYAN}El certificado no corresponde al dominio '$domain'.${NC}"
            echo -e "${YELLOW}Problema detectado:${NC}"
            echo -e "  • El certificado configurado es para otro dominio"
            echo -e "  • Esto causa que Cloudflare rechace la conexión (error 526)"
            echo -e "  • Necesitas un certificado específico para este dominio"
            echo ""
            
            read -p "¿Deseas crear un nuevo certificado específico para '$domain'? (s/n): " create_new_cert
            if [[ "$create_new_cert" =~ ^[Ss]$ ]]; then
                # Obtener email
                local email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$domain" | grep "Account" | awk '{print $3}' | head -1)
                if [ -z "$email" ]; then
                    local base_domain=$(echo "$domain" | sed 's/^[^.]*\.//')
                    email=$(sudo certbot certificates 2>/dev/null | grep -A 10 "$base_domain" | grep "Account" | awk '{print $3}' | head -1)
                fi
                
                if [ -z "$email" ]; then
                    read -p "Ingresa el email para certificados SSL: " email
                    if [ -z "$email" ]; then
                        email="admin@$domain"
                    fi
                fi
                
                echo -e "${CYAN}Creando nuevo certificado específico para '$domain'...${NC}"
                configure_ssl "$domain" "$email"
                return $?
            else
                echo -e "${YELLOW}Operación cancelada. Necesitas crear un certificado específico para este dominio.${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${YELLOW}No se puede reparar automáticamente: $issue_type${NC}"
            return 1
            ;;
    esac
}

repair_site_ssl_interactive() {
    local domain=$1
    local config_file=$2
    
    echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}Reparación SSL para: $domain${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Diagnosticar problemas (esto ahora incluye prueba HTTPS)
    local diagnosis=$(diagnose_ssl_issue "$domain" "$config_file")
    local diagnose_exit=$?
    
    # Siempre probar conexión HTTPS para mostrar resultados al usuario
    echo -e "${CYAN}Probando conexión HTTPS...${NC}"
    test_ssl_connection "$domain"
    local https_test_exit=$?
    
    # Si no se detectaron problemas en el diagnóstico pero la prueba HTTPS falla,
    # forzar un nuevo diagnóstico que incluya la prueba HTTPS
    if [ $diagnose_exit -eq 0 ] && [ $https_test_exit -ne 0 ]; then
        echo -e "${YELLOW}⚠ La configuración parece correcta pero la conexión HTTPS falla${NC}"
        echo -e "${CYAN}Re-diagnosticando con prueba HTTPS...${NC}"
        diagnosis=$(diagnose_ssl_issue "$domain" "$config_file")
        diagnose_exit=$?
    fi
    
    if [ $diagnose_exit -eq 0 ] && [ $https_test_exit -eq 0 ]; then
        echo -e "\n${GREEN}✓ No se detectaron problemas. SSL funcionando correctamente.${NC}\n"
        return 0
    fi
    
    # Si hay problemas, continuar con el proceso de reparación
    if [ $diagnose_exit -eq 0 ]; then
        # Si después de la prueba HTTPS aún no detecta problemas, pero HTTPS falla,
        # crear un diagnóstico manual basado en el código HTTP
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 -k "https://$domain" 2>/dev/null)
        if [ "$http_code" = "526" ]; then
            diagnosis="cloudflare_526_error|Error Cloudflare 526: Certificado no válido para Cloudflare"
            diagnose_exit=1
        fi
    fi
    
    IFS='|' read -r issues issue_descriptions <<< "$diagnosis"
    read -ra issue_array <<< "$issues"
    read -ra desc_array <<< "$issue_descriptions"
    
    echo -e "${YELLOW}Problemas detectados:${NC}"
    for i in "${!issue_array[@]}"; do
        echo -e "  ${RED}✗${NC} ${desc_array[$i]}"
    done
    echo ""
    
    echo -e "${CYAN}Opciones de reparación:${NC}"
    echo -e "  1) Reparar automáticamente todos los problemas"
    echo -e "  2) Reparar problemas específicos"
    echo -e "  3) Solo verificar (sin reparar)"
    echo -e "  4) Cancelar"
    echo ""
    read -p "Opción (1-4): " repair_option
    
    case "$repair_option" in
        1)
            # Reparar todos los problemas
            for issue in "${issue_array[@]}"; do
                repair_ssl_configuration "$domain" "$config_file" "$issue"
            done
            
            # Verificar después de reparar
            echo -e "\n${CYAN}Verificando después de reparación...${NC}"
            verify_ssl_certificate_config "$domain" "$config_file"
            test_ssl_connection "$domain"
            ;;
        2)
            # Reparar problemas específicos
            echo -e "\n${CYAN}Selecciona el problema a reparar:${NC}"
            for i in "${!issue_array[@]}"; do
                echo -e "  $((i+1))) ${desc_array[$i]}"
            done
            echo ""
            read -p "Número del problema (o 'a' para todos): " selected_issue
            
            if [[ "$selected_issue" =~ ^[Aa]$ ]]; then
                for issue in "${issue_array[@]}"; do
                    repair_ssl_configuration "$domain" "$config_file" "$issue"
                done
            elif [[ "$selected_issue" =~ ^[0-9]+$ ]] && [ "$selected_issue" -ge 1 ] && [ "$selected_issue" -le ${#issue_array[@]} ]; then
                local idx=$((selected_issue - 1))
                repair_ssl_configuration "$domain" "$config_file" "${issue_array[$idx]}"
            else
                echo -e "${YELLOW}Opción inválida${NC}"
                return 1
            fi
            
            # Verificar después de reparar
            echo -e "\n${CYAN}Verificando después de reparación...${NC}"
            verify_ssl_certificate_config "$domain" "$config_file"
            test_ssl_connection "$domain"
            ;;
        3)
            # Solo verificar
            verify_ssl_certificate_config "$domain" "$config_file"
            test_ssl_connection "$domain"
            ;;
        4)
            echo -e "${YELLOW}Reparación cancelada${NC}"
            return 1
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            return 1
            ;;
    esac
}

verify_all_sites_ssl() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           VALIDACIÓN SSL DE TODOS LOS SITIOS${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_to_verify=()
    local index=1
    
    # Buscar sitios en sites-available
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                if [ -n "$domain" ]; then
                    sites_to_verify+=("$site_file|$site_name|$domain")
                fi
            fi
        done
    fi
    
    # Buscar sitios en conf.d
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                if [ -n "$domain" ]; then
                    sites_to_verify+=("$site_file|$site_name|$domain")
                fi
            fi
        done
    fi
    
    if [ ${#sites_to_verify[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios para validar.${NC}\n"
        return 1
    fi
    
    echo -e "${CYAN}Sitios encontrados: ${#sites_to_verify[@]}${NC}\n"
    
    local valid_count=0
    local invalid_count=0
    local test_failed_count=0
    local sites_with_issues=()
    
    for site_info in "${sites_to_verify[@]}"; do
        IFS='|' read -r site_file site_name domain <<< "$site_info"
        
        echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}${BOLD}Sitio: $site_name${NC}"
        echo -e "${CYAN}Dominio: $domain${NC}"
        echo ""
        
        local has_issue=false
        
        # Verificar configuración SSL
        if verify_ssl_certificate_config "$domain" "$site_file"; then
            ((valid_count++))
            echo -e "  ${GREEN}✓ Configuración SSL correcta${NC}"
        else
            ((invalid_count++))
            has_issue=true
            echo -e "  ${RED}✗ Configuración SSL tiene problemas${NC}"
        fi
        
        echo ""
        
        # Probar conexión HTTPS
        if test_ssl_connection "$domain"; then
            echo -e "  ${GREEN}✓ Conexión HTTPS funcionando correctamente${NC}"
        else
            ((test_failed_count++))
            has_issue=true
            echo -e "  ${RED}✗ Problemas con la conexión HTTPS${NC}"
        fi
        
        # Guardar sitio con problemas
        if [ "$has_issue" = true ]; then
            sites_with_issues+=("$site_file|$site_name|$domain")
        fi
        
        echo ""
    done
    
    # Resumen con días restantes de certificados
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           RESUMEN DE CERTIFICADOS SSL${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    echo -e "${CYAN}Estado de certificados por sitio:${NC}\n"
    printf "%-40s %-15s %-15s\n" "Dominio" "Días Restantes" "Estado"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
    
    for site_info in "${sites_to_verify[@]}"; do
        IFS='|' read -r site_file site_name domain <<< "$site_info"
        
        local expiry_info=$(get_certificate_expiry_info "$domain")
        if [ -n "$expiry_info" ]; then
            IFS='|' read -r days_remaining expiry_formatted expiry_date <<< "$expiry_info"
            
            local status=""
            local status_color=""
            if [ "$days_remaining" -gt 0 ]; then
                if [ "$days_remaining" -lt 30 ]; then
                    status="⚠ Expira pronto"
                    status_color="${RED}"
                elif [ "$days_remaining" -lt 60 ]; then
                    status="⚠ Atención"
                    status_color="${YELLOW}"
                else
                    status="✓ Válido"
                    status_color="${GREEN}"
                fi
                printf "%-40s %-15s ${status_color}%-15s${NC}\n" "$domain" "${days_remaining} días" "$status"
            else
                printf "%-40s %-15s ${RED}%-15s${NC}\n" "$domain" "EXPIRADO" "✗ Expirado"
            fi
        else
            printf "%-40s %-15s ${RED}%-15s${NC}\n" "$domain" "N/A" "✗ Sin certificado"
        fi
    done
    
    echo ""
    
    # Resumen estadístico
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           RESUMEN DE VALIDACIÓN${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    echo -e "${GREEN}✓ Sitios con SSL correctamente configurado: $valid_count${NC}"
    echo -e "${RED}✗ Sitios con problemas de configuración SSL: $invalid_count${NC}"
    echo -e "${YELLOW}⚠ Sitios con problemas de conexión HTTPS: $test_failed_count${NC}"
    echo ""
    
    if [ $invalid_count -eq 0 ] && [ $test_failed_count -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ Todos los sitios tienen SSL funcionando correctamente${NC}\n"
        return 0
    else
        echo -e "${YELLOW}${BOLD}⚠ Algunos sitios necesitan atención${NC}\n"
        
        # Ofrecer reparación si hay sitios con problemas
        if [ ${#sites_with_issues[@]} -gt 0 ]; then
            echo -e "${CYAN}¿Deseas intentar reparar los sitios con problemas?${NC}"
            echo -e "  1) Reparar todos los sitios automáticamente"
            echo -e "  2) Reparar sitios específicos"
            echo -e "  3) No reparar ahora"
            echo ""
            read -p "Opción (1-3): " repair_all_option
            
            case "$repair_all_option" in
                1)
                    # Reparar todos automáticamente
                    echo -e "\n${CYAN}Reparando todos los sitios con problemas...${NC}\n"
                    for site_info in "${sites_with_issues[@]}"; do
                        IFS='|' read -r site_file site_name domain <<< "$site_info"
                        local diagnosis=$(diagnose_ssl_issue "$domain" "$site_file")
                        if [ $? -ne 0 ]; then
                            IFS='|' read -r issues issue_descriptions <<< "$diagnosis"
                            read -ra issue_array <<< "$issues"
                            for issue in "${issue_array[@]}"; do
                                repair_ssl_configuration "$domain" "$site_file" "$issue"
                            done
                        fi
                    done
                    ;;
                2)
                    # Reparar sitios específicos
                    echo -e "\n${CYAN}Sitios con problemas:${NC}\n"
                    for i in "${!sites_with_issues[@]}"; do
                        IFS='|' read -r site_file site_name domain <<< "${sites_with_issues[$i]}"
                        echo -e "  $((i+1))) $domain ($site_name)"
                    done
                    echo ""
                    read -p "Selecciona el número del sitio a reparar (o 'a' para todos): " selected_site
                    
                    if [[ "$selected_site" =~ ^[Aa]$ ]]; then
                        for site_info in "${sites_with_issues[@]}"; do
                            IFS='|' read -r site_file site_name domain <<< "$site_info"
                            repair_site_ssl_interactive "$domain" "$site_file"
                        done
                    elif [[ "$selected_site" =~ ^[0-9]+$ ]] && [ "$selected_site" -ge 1 ] && [ "$selected_site" -le ${#sites_with_issues[@]} ]; then
                        local idx=$((selected_site - 1))
                        IFS='|' read -r site_file site_name domain <<< "${sites_with_issues[$idx]}"
                        repair_site_ssl_interactive "$domain" "$site_file"
                    else
                        echo -e "${YELLOW}Opción inválida${NC}"
                    fi
                    ;;
                3)
                    echo -e "${YELLOW}Reparación cancelada${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}Opción inválida${NC}"
                    ;;
            esac
        fi
        
        return 1
    fi
}

process_containers() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           CONFIGURACIÓN DE CONTENEDORES${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local success_count=0
    local error_count=0
    local errors=()
    
    for container_info in "${SELECTED_CONTAINERS[@]}"; do
        IFS='|' read -r name exposed_ports <<< "$container_info"
        
        echo -e "\n${CYAN}${BOLD}Procesando: $name${NC}"
        
        # Obtener puerto del contenedor
        local port=$(get_container_info "$name")
        
        if [ -z "$port" ] || [ "$port" = "" ]; then
            echo -e "${YELLOW}⚠ No se pudo determinar el puerto automáticamente.${NC}"
            echo -e "${CYAN}Puertos disponibles del contenedor:${NC}"
            docker port "$name" 2>/dev/null || echo "  No se pudieron obtener puertos"
            read -p "Ingresa el puerto del host para $name (ej: 8080): " port
        fi
        
        # Validar que el puerto sea un número
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}✗ Puerto inválido. Omitiendo $name${NC}"
            errors+=("$name: Puerto inválido")
            ((error_count++))
            continue
        fi
        
        # Solicitar dominio
        read -p "Ingresa el dominio para $name (ej: ejemplo.com): " domain
        
        if [ -z "$domain" ]; then
            echo -e "${RED}✗ Dominio no proporcionado. Omitiendo $name${NC}"
            errors+=("$name: Dominio no proporcionado")
            ((error_count++))
            continue
        fi
        
        # Solicitar email para SSL
        read -p "Ingresa el email para certificados SSL: " email
        
        if [ -z "$email" ]; then
            echo -e "${YELLOW}⚠ Email no proporcionado. Se usará un email por defecto.${NC}"
            email="admin@$domain"
        fi
        
        # Crear configuración de Nginx
        create_nginx_config "$name" "$domain" "$port"
        local create_result=$?
        
        if [ "$create_result" -eq 0 ]; then
            # Recargar Nginx
            if sudo nginx -t &> /dev/null; then
                sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
                echo -e "${GREEN}✓ Nginx recargado${NC}"
            else
                echo -e "${YELLOW}⚠ Advertencia: Error en configuración de Nginx${NC}"
                errors+=("$name: Error en configuración de Nginx")
            fi
            
            # Configurar SSL
            if configure_ssl "$domain" "$email"; then
                echo -e "${GREEN}✓ Configuración completa para $name${NC}"
                ((success_count++))
            else
                errors+=("$name: Error al configurar SSL")
                ((error_count++))
            fi
        elif [ "$create_result" -eq 2 ]; then
            # Sitio ya existe, solo verificar/configurar SSL si es necesario
            echo -e "${CYAN}Verificando configuración SSL...${NC}"
            if check_certbot_certificates "$domain"; then
                echo -e "${GREEN}✓ El sitio ya tiene SSL configurado${NC}"
                ((success_count++))
            else
                echo -e "${YELLOW}⚠ El sitio existe pero no tiene SSL. Configurando SSL...${NC}"
                if configure_ssl "$domain" "$email"; then
                    echo -e "${GREEN}✓ SSL configurado para sitio existente${NC}"
                    ((success_count++))
                else
                    errors+=("$name: Error al configurar SSL en sitio existente")
                    ((error_count++))
                fi
            fi
        else
            errors+=("$name: Error al crear configuración")
            ((error_count++))
        fi
    done
    
    # Mostrar resumen
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           RESUMEN DE CONFIGURACIÓN${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    echo -e "${GREEN}✓ Configuraciones exitosas: $success_count${NC}"
    echo -e "${RED}✗ Errores: $error_count${NC}"
    
    if [ ${#errors[@]} -gt 0 ]; then
        echo -e "\n${RED}Errores encontrados:${NC}"
        for error in "${errors[@]}"; do
            echo -e "  - $error"
        done
    fi
    
    echo ""
}

###############################################################################
# FUNCIONES DE ELIMINACIÓN
###############################################################################

get_domain_from_config() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        # Buscar server_name en el archivo
        local domain=$(grep -E "^\s*server_name\s+" "$config_file" | head -n1 | sed 's/.*server_name\s\+\([^;]*\);.*/\1/' | tr -d ' ')
        echo "$domain"
    fi
}

check_certbot_certificates() {
    local domain=$1
    if [ -z "$domain" ]; then
        return 1
    fi
    
    # Verificar si hay certificados de certbot para este dominio
    if sudo certbot certificates 2>/dev/null | grep -q "$domain"; then
        return 0
    fi
    
    # Verificar si existe el directorio de certificados
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        return 0
    fi
    
    return 1
}

list_sites_for_deletion() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SITIOS DISPONIBLES PARA ELIMINAR${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_list=()
    local index=1
    
    # Buscar en sites-available
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                local enabled=""
                local ssl_info=""
                
                if [ -L "$NGINX_SITES_ENABLED/$site_name" ]; then
                    enabled="${GREEN}[ACTIVO]${NC}"
                else
                    enabled="${RED}[INACTIVO]${NC}"
                fi
                
                if [ -n "$domain" ] && check_certbot_certificates "$domain"; then
                    ssl_info="${CYAN}[SSL]${NC}"
                fi
                
                echo -e "  $index) $site_name $enabled $ssl_info"
                if [ -n "$domain" ]; then
                    echo -e "     Dominio: $domain"
                fi
                
                sites_list+=("$site_file|$site_name|$domain")
                ((index++))
            fi
        done
    fi
    
    # Buscar en conf.d (todos los archivos, no solo .conf)
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                local ssl_info=""
                
                if [ -n "$domain" ] && check_certbot_certificates "$domain"; then
                    ssl_info="${CYAN}[SSL]${NC}"
                fi
                
                echo -e "  $index) $site_name ${GREEN}[ACTIVO]${NC} $ssl_info"
                if [ -n "$domain" ]; then
                    echo -e "     Dominio: $domain"
                fi
                
                sites_list+=("$site_file|$site_name|$domain")
                ((index++))
            fi
        done
    fi
    
    if [ ${#sites_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios para eliminar.${NC}\n"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Total de sitios encontrados: ${#sites_list[@]}${NC}\n"
    
    # Devolver la lista como variable global
    DELETE_SITES_LIST=("${sites_list[@]}")
    return 0
}

select_site_to_delete() {
    if [ ${#DELETE_SITES_LIST[@]} -eq 0 ]; then
        return 1
    fi
    
    read -p "Selecciona el número del sitio a eliminar (o 'q' para cancelar): " selection
    
    if [[ "$selection" =~ ^[Qq]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#DELETE_SITES_LIST[@]} ]; then
        echo -e "${RED}Selección inválida.${NC}\n"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local selected_site="${DELETE_SITES_LIST[$selected_index]}"
    
    IFS='|' read -r site_file site_name domain <<< "$selected_site"
    
    echo -e "\n${YELLOW}${BOLD}Sitio seleccionado para eliminar:${NC}"
    echo -e "  ${CYAN}Archivo:${NC} $site_file"
    echo -e "  ${CYAN}Nombre:${NC} $site_name"
    if [ -n "$domain" ]; then
        echo -e "  ${CYAN}Dominio:${NC} $domain"
    fi
    
    # Verificar si tiene SSL
    local has_ssl=false
    if [ -n "$domain" ] && check_certbot_certificates "$domain"; then
        has_ssl=true
        echo -e "  ${CYAN}SSL:${NC} ${YELLOW}Tiene certificados SSL configurados${NC}"
    fi
    
    echo ""
    read -p "¿Estás seguro de que deseas eliminar este sitio? (s/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    # Si tiene SSL, preguntar si también eliminar certificados
    local delete_certs=false
    if [ "$has_ssl" = true ]; then
        echo ""
        read -p "¿Deseas también eliminar los certificados SSL asociados? (s/n): " delete_certs_confirm
        if [[ "$delete_certs_confirm" =~ ^[Ss]$ ]]; then
            delete_certs=true
        fi
    fi
    
    # Llamar a la función de eliminación
    delete_site "$site_file" "$site_name" "$domain" "$delete_certs"
    return $?
}

delete_site() {
    local site_file=$1
    local site_name=$2
    local domain=$3
    local delete_certs=$4
    
    echo -e "\n${CYAN}${BOLD}Eliminando sitio: $site_name${NC}\n"
    
    local errors=()
    local success_steps=()
    
    # 1. Deshabilitar el sitio (eliminar enlace simbólico)
    if [ -L "$NGINX_SITES_ENABLED/$site_name" ]; then
        echo -e "${CYAN}Deshabilitando sitio...${NC}"
        if sudo rm "$NGINX_SITES_ENABLED/$site_name" 2>/dev/null; then
            echo -e "${GREEN}✓ Sitio deshabilitado${NC}"
            success_steps+=("Sitio deshabilitado")
        else
            echo -e "${RED}✗ Error al deshabilitar sitio${NC}"
            errors+=("Error al deshabilitar sitio")
        fi
    fi
    
    # 2. Eliminar certificados SSL si se solicitó
    if [ "$delete_certs" = true ] && [ -n "$domain" ]; then
        echo -e "${CYAN}Verificando certificados SSL para $domain...${NC}"
        
        # Verificar si el certificado tiene múltiples dominios
        local cert_info=$(sudo certbot certificates 2>/dev/null | grep -A 10 "Certificate Name:.*$domain" | head -20)
        local cert_name=$(echo "$cert_info" | grep "Certificate Name:" | awk '{print $3}')
        
        if [ -z "$cert_name" ]; then
            # Intentar encontrar el certificado por dominio
            cert_name=$(sudo certbot certificates 2>/dev/null | grep -B 2 "$domain" | grep "Certificate Name:" | awk '{print $3}' | head -1)
        fi
        
        if [ -n "$cert_name" ]; then
            # Verificar cuántos dominios tiene el certificado
            local domains_in_cert=$(sudo certbot certificates 2>/dev/null | grep -A 10 "Certificate Name: $cert_name" | grep "Domains:" | sed 's/.*Domains: //')
            
            if [ -n "$domains_in_cert" ]; then
                local domain_count=$(echo "$domains_in_cert" | tr ',' '\n' | wc -l | tr -d ' ')
                
                if [ "$domain_count" -gt 1 ]; then
                    echo -e "${YELLOW}⚠ Advertencia: El certificado '$cert_name' incluye múltiples dominios:${NC}"
                    echo -e "${YELLOW}  $domains_in_cert${NC}"
                    echo -e "${YELLOW}  Eliminar este certificado afectará a otros dominios.${NC}"
                    read -p "¿Deseas continuar eliminando el certificado completo? (s/n): " confirm_cert_delete
                    
                    if [[ ! "$confirm_cert_delete" =~ ^[Ss]$ ]]; then
                        echo -e "${YELLOW}Eliminación de certificados cancelada.${NC}"
                        delete_certs=false
                    fi
                fi
            fi
            
            if [ "$delete_certs" = true ]; then
                echo -e "${CYAN}Eliminando certificados SSL...${NC}"
                local certbot_output=$(sudo certbot delete --cert-name "$cert_name" --non-interactive 2>&1)
                local certbot_exit=$?
                
                if [ $certbot_exit -eq 0 ]; then
                    echo -e "${GREEN}✓ Certificados SSL eliminados${NC}"
                    success_steps+=("Certificados SSL eliminados")
                else
                    echo -e "${RED}✗ Error al eliminar certificados SSL${NC}"
                    echo -e "${YELLOW}Logs del error:${NC}"
                    echo "$certbot_output" | sed 's/^/  /'
                    echo -e "${YELLOW}  Puedes eliminarlos manualmente con: sudo certbot delete --cert-name $cert_name${NC}"
                    errors+=("Error al eliminar certificados SSL: $certbot_output")
                fi
            fi
        else
            echo -e "${YELLOW}⚠ No se encontraron certificados SSL para $domain${NC}"
        fi
    fi
    
    # 3. Verificar si otros sitios usan el mismo dominio antes de eliminar el archivo
    local other_sites_using_domain=false
    local other_sites_list=()
    
    if [ -n "$domain" ]; then
        # Buscar en sites-available
        if [ -d "$NGINX_SITES_AVAILABLE" ]; then
            for other_file in "$NGINX_SITES_AVAILABLE"/*; do
                if [ -f "$other_file" ] && [ "$other_file" != "$site_file" ]; then
                    # Buscar el dominio en el archivo (puede estar en múltiples líneas)
                    if grep -qE "server_name\s+.*$domain" "$other_file" 2>/dev/null; then
                        other_sites_using_domain=true
                        local other_site_name=$(basename "$other_file")
                        other_sites_list+=("$other_site_name")
                    fi
                fi
            done
        fi
        
        # Buscar en conf.d
        if [ -d "$NGINX_CONF_DIR" ]; then
            for other_file in "$NGINX_CONF_DIR"/*.conf; do
                if [ -f "$other_file" ] && [ "$other_file" != "$site_file" ]; then
                    if grep -qE "server_name\s+.*$domain" "$other_file" 2>/dev/null; then
                        other_sites_using_domain=true
                        local other_site_name=$(basename "$other_file")
                        other_sites_list+=("$other_site_name")
                    fi
                fi
            done
        fi
        
        if [ "$other_sites_using_domain" = true ]; then
            echo -e "${YELLOW}⚠ Advertencia: Otros sitios también usan el dominio '$domain':${NC}"
            for other_site in "${other_sites_list[@]}"; do
                echo -e "${YELLOW}  - $other_site${NC}"
            done
            echo -e "${YELLOW}  Los certificados SSL se mantendrán para estos sitios.${NC}"
        fi
    fi
    
    # 4. Eliminar archivo de configuración
    if [ -f "$site_file" ]; then
        echo -e "${CYAN}Eliminando archivo de configuración...${NC}"
        
        if sudo rm "$site_file" 2>/dev/null; then
            echo -e "${GREEN}✓ Archivo de configuración eliminado${NC}"
            success_steps+=("Archivo eliminado")
        else
            echo -e "${RED}✗ Error al eliminar archivo de configuración${NC}"
            errors+=("Error al eliminar archivo")
        fi
    fi
    
    # 5. Validar y recargar Nginx
    echo -e "${CYAN}Validando configuración de Nginx...${NC}"
    if sudo nginx -t &> /dev/null; then
        echo -e "${GREEN}✓ Configuración válida${NC}"
        if sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null; then
            echo -e "${GREEN}✓ Nginx recargado${NC}"
            success_steps+=("Nginx recargado")
        else
            echo -e "${YELLOW}⚠ Advertencia: No se pudo recargar Nginx${NC}"
            errors+=("Error al recargar Nginx")
        fi
    else
        echo -e "${RED}✗ Error en la configuración de Nginx${NC}"
        sudo nginx -t
        errors+=("Error en configuración de Nginx")
    fi
    
    # Mostrar resumen
    echo -e "\n${BLUE}${BOLD}Resumen de eliminación:${NC}"
    if [ ${#success_steps[@]} -gt 0 ]; then
        echo -e "${GREEN}Operaciones exitosas:${NC}"
        for step in "${success_steps[@]}"; do
            echo -e "  ✓ $step"
        done
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        echo -e "\n${RED}${BOLD}Errores encontrados:${NC}"
        for error in "${errors[@]}"; do
            echo -e "  ${RED}✗${NC} $error"
        done
        echo ""
        echo -e "${YELLOW}Para más detalles, revisa los logs arriba.${NC}"
        return 1
    else
        echo -e "\n${GREEN}${BOLD}✓ Sitio eliminado correctamente${NC}\n"
        return 0
    fi
}

###############################################################################
# FUNCIONES DE RENOMBRAR Y ESTANDARIZAR
###############################################################################

is_standard_name() {
    local site_name=$1
    # Un nombre estándar es SOLO el dominio SIN .conf (ej: ejemplo.com)
    # NO debe terminar en .conf
    # Debe ser un dominio válido (contiene al menos un punto)
    
    # Si termina en .conf, NO es estándar (a menos que sea un dominio válido sin palabras de contenedor)
    if [[ "$site_name" =~ \.conf$ ]]; then
        # Remover .conf para obtener el dominio
        local domain_part="${site_name%.conf}"
        
        # Verificar que el dominio tenga al menos un punto (formato dominio.com)
        if [[ ! "$domain_part" =~ \. ]]; then
            return 1  # No es un dominio válido
        fi
        
        # Verificar que no sea un nombre de contenedor típico
        if [[ "$domain_part" =~ (container|api-container|service-container|app-container|-container) ]]; then
            return 1  # Es un nombre de contenedor, no estándar
        fi
        
        # Verificar que no tenga formato de nombre de contenedor (muchos guiones seguidos)
        if [[ "$domain_part" =~ -.*-.*- ]]; then
            return 1  # Probablemente es un nombre de contenedor
        fi
        
        # Si tiene .conf pero es un dominio válido sin palabras de contenedor, podría ser estándar
        # Pero el formato correcto es sin .conf, así que lo marcamos como no estándar para renombrarlo
        return 1
    fi
    
    # Si NO termina en .conf, verificar que sea un dominio válido
    if [[ ! "$site_name" =~ \. ]]; then
        return 1  # No es un dominio válido
    fi
    
    # Verificar que no sea un nombre de contenedor típico
    if [[ "$site_name" =~ (container|api-container|service-container|app-container|-container) ]]; then
        return 1  # Es un nombre de contenedor, no estándar
    fi
    
    # Si es un dominio válido sin .conf y sin palabras de contenedor, es estándar
    return 0
}

list_sites_for_rename() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SITIOS DISPONIBLES PARA RENOMBRAR${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_list=()
    local index=1
    
    # Buscar en sites-available
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                local enabled=""
                local standard=""
                
                if [ -L "$NGINX_SITES_ENABLED/$site_name" ]; then
                    enabled="${GREEN}[ACTIVO]${NC}"
                else
                    enabled="${RED}[INACTIVO]${NC}"
                fi
                
                if is_standard_name "$site_name"; then
                    standard="${GREEN}[ESTÁNDAR]${NC}"
                else
                    standard="${YELLOW}[NO ESTÁNDAR]${NC}"
                fi
                
                echo -e "  $index) $site_name $enabled $standard"
                if [ -n "$domain" ]; then
                    echo -e "     Dominio: $domain"
                    if ! is_standard_name "$site_name"; then
                        echo -e "     ${CYAN}Nombre sugerido: $domain${NC}"
                    fi
                fi
                
                sites_list+=("$site_file|$site_name|$domain")
                ((index++))
            fi
        done
    fi
    
    # Buscar en conf.d (todos los archivos, no solo .conf)
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                local standard=""
                
                if is_standard_name "$site_name"; then
                    standard="${GREEN}[ESTÁNDAR]${NC}"
                else
                    standard="${YELLOW}[NO ESTÁNDAR]${NC}"
                fi
                
                echo -e "  $index) $site_name ${GREEN}[ACTIVO]${NC} $standard"
                if [ -n "$domain" ]; then
                    echo -e "     Dominio: $domain"
                    if ! is_standard_name "$site_name"; then
                        echo -e "     ${CYAN}Nombre sugerido: $domain${NC}"
                    fi
                fi
                
                sites_list+=("$site_file|$site_name|$domain")
                ((index++))
            fi
        done
    fi
    
    if [ ${#sites_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios para renombrar.${NC}\n"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Total de sitios encontrados: ${#sites_list[@]}${NC}\n"
    
    RENAME_SITES_LIST=("${sites_list[@]}")
    return 0
}

rename_site() {
    local old_file=$1
    local old_name=$2
    local domain=$3
    local new_name=$4
    
    echo -e "\n${CYAN}${BOLD}Renombrando sitio:${NC}"
    echo -e "  ${CYAN}Archivo actual:${NC} $old_file"
    echo -e "  ${CYAN}Nombre actual:${NC} $old_name"
    echo -e "  ${CYAN}Nuevo nombre:${NC} $new_name"
    echo ""
    
    local errors=()
    local success_steps=()
    
    # Determinar directorio base
    local base_dir=""
    if [[ "$old_file" == "$NGINX_SITES_AVAILABLE"/* ]]; then
        base_dir="$NGINX_SITES_AVAILABLE"
    elif [[ "$old_file" == "$NGINX_CONF_DIR"/* ]]; then
        base_dir="$NGINX_CONF_DIR"
    else
        echo -e "${RED}Error: No se pudo determinar el directorio base${NC}"
        return 1
    fi
    
    local new_file="$base_dir/$new_name"
    
    # Verificar si el nuevo nombre ya existe
    if [ -f "$new_file" ]; then
        echo -e "${RED}Error: El archivo $new_name ya existe${NC}"
        return 1
    fi
    
    # 1. Renombrar el archivo
    echo -e "${CYAN}Renombrando archivo...${NC}"
    if sudo mv "$old_file" "$new_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Archivo renombrado${NC}"
        success_steps+=("Archivo renombrado")
    else
        echo -e "${RED}✗ Error al renombrar archivo${NC}"
        errors+=("Error al renombrar archivo")
        return 1
    fi
    
    # 2. Actualizar enlace simbólico si existe
    if [ -d "$NGINX_SITES_ENABLED" ] && [ -L "$NGINX_SITES_ENABLED/$old_name" ]; then
        echo -e "${CYAN}Actualizando enlace simbólico...${NC}"
        sudo rm "$NGINX_SITES_ENABLED/$old_name" 2>/dev/null
        if sudo ln -s "$new_file" "$NGINX_SITES_ENABLED/$new_name" 2>/dev/null; then
            echo -e "${GREEN}✓ Enlace simbólico actualizado${NC}"
            success_steps+=("Enlace simbólico actualizado")
        else
            echo -e "${YELLOW}⚠ Advertencia: No se pudo actualizar el enlace simbólico${NC}"
            errors+=("Error al actualizar enlace simbólico")
        fi
    fi
    
    # 3. Validar y recargar Nginx
    echo -e "${CYAN}Validando configuración de Nginx...${NC}"
    if sudo nginx -t &> /dev/null; then
        echo -e "${GREEN}✓ Configuración válida${NC}"
        if sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null; then
            echo -e "${GREEN}✓ Nginx recargado${NC}"
            success_steps+=("Nginx recargado")
        else
            echo -e "${YELLOW}⚠ Advertencia: No se pudo recargar Nginx${NC}"
            errors+=("Error al recargar Nginx")
        fi
    else
        echo -e "${RED}✗ Error en la configuración de Nginx${NC}"
        sudo nginx -t
        errors+=("Error en configuración de Nginx")
        return 1
    fi
    
    # Mostrar resumen
    echo -e "\n${BLUE}${BOLD}Resumen de renombrado:${NC}"
    if [ ${#success_steps[@]} -gt 0 ]; then
        echo -e "${GREEN}Operaciones exitosas:${NC}"
        for step in "${success_steps[@]}"; do
            echo -e "  ✓ $step"
        done
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        echo -e "\n${RED}Errores encontrados:${NC}"
        for error in "${errors[@]}"; do
            echo -e "  ✗ $error"
        done
        return 1
    else
        echo -e "\n${GREEN}${BOLD}✓ Sitio renombrado correctamente${NC}\n"
        return 0
    fi
}

select_site_to_rename() {
    if [ ${#RENAME_SITES_LIST[@]} -eq 0 ]; then
        return 1
    fi
    
    read -p "Selecciona el número del sitio a renombrar (o 'q' para cancelar): " selection
    
    if [[ "$selection" =~ ^[Qq]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#RENAME_SITES_LIST[@]} ]; then
        echo -e "${RED}Selección inválida.${NC}\n"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local selected_site="${RENAME_SITES_LIST[$selected_index]}"
    
    IFS='|' read -r site_file site_name domain <<< "$selected_site"
    
    # Si ya tiene nombre estándar, informar
    if is_standard_name "$site_name"; then
        echo -e "${GREEN}El sitio ya tiene un nombre estándar: $site_name${NC}\n"
        return 1
    fi
    
    # Si no tiene dominio, no se puede renombrar
    if [ -z "$domain" ]; then
        echo -e "${RED}Error: No se pudo determinar el dominio del sitio${NC}"
        echo -e "${YELLOW}No se puede renombrar sin un dominio válido.${NC}\n"
        return 1
    fi
    
    local suggested_name="$domain"
    
    echo -e "\n${YELLOW}${BOLD}Sitio seleccionado:${NC}"
    echo -e "  ${CYAN}Archivo actual:${NC} $site_file"
    echo -e "  ${CYAN}Nombre actual:${NC} $site_name"
    echo -e "  ${CYAN}Dominio:${NC} $domain"
    echo -e "  ${CYAN}Nombre sugerido:${NC} $suggested_name"
    echo ""
    
    read -p "¿Deseas renombrar a '$suggested_name'? (s/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        read -p "Ingresa el nuevo nombre (solo el dominio, sin .conf): " custom_name
        
        if [ -z "$custom_name" ]; then
            echo -e "${RED}Nombre no proporcionado. Operación cancelada.${NC}\n"
            return 1
        fi
        
        # Verificar que sea un dominio válido (contiene al menos un punto)
        if [[ ! "$custom_name" =~ \. ]]; then
            echo -e "${RED}El nombre debe ser un dominio válido (debe contener al menos un punto)${NC}\n"
            return 1
        fi
        
        suggested_name="$custom_name"
    fi
    
    rename_site "$site_file" "$site_name" "$domain" "$suggested_name"
    return $?
}

standardize_all_sites() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           ESTANDARIZAR TODOS LOS SITIOS${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_to_standardize=()
    local index=1
    
    # Buscar sitios no estándar
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                if ! is_standard_name "$site_name"; then
                    local domain=$(get_domain_from_config "$site_file")
                    if [ -n "$domain" ]; then
                        sites_to_standardize+=("$site_file|$site_name|$domain")
                    fi
                fi
            fi
        done
    fi
    
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                if ! is_standard_name "$site_name"; then
                    local domain=$(get_domain_from_config "$site_file")
                    if [ -n "$domain" ]; then
                        sites_to_standardize+=("$site_file|$site_name|$domain")
                    fi
                fi
            fi
        done
    fi
    
    if [ ${#sites_to_standardize[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ Todos los sitios ya tienen nombres estándar${NC}\n"
        return 0
    fi
    
    echo -e "${CYAN}Sitios que serán estandarizados:${NC}\n"
    for site_info in "${sites_to_standardize[@]}"; do
        IFS='|' read -r site_file site_name domain <<< "$site_info"
        local new_name="$domain"
        echo -e "  $index) $site_name → $new_name"
        ((index++))
    done
    
    echo ""
    read -p "¿Deseas estandarizar estos ${#sites_to_standardize[@]} sitios? (s/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    local success_count=0
    local error_count=0
    
    for site_info in "${sites_to_standardize[@]}"; do
        IFS='|' read -r site_file site_name domain <<< "$site_info"
        local new_name="$domain"
        
        echo -e "\n${CYAN}Estandarizando: $site_name → $new_name${NC}"
        if rename_site "$site_file" "$site_name" "$domain" "$new_name"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    echo -e "\n${BLUE}${BOLD}Resumen de estandarización:${NC}"
    echo -e "${GREEN}✓ Sitios estandarizados: $success_count${NC}"
    echo -e "${RED}✗ Errores: $error_count${NC}"
    echo ""
    
    return 0
}

###############################################################################
# FUNCIONES PARA CAMBIAR TIPO DE SITIO
###############################################################################

get_site_type_from_config() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        # Buscar comentario que indique el tipo
        if grep -q "# Tipo: Next.js" "$config_file" 2>/dev/null || grep -q "# Tipo: Next" "$config_file" 2>/dev/null || grep -q "# Configuración para Next.js" "$config_file" 2>/dev/null; then
            echo "nextjs"
        elif grep -q "# Tipo: API" "$config_file" 2>/dev/null || grep -q "# Configuración para API" "$config_file" 2>/dev/null; then
            echo "api"
        else
            # Detectar por características del archivo
            # Next.js tiene: gzip, client_max_body_size, _next, X-Forwarded-Host
            if grep -q "gzip on" "$config_file" 2>/dev/null && grep -q "client_max_body_size" "$config_file" 2>/dev/null && grep -q "X-Forwarded-Host" "$config_file" 2>/dev/null; then
                echo "nextjs"
            else
                echo "api"  # Por defecto
            fi
        fi
    else
        echo "api"
    fi
}

list_sites_for_type_change() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SITIOS DISPONIBLES PARA CAMBIAR TIPO${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_list=()
    local index=1
    
    # Buscar en sites-available
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                local current_type=$(get_site_type_from_config "$site_file")
                local enabled=""
                
                if [ -L "$NGINX_SITES_ENABLED/$site_name" ]; then
                    enabled="${GREEN}[ACTIVO]${NC}"
                else
                    enabled="${RED}[INACTIVO]${NC}"
                fi
                
                local type_display=""
                if [ "$current_type" = "nextjs" ]; then
                    type_display="${CYAN}[Next.js]${NC}"
                else
                    type_display="${YELLOW}[API]${NC}"
                fi
                
                echo -e "  $index) $site_name $enabled $type_display"
                if [ -n "$domain" ]; then
                    echo -e "     Dominio: $domain"
                fi
                
                sites_list+=("$site_file|$site_name|$domain|$current_type")
                ((index++))
            fi
        done
    fi
    
    # Buscar en conf.d
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                local current_type=$(get_site_type_from_config "$site_file")
                
                local type_display=""
                if [ "$current_type" = "nextjs" ]; then
                    type_display="${CYAN}[Next.js]${NC}"
                else
                    type_display="${YELLOW}[API]${NC}"
                fi
                
                echo -e "  $index) $site_name ${GREEN}[ACTIVO]${NC} $type_display"
                if [ -n "$domain" ]; then
                    echo -e "     Dominio: $domain"
                fi
                
                sites_list+=("$site_file|$site_name|$domain|$current_type")
                ((index++))
            fi
        done
    fi
    
    if [ ${#sites_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios para cambiar tipo.${NC}\n"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Total de sitios encontrados: ${#sites_list[@]}${NC}\n"
    
    CHANGE_TYPE_SITES_LIST=("${sites_list[@]}")
    return 0
}

change_site_type() {
    local site_file=$1
    local site_name=$2
    local domain=$3
    local current_type=$4
    local new_type=$5
    
    echo -e "\n${CYAN}${BOLD}Cambiando tipo de sitio:${NC}"
    echo -e "  ${CYAN}Archivo:${NC} $site_file"
    echo -e "  ${CYAN}Dominio:${NC} $domain"
    echo -e "  ${CYAN}Tipo actual:${NC} $([ "$current_type" = "nextjs" ] && echo "Next.js" || echo "API")"
    echo -e "  ${CYAN}Tipo nuevo:${NC} $([ "$new_type" = "nextjs" ] && echo "Next.js" || echo "API")"
    echo ""
    
    # Obtener puerto del archivo actual
    local port=$(grep -E "proxy_pass\s+http://localhost:" "$site_file" 2>/dev/null | head -1 | grep -oE "localhost:[0-9]+" | cut -d: -f2)
    
    if [ -z "$port" ]; then
        echo -e "${RED}Error: No se pudo determinar el puerto del sitio${NC}"
        read -p "Ingresa el puerto del sitio: " port
        if [ -z "$port" ] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Puerto inválido${NC}"
            return 1
        fi
    fi
    
    # Crear nueva configuración según el tipo
    local temp_config="/tmp/nginx_config_${site_name}_$$"
    
    case $new_type in
        nextjs)
            echo -e "${CYAN}Obteniendo configuración para Next.js...${NC}"
            local nextjs_options=$(get_nextjs_config "$domain")
            
            # Limpiar y leer los valores
            nextjs_options=$(echo "$nextjs_options" | tr -d '\n\r')
            IFS='|' read -r public_dir enable_cache max_upload enable_isr <<< "$nextjs_options"
            
            # Limpiar espacios de cada variable
            public_dir=$(echo "$public_dir" | tr -d ' ')
            enable_cache=$(echo "$enable_cache" | tr -d ' ')
            max_upload=$(echo "$max_upload" | tr -d ' ')
            enable_isr=$(echo "$enable_isr" | tr -d ' ')
            
            # Validar max_upload antes de usar
            if [ -z "$max_upload" ] || ! [[ "$max_upload" =~ ^[0-9]+$ ]] || [ "$max_upload" -le 0 ]; then
                echo -e "${YELLOW}Valor inválido para max_upload ($max_upload), usando 10MB por defecto${NC}"
                max_upload="10"
            fi
            
            # Asegurar valores por defecto si están vacíos
            public_dir="${public_dir:-/public}"
            enable_cache="${enable_cache:-s}"
            enable_isr="${enable_isr:-s}"
            
            create_nextjs_config "$temp_config" "$domain" "$port" "$public_dir" "$enable_cache" "$max_upload" "$enable_isr"
            ;;
        *)
            echo -e "${CYAN}Obteniendo configuración para API...${NC}"
            create_api_config "$temp_config" "$domain" "$port"
            ;;
    esac
    
    # Hacer backup del archivo original
    local backup_file="${site_file}.backup.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$site_file" "$backup_file" 2>/dev/null
    echo -e "${CYAN}Backup creado: $backup_file${NC}"
    
    # Reemplazar el archivo
    if sudo mv "$temp_config" "$site_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Configuración actualizada${NC}"
        
        # Validar configuración
        if sudo nginx -t &> /dev/null; then
            echo -e "${GREEN}✓ Configuración válida${NC}"
            
            # Recargar Nginx
            if sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null; then
                echo -e "${GREEN}✓ Nginx recargado${NC}"
                
                # Verificar SSL (no recrear si ya existe)
                if check_certbot_certificates "$domain"; then
                    echo -e "${GREEN}✓ El sitio ya tiene certificado SSL configurado${NC}"
                else
                    echo -e "${YELLOW}⚠ El sitio no tiene certificado SSL${NC}"
                    read -p "¿Deseas configurar SSL ahora? (s/n): " configure_ssl_now
                    if [[ "$configure_ssl_now" =~ ^[Ss]$ ]]; then
                        read -p "Ingresa el email para certificados SSL: " email
                        if [ -z "$email" ]; then
                            email="admin@$domain"
                        fi
                        configure_ssl "$domain" "$email"
                    fi
                fi
                
                echo -e "\n${GREEN}${BOLD}✓ Tipo de sitio cambiado exitosamente${NC}\n"
                return 0
            else
                echo -e "${RED}✗ Error al recargar Nginx${NC}"
                # Restaurar backup
                sudo mv "$backup_file" "$site_file" 2>/dev/null
                echo -e "${YELLOW}Configuración restaurada desde backup${NC}"
                return 1
            fi
        else
            echo -e "${RED}✗ Error en la configuración de Nginx${NC}"
            sudo nginx -t
            # Restaurar backup
            sudo mv "$backup_file" "$site_file" 2>/dev/null
            echo -e "${YELLOW}Configuración restaurada desde backup${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Error al actualizar configuración${NC}"
        return 1
    fi
}

select_site_to_change_type() {
    if [ ${#CHANGE_TYPE_SITES_LIST[@]} -eq 0 ]; then
        return 1
    fi
    
    read -p "Selecciona el número del sitio a cambiar (o 'q' para cancelar): " selection
    
    if [[ "$selection" =~ ^[Qq]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#CHANGE_TYPE_SITES_LIST[@]} ]; then
        echo -e "${RED}Selección inválida.${NC}\n"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local selected_site="${CHANGE_TYPE_SITES_LIST[$selected_index]}"
    
    IFS='|' read -r site_file site_name domain current_type <<< "$selected_site"
    
    echo -e "\n${YELLOW}${BOLD}Sitio seleccionado:${NC}"
    echo -e "  ${CYAN}Archivo:${NC} $site_file"
    echo -e "  ${CYAN}Nombre:${NC} $site_name"
    echo -e "  ${CYAN}Dominio:${NC} $domain"
    echo -e "  ${CYAN}Tipo actual:${NC} $([ "$current_type" = "nextjs" ] && echo "Next.js" || echo "API")"
    echo ""
    
    # Determinar tipo nuevo
    local new_type=""
    if [ "$current_type" = "nextjs" ]; then
        echo -e "${CYAN}El sitio actualmente es Next.js. ¿Cambiar a API?${NC}"
        read -p "Cambiar a API? (s/n): " confirm_change
        if [[ "$confirm_change" =~ ^[Ss]$ ]]; then
            new_type="api"
        else
            echo -e "${YELLOW}Operación cancelada.${NC}\n"
            return 1
        fi
    else
        echo -e "${CYAN}El sitio actualmente es API. ¿Cambiar a Next.js?${NC}"
        read -p "Cambiar a Next.js? (s/n): " confirm_change
        if [[ "$confirm_change" =~ ^[Ss]$ ]]; then
            new_type="nextjs"
        else
            echo -e "${YELLOW}Operación cancelada.${NC}\n"
            return 1
        fi
    fi
    
    change_site_type "$site_file" "$site_name" "$domain" "$current_type" "$new_type"
    return $?
}

###############################################################################
# FUNCIONES PARA REPARACIÓN SSL INTERACTIVA
###############################################################################

list_sites_for_ssl_repair() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SITIOS DISPONIBLES PARA REPARACIÓN SSL${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_list=()
    local index=1
    
    # Buscar sitios en sites-available
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                if [ -n "$domain" ]; then
                    sites_list+=("$site_file|$site_name|$domain")
                fi
            fi
        done
    fi
    
    # Buscar sitios en conf.d
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                if [ -n "$domain" ]; then
                    sites_list+=("$site_file|$site_name|$domain")
                fi
            fi
        done
    fi
    
    if [ ${#sites_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios.${NC}\n"
        return 1
    fi
    
    echo -e "${CYAN}Sitios disponibles:${NC}\n"
    for i in "${!sites_list[@]}"; do
        IFS='|' read -r site_file site_name domain <<< "${sites_list[$i]}"
        
        # Verificar rápidamente si tiene problemas
        local diagnosis=$(diagnose_ssl_issue "$domain" "$site_file")
        local has_issues=$?
        
        if [ $has_issues -eq 0 ]; then
            echo -e "  $((i+1))) $domain ($site_name) ${GREEN}[OK]${NC}"
        else
            echo -e "  $((i+1))) $domain ($site_name) ${RED}[PROBLEMAS]${NC}"
        fi
    done
    
    echo ""
    read -p "Selecciona el número del sitio a reparar (o 'q' para cancelar): " selection
    
    if [[ "$selection" =~ ^[Qq]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#sites_list[@]} ]; then
        echo -e "${RED}Selección inválida.${NC}\n"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local selected_site="${sites_list[$selected_index]}"
    
    IFS='|' read -r site_file site_name domain <<< "$selected_site"
    
    repair_site_ssl_interactive "$domain" "$site_file"
    return $?
}

list_sites_for_ssl_repair() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           SITIOS DISPONIBLES PARA REPARACIÓN SSL${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    local sites_list=()
    local index=1
    
    # Buscar sitios en sites-available
    if [ -d "$NGINX_SITES_AVAILABLE" ]; then
        for site_file in "$NGINX_SITES_AVAILABLE"/*; do
            if [ -f "$site_file" ] && [[ ! "$site_file" =~ default$ ]]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                if [ -n "$domain" ]; then
                    sites_list+=("$site_file|$site_name|$domain")
                fi
            fi
        done
    fi
    
    # Buscar sitios en conf.d
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*; do
            if [ -f "$site_file" ]; then
                local site_name=$(basename "$site_file")
                local domain=$(get_domain_from_config "$site_file")
                if [ -n "$domain" ]; then
                    sites_list+=("$site_file|$site_name|$domain")
                fi
            fi
        done
    fi
    
    if [ ${#sites_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron sitios.${NC}\n"
        return 1
    fi
    
    echo -e "${CYAN}Sitios disponibles:${NC}\n"
    for i in "${!sites_list[@]}"; do
        IFS='|' read -r site_file site_name domain <<< "${sites_list[$i]}"
        
        # Verificar rápidamente si tiene problemas
        local diagnosis=$(diagnose_ssl_issue "$domain" "$site_file")
        local has_issues=$?
        
        if [ $has_issues -eq 0 ]; then
            echo -e "  $((i+1))) $domain ($site_name) ${GREEN}[OK]${NC}"
        else
            echo -e "  $((i+1))) $domain ($site_name) ${RED}[PROBLEMAS]${NC}"
        fi
    done
    
    echo ""
    read -p "Selecciona el número del sitio a reparar (o 'q' para cancelar): " selection
    
    if [[ "$selection" =~ ^[Qq]$ ]]; then
        echo -e "${YELLOW}Operación cancelada.${NC}\n"
        return 1
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#sites_list[@]} ]; then
        echo -e "${RED}Selección inválida.${NC}\n"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local selected_site="${sites_list[$selected_index]}"
    
    IFS='|' read -r site_file site_name domain <<< "$selected_site"
    
    repair_site_ssl_interactive "$domain" "$site_file"
    return $?
}

###############################################################################
# FUNCIÓN PRINCIPAL
###############################################################################

show_main_menu() {
    echo -e "\n${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}           MENÚ PRINCIPAL${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    echo -e "${CYAN}¿Qué deseas hacer?${NC}"
    echo -e "  1) Configurar nuevos sitios para contenedores Docker"
    echo -e "  2) Eliminar un sitio existente"
    echo -e "  3) Renombrar un sitio"
    echo -e "  4) Cambiar tipo de sitio (API ↔ Next.js)"
    echo -e "  5) Estandarizar todos los sitios"
    echo -e "  6) Validar SSL de todos los sitios"
    echo -e "  7) Reparar SSL de un sitio específico"
    echo -e "  8) Solo mostrar información (sin cambios)"
    echo -e "  9) Salir"
    echo ""
    read -p "Opción (1-9): " main_option
    
    case $main_option in
        1)
            return 1  # Configurar sitios
            ;;
        2)
            return 2  # Eliminar sitio
            ;;
        3)
            return 3  # Renombrar sitio
            ;;
        4)
            return 4  # Cambiar tipo de sitio
            ;;
        5)
            return 5  # Estandarizar sitios
            ;;
        6)
            return 6  # Validar SSL
            ;;
        7)
            return 7  # Reparar SSL específico
            ;;
        8)
            return 8  # Solo información
            ;;
        9)
            return 9  # Salir
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}\n"
            return 0  # Mostrar menú de nuevo
            ;;
    esac
}

main() {
    # Limpiar pantalla al inicio
    clear
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}"
    echo -e "${BLUE}${BOLD}     ENABLE SITES - Gestión de Sitios Nginx${NC}"
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    
    # Verificar si se ejecuta como root o con sudo
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}Este script requiere permisos de administrador para algunas operaciones.${NC}"
        echo -e "${YELLOW}Se solicitará contraseña cuando sea necesario.${NC}\n"
    fi
    
    # Validar dependencias
    check_dependencies
    
    # Obtener información de Docker
    get_docker_containers
    
    # Obtener información de Nginx
    get_nginx_sites
    
    # Hacer correspondencia
    match_containers_to_sites
    
    # Menú principal
    while true; do
        show_main_menu
        local menu_result=$?
        
        case $menu_result in
            1)
                # Configurar nuevos sitios
                increment_operation
                if select_containers; then
                    process_containers
                fi
                ;;
            2)
                # Eliminar sitio
                increment_operation
                if list_sites_for_deletion; then
                    select_site_to_delete
                fi
                ;;
            3)
                # Renombrar sitio
                increment_operation
                if list_sites_for_rename; then
                    select_site_to_rename
                fi
                ;;
            4)
                # Cambiar tipo de sitio
                increment_operation
                if list_sites_for_type_change; then
                    select_site_to_change_type
                fi
                ;;
            5)
                # Estandarizar todos los sitios
                increment_operation
                standardize_all_sites
                ;;
            6)
                # Validar SSL de todos los sitios
                increment_operation
                verify_all_sites_ssl
                ;;
            7)
                # Reparar SSL de un sitio específico
                increment_operation
                list_sites_for_ssl_repair
                ;;
            8)
                # Solo mostrar información
                echo -e "\n${GREEN}Información mostrada. No se realizaron cambios.${NC}\n"
                break
                ;;
            9)
                # Salir
                echo -e "\n${GREEN}Saliendo...${NC}\n"
                break
                ;;
            0)
                # Opción inválida, continuar loop
                continue
                ;;
        esac
        
        # Preguntar si desea hacer otra operación
        echo ""
        read -p "¿Deseas realizar otra operación? (s/n): " continue_choice
        if [[ ! "$continue_choice" =~ ^[Ss]$ ]]; then
            break
        fi
    done
    
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    echo -e "${GREEN}${BOLD}Proceso completado.${NC}\n"
}

# Ejecutar función principal
main

