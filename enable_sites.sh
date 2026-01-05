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
    
    echo -e "\n${CYAN}${BOLD}Configuración adicional para Next.js:${NC}\n"
    
    # Preguntar por directorio público
    read -p "¿Ruta del directorio público? [Por defecto: /public]: " public_dir
    public_dir="${public_dir:-/public}"
    
    # Preguntar por caché de assets estáticos
    echo ""
    read -p "¿Habilitar caché de assets estáticos? (s/n) [Por defecto: s]: " enable_cache
    enable_cache="${enable_cache:-s}"
    
    # Preguntar por tamaño máximo de upload
    echo ""
    read -p "¿Tamaño máximo de upload en MB? [Por defecto: 10]: " max_upload
    max_upload="${max_upload:-10}"
    
    # Preguntar por ISR (Incremental Static Regeneration)
    echo ""
    read -p "¿Habilitar soporte para ISR (Incremental Static Regeneration)? (s/n) [Por defecto: s]: " enable_isr
    enable_isr="${enable_isr:-s}"
    
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
        site_type=$(select_site_type | tr -d '\n\r ')
        echo ""
        if [ "$site_type" = "nextjs" ]; then
            echo -e "${GREEN}✓ Tipo seleccionado: Web Next.js${NC}"
        else
            echo -e "${GREEN}✓ Tipo seleccionado: API/Backend${NC}"
        fi
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
            IFS='|' read -r public_dir enable_cache max_upload enable_isr <<< "$nextjs_options"
            
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
        
        # Verificar que la configuración SSL esté correcta
        if sudo nginx -t &> /dev/null; then
            echo -e "${GREEN}✓ Configuración de Nginx validada${NC}"
            sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
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
            IFS='|' read -r public_dir enable_cache max_upload enable_isr <<< "$nextjs_options"
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
    echo -e "  6) Solo mostrar información (sin cambios)"
    echo -e "  7) Salir"
    echo ""
    read -p "Opción (1-7): " main_option
    
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
            return 6  # Solo información
            ;;
        7)
            return 7  # Salir
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
                # Solo mostrar información
                echo -e "\n${GREEN}Información mostrada. No se realizaron cambios.${NC}\n"
                break
                ;;
            7)
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

# Ejecutar función principal.
main

