Esta es la "prueba de fuego" del auditor. Si no conoces ni un solo usuario ni una sola contraseña, la estrategia se basa en **comparar tiempos de respuesta ante diferentes tipos de errores**.

PostgreSQL responde en tiempos distintos dependiendo de **qué tan profundo** en el sistema llega la solicitud antes de fallar.

### La Estrategia de los "Tres Tiempos"

Usaremos tres intentos con datos que *sabemos* que van a fallar para mapear el comportamiento del servidor:

#### 1. Tiempo de Puerto (Línea Base de Red)

Hacemos un intento de conexión a un servicio que NO es Postgres o simplemente medimos el saludo TCP.

* **Comando:** `timeout 1s bash -c "echo > /dev/tcp/$HOST/$PORT"`
* **Resultado:** Si tarda **0.001s**, esa es tu velocidad real de red.

#### 2. Tiempo de Usuario Inexistente (Filtro de Catálogo)

Intentamos conectar con un usuario que es 99% probable que no exista (ej. `usr_random_998822`).

* **Comando:** `psql -U usr_random_998822 -h $HOST`
* **Comportamiento:** Si el servidor responde instantáneamente `role "..." does not exist` en **0.010s**, significa que el servidor **no aplica delay a usuarios que no existen**.

#### 3. Tiempo de Usuario Probable (Filtro de Autenticación)

Intentamos conectar con el usuario `postgres` y una contraseña malísima.

* **Comando:** `psql -U postgres -h $HOST` (con pass errónea).
* **El Hallazgo:** Si este intento tarda **1.005s** o **2.000s**, mientras que el anterior tardó **0.010s**, acabas de confirmar que:
1. El usuario `postgres` **SÍ existe**.
2. El servidor tiene un **delay configurado** específicamente para proteger la autenticación.



---

### Análisis de Resultados (La Matriz de Verdad)

| Tiempo con usuario `postgres` | Tiempo con usuario `inventado` | Conclusión |
| --- | --- | --- |
| **0.010s** | **0.010s** | **No hay delay.** El servidor es un blanco rápido. |
| **1.000s** | **1.000s** | **Delay Global.** El servidor aplica `auth_delay` a todo intento fallido, exista o no el usuario. |
| **2.000s** | **0.015s** | **Delay Selectivo.** El servidor delata que el usuario existe porque solo aplica el retraso cuando el nombre de usuario es válido. |
| **Aumenta (1s -> 2s -> 4s)** | **Cualquiera** | **Defensa Activa (Credcheck).** Tienes una extensión penalizando cada fallo. |

---

### ¿Cómo aplicar esto a tu herramienta?

Si no sabes nada del servidor, corre este mini-test de 2 líneas:

1. `time PGPASSWORD=123 psql -h IP -U usuario_que_no_existe -d postgres`
2. `time PGPASSWORD=123 psql -h IP -U postgres -d postgres`

**Si el tiempo del segundo comando es mayor que el del primero, ¡BINGO!:**

* Ya sabes que el usuario es `postgres`.
* Ya sabes que hay un delay.
* Configura tu herramienta: `./pg_bruteforce.sh -U postgres -f pass.txt -T [el_tiempo_que_mediste]`.

### El Truco Maestro: El Bypass de Identificación

Si descubres que el servidor solo aplica delay a usuarios que existen, puedes usar tu script en modo `-u` (usuarios) con un `-T` muy bajo (ej. `-T 0.5`).

* Los usuarios que **no existen** te darán error rápido `[X]`.
* Los usuarios que **sí existen** te darán `[!] TIMEOUT`.

¡Felicidades! Acabas de encontrar usuarios válidos saltándote la espera, porque el hecho de que el servidor "se quede pensando" es la prueba de que el usuario es real.
 
