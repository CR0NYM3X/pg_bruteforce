 

## 1. Parámetro pre_auth_delay (Antes de validar)
Este concepto se refiere a un retardo que ocurre **antes** de que PostgreSQL verifique si la contraseña es correcta. 

* **Cómo funciona:** El servidor recibe la solicitud de conexión y, de forma indiscriminada, espera un tiempo determinado antes de procesar cualquier credencial.
* **Relación con lo anterior:** Ni `auth_delay` ni `credcheck.auth_delay_ms` funcionan así por defecto. 
* **Problema:** Es ineficiente. Castiga al usuario legítimo que escribió bien su clave, obligándolo a esperar siempre.

## 2. Parámetro post_auth_delay (Después de fallar)
Esta es la técnica que estamos implementando con `auth_delay.milliseconds` y `credcheck.auth_delay_ms`. El retardo ocurre **solo si la autenticación falló**.

* **Cómo funciona:**
    1. El usuario envía credenciales.
    2. PostgreSQL las valida.
    3. Si son **correctas**, el acceso es instantáneo.
    4. Si son **incorrectas**, el proceso "duerme" por el tiempo configurado (ej. 1000ms) antes de enviar el error `28P01 (password_authentication_failed)`.
* **Ventaja:** No afecta la experiencia de usuario de quienes ingresan los datos correctamente.

---

### Diferencias Clave: El flujo de ejecución

| Fase | Sin Delay | Con `auth_delay` (Post-Auth) | Pre-Auth Delay (Teórico) |
| :--- | :--- | :--- | :--- |
| **1. Intento de Login** | Recibido | Recibido | Recibido |
| **2. Procesamiento** | Inmediato | Inmediato | **PAUSA** |
| **3. Validación** | Éxito / Error | Éxito / Error | Éxito / Error |
| **4. Respuesta** | Inmediata | **PAUSA (Solo si falló)** | Inmediata |



---

## 3. ¿Por qué ocurre la confusión?

La confusión suele venir de dos fuentes:

1.  **Parámetros de Red vs. Aplicación:** En firewalls o balanceadores de carga, a veces se aplican retardos *Pre-Auth* para mitigar ataques de denegación de servicio (DoS), mientras que en la base de datos aplicamos *Post-Auth*.
2.  **El "Slot" de Conexión:** Tanto en `auth_delay` como en `credcheck`, aunque el delay sea *Post-Auth*, el **backend (proceso de CPU)** de Postgres ya está asignado a esa conexión. 

> **Nota de experto:** Si un atacante lanza 500 intentos fallidos simultáneos y tienes un `auth_delay` de 2 segundos, tendrás 500 procesos de Postgres "durmiendo" y consumiendo memoria/slots de conexión durante 2 segundos. Esto es lo que se conoce como un ataque de **agotamiento de recursos**.

 
