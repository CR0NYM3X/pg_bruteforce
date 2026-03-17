
 
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

 
