
 
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


