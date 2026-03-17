# Ventajas de implementar Delay
 
## 1. Mitigación de Ataques de Fuerza Bruta (Brute Force)
La razón principal es que un atacante puede probar miles de combinaciones de contraseñas por segundo si el servidor responde instantáneamente.

* **Sin Delay:** Un atacante puede realizar 10,000 intentos por segundo. Si la contraseña es débil, la vulnerará en minutos.
* **Con Delay (1s):** El atacante está limitado a **1 intento por segundo por conexión**. Esto convierte un ataque de 10 minutos en uno que tardaría décadas, haciendo que el esfuerzo del atacante no sea rentable.


## 2. Prevención de Ataques de Diccionario y Relleno de Credenciales
Muchos atacantes utilizan bases de datos de contraseñas filtradas de otros sitios (Credential Stuffing). 
* Al introducir un retraso, el software de ataque (como *Hydra* o scripts personalizados) suele desconectarse por "timeout" o se vuelve extremadamente lento, forzando al atacante a desistir y buscar un objetivo más "blando" o desprotegido.

## 3. Reducción del Ruido en Logs y Carga de CPU
Cada intento de autenticación fallido genera:
1.  Escritura en el Log de errores.
2.  Uso de algoritmos de hashing (como `scrypt` o `bcrypt`) que consumen **CPU**.
Sin un retraso, un ataque masivo puede disparar el uso de CPU solo procesando intentos fallidos, afectando el rendimiento de los usuarios que ya están conectados. El delay "duerme" el proceso, reduciendo la frecuencia de estas operaciones costosas.

## 4. Ventana de Reacción para el Administrador (Detección)
El retraso le da al equipo de Seguridad (o a herramientas de monitoreo como un SIEM) **tiempo valioso**. 
* Si los intentos son instantáneos, para cuando recibes la alerta, el atacante ya probó 1 millón de claves.
* Con el delay, el flujo de ataques es constante pero lento, permitiendo que sistemas automáticos detecten la anomalía y bloqueen la IP del atacante antes de que tenga éxito.


### Riesgos que debes advertir en el manual
No todo es color de rosa. Debes incluir una nota de advertencia sobre el **Agotamiento de Conexiones**:
Como cada intento fallido mantiene un proceso de Postgres "ocupado" esperando a que pase el tiempo del delay, un atacante inteligente podría intentar llenar todos los slots de `max_connections` disponibles, provocando que los usuarios legítimos no puedan siquiera intentar entrar.


---
# Fromas de configurar un Delay
 
## 1. Módulo `auth_delay` (Nativo)
Es una herramienta estándar que viene incluida en la distribución de PostgreSQL (dentro de `contrib`). Su función es pausar el proceso del servidor por un tiempo determinado antes de reportar el error al cliente.

### Configuración
Se debe cargar en la variable `shared_preload_libraries` del archivo `postgresql.conf`:
```text
shared_preload_libraries = 'auth_delay'
auth_delay.milliseconds = '1000'
```

* **Objetivo:** Ralentizar los ataques automatizados de fuerza bruta, limitando cuántos intentos por segundo puede realizar un atacante.
* **Ventajas:** * Extremadamente ligero y estable.
    * No requiere instalaciones de terceros.
* **Desventajas:**
    * Es estático: el retraso se aplica **siempre**, independientemente de si el usuario es legítimo o un atacante persistente.
    * Consume un "slot" de conexión (backend) durante el tiempo de espera, lo que podría derivar en un DoS (Denegación de Servicio) si el atacante lanza miles de hilos simultáneos.
 

## 2. Extensión `credcheck`
`credcheck` es una extensión de terceros más robusta diseñada para aplicar políticas de cumplimiento de contraseñas y control de acceso.

### Configuración
Al igual que la anterior, requiere carga previa y configuración específica:
```text
shared_preload_libraries = 'credcheck'
credcheck.auth_delay_ms = '1000'
```

* **Objetivo:** Proporcionar una capa de seguridad integral que no solo retrasa la respuesta, sino que permite validar la complejidad de las credenciales.
* **Ventajas:**
    * **Versatilidad:** Es parte de una suite que permite definir reglas de contraseñas (longitud, caracteres especiales, etc.).
    * **Integración:** Centraliza la seguridad de credenciales en un solo lugar.
* **Desventajas:**
    * Requiere instalación externa (compilación o manejo de paquetes específicos).
    * Si solo buscas el "delay", puede ser demasiado pesada comparada con el módulo nativo.




## 4. Consideraciones Críticas de Seguridad

### El riesgo del DoS (Denegación de Servicio)
Es vital entender que si configuras un retardo de `1000ms` (1 segundo) y tienes un `max_connections = 100`, un atacante con 100 hilos puede dejar tu base de datos inaccesible para usuarios legítimos simplemente fallando el login continuamente.

> **Recomendación de Experto:**
> No utilices estos retardos como tu única línea de defensa. Combínalos con herramientas a nivel de red o sistema operativo como **Fail2Ban** (que bloquea la IP en el firewall tras N intentos) para liberar los recursos de PostgreSQL.

 

---

# Consecuencias y recomendaciones de configurar un delay 

Aunque el usuario no haya logrado entrar (porque su contraseña es incorrecta y el `auth_delay` lo tiene "congelado"), ese intento **ya está consumiendo un slot de `max_connections` y recursos del sistema.**

porque es el riesgo de seguridad más crítico de estas extensiones:

### 1. El Ciclo de "Secuestro" de la Conexión
Cuando alguien intenta conectarse, ocurre lo siguiente en el motor:

1.  **Llegada:** El proceso padre de PostgreSQL (`postmaster`) recibe la petición de red.
2.  **Bifurcación (Fork):** El `postmaster` crea un nuevo proceso hijo (un *backend*) para atender a ese usuario específico. **En este preciso instante, se resta 1 al contador de `max_connections`**.
3.  **Validación:** El nuevo proceso le pide la contraseña al usuario.
4.  **El Retraso (`auth_delay`):** Si la clave es mala, el proceso recibe la orden de "dormirse" (por ejemplo, 1000ms).
5.  **Ocupación Real:** Durante ese segundo de sueño, el proceso **sigue vivo**. Ocupa memoria RAM y mantiene el slot de `max_connections` bloqueado.
6.  **Liberación:** Solo cuando termina el tiempo del delay y el proceso envía el error al cliente, el proceso muere y el slot de `max_connections` queda libre para otra persona.


 

### 2. Por qué esto es un peligro (Escenario de Ataque)
Imagina que tu configuración es:
* `max_connections = 100`
* `auth_delay.milliseconds = 5000` (5 segundos)

Si un atacante lanza **100 intentos fallidos en menos de un segundo**, habrá creado 100 procesos de PostgreSQL que se quedarán "durmiendo" por 5 segundos. 

**Resultado:** Durante esos 5 segundos, **nadie más (ni siquiera tú como administrador)** podrá conectarse a la base de datos, porque el servidor dirá que ya llegó al límite de conexiones, aunque en `pg_stat_activity` no veas a nadie "logueado".

 

### 3. Resumen para el Manual (Sección: Advertencia Técnica)

> **¡IMPORTANTE!**
> Los parámetros de retraso de autenticación (`auth_delay` / `credcheck`) actúan **después** de que el proceso de backend ha sido asignado. 
> * **Consumo de Slots:** Cada intento fallido ocupa un lugar en `max_connections` durante la duración total del retardo.
> * **Riesgo de DoS:** Un atacante no necesita adivinar tu contraseña para tirar el servicio; solo necesita lanzar tantos intentos fallidos como conexiones permitidas tengas, saturando el servidor rápidamente.

 

### 4. ¿Cómo mitigar este "efecto secundario"?
Para que tu manual sea de un verdadero experto, debes recomendar lo siguiente:
* **No pongas tiempos excesivos:** Un delay de 1 o 2 segundos es suficiente para frenar un ataque sin dejar los slots ocupados demasiado tiempo.
* **Reservar conexiones para Superusuarios:** Mantén siempre un margen en `superuser_reserved_connections` (por defecto son 3) para que tú puedas entrar a corregir problemas aunque los slots normales estén saturados.
 

