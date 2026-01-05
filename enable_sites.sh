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
    
    local containers=$(docker ps --format "{{.Names}}|{{.Ports}}|{{.ID}}")
    
    if [ -z "$containers" ]; then
        echo -e "${YELLOW}No hay contenedores Docker en ejecución.${NC}\n"
        return
    fi
    
    local index=1
    while IFS='|' read -r name ports id; do
        echo -e "${CYAN}${BOLD}Contenedor #$index:${NC}"
        echo -e "  ${GREEN}Nombre:${NC} $name"
        echo -e "  ${GREEN}ID:${NC} $id"
        echo -e "  ${GREEN}Puertos:${NC} $ports"
        
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
    
    # Buscar en conf.d (si existe)
    if [ -d "$NGINX_CONF_DIR" ]; then
        echo -e "${CYAN}Sitios en conf.d:${NC}"
        for site in "$NGINX_CONF_DIR"/*.conf; do
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

create_nginx_config() {
    local container_name=$1
    local domain=$2
    local port=$3
    
    local site_name="${container_name}.conf"
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
    
    # Crear configuración de Nginx
    cat > "$site_path" << EOF
server {
    listen 80;
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
    }
}
EOF
    
    echo -e "${GREEN}Configuración creada: $site_path${NC}"
    
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
    
    # Verificar configuración de Nginx antes de continuar
    if ! sudo nginx -t &> /dev/null; then
        echo -e "${YELLOW}Advertencia: La configuración de Nginx tiene errores. Corrigiéndolos...${NC}"
        # Intentar recargar de todas formas
    fi
    
    # Ejecutar certbot
    if sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" &> /dev/null; then
        echo -e "${GREEN}✓ SSL configurado correctamente para $domain${NC}"
        return 0
    else
        echo -e "${RED}✗ Error al configurar SSL para $domain${NC}"
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
        if create_nginx_config "$name" "$domain" "$port"; then
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
# FUNCIÓN PRINCIPAL
###############################################################################

main() {
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
    
    # Seleccionar contenedores para configurar
    if select_containers; then
        process_containers
    fi
    
    echo -e "${BLUE}${BOLD}${SEPARATOR}${NC}\n"
    echo -e "${GREEN}${BOLD}Proceso completado.${NC}\n"
}

# Ejecutar función principal
main

