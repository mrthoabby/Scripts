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
    # Nota: Inicialmente el bloque HTTP no tiene redirección para permitir validación de Certbot
    # Certbot agregará la redirección automáticamente después de configurar SSL
    cat > "$site_path" << EOF
# Configuración HTTP (Certbot agregará redirección a HTTPS después de configurar SSL)
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    # Este bloque permite la validación de Certbot
    # Certbot modificará este bloque para agregar redirección a HTTPS
    
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

# Configuración HTTPS (será completada por Certbot)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # Certificados SSL (serán configurados por Certbot)
    # ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    # include /etc/letsencrypt/options-ssl-nginx.conf;
    # ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
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
    echo -e "${CYAN}Ejecutando Certbot para obtener certificado SSL...${NC}"
    if sudo certbot --nginx -d "$domain" \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --redirect \
        --keep-until-expiring 2>&1 | tee /tmp/certbot_${domain}.log; then
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
        echo -e "${YELLOW}Revisa los logs en /tmp/certbot_${domain}.log${NC}"
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
    
    # Buscar en conf.d
    if [ -d "$NGINX_CONF_DIR" ]; then
        for site_file in "$NGINX_CONF_DIR"/*.conf; do
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
                if sudo certbot delete --cert-name "$cert_name" --non-interactive 2>/dev/null; then
                    echo -e "${GREEN}✓ Certificados SSL eliminados${NC}"
                    success_steps+=("Certificados SSL eliminados")
                else
                    echo -e "${YELLOW}⚠ No se pudieron eliminar los certificados automáticamente${NC}"
                    echo -e "${YELLOW}  Puedes eliminarlos manualmente con: sudo certbot delete --cert-name $cert_name${NC}"
                    errors+=("Error al eliminar certificados SSL")
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
        echo -e "\n${RED}Errores encontrados:${NC}"
        for error in "${errors[@]}"; do
            echo -e "  ✗ $error"
        done
        return 1
    else
        echo -e "\n${GREEN}${BOLD}✓ Sitio eliminado correctamente${NC}\n"
        return 0
    fi
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
    echo -e "  3) Solo mostrar información (sin cambios)"
    echo -e "  4) Salir"
    echo ""
    read -p "Opción (1-4): " main_option
    
    case $main_option in
        1)
            return 1  # Configurar sitios
            ;;
        2)
            return 2  # Eliminar sitio
            ;;
        3)
            return 3  # Solo información
            ;;
        4)
            return 4  # Salir
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}\n"
            return 0  # Mostrar menú de nuevo
            ;;
    esac
}

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
    
    # Menú principal
    while true; do
        show_main_menu
        local menu_result=$?
        
        case $menu_result in
            1)
                # Configurar nuevos sitios
                if select_containers; then
                    process_containers
                fi
                ;;
            2)
                # Eliminar sitio
                if list_sites_for_deletion; then
                    select_site_to_delete
                fi
                ;;
            3)
                # Solo mostrar información
                echo -e "\n${GREEN}Información mostrada. No se realizaron cambios.${NC}\n"
                break
                ;;
            4)
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

