## Agregar opcion para validar 
```bash

postgres@serv-test /sysx/data17 $ cat listado_usuarios.txt
jose
pedro
mesatierra
test
nada
maria


postgres@serv-test /sysx/data17 $ cat mis_passwords.txt
admin123

password
qwerty
1231234
root
123123




postgres@serv-test /sysx/data17 $ ./pg_bruteforce.sh -h 127.0.0.1 -p 5432 -d pepe -u listado_usuarios.txt
[*] Validando puerto 5432 en 127.0.0.1... ¡Alcanzable!
[!] Iniciando fuerza bruta de USUARIOS en DB: pepe...
[X] [.015517502s] Usuario 'jose' denegado (pg_hba.conf)
[X] [.013572638s] Usuario 'pedro' denegado (pg_hba.conf)
[X] [.013227052s] Usuario 'mesatierra' denegado (pg_hba.conf)
[->] [1.021816069s] Usuario VÁLIDO: test (Requiere contraseña)
[X] [.013939947s] Usuario 'nada' denegado (pg_hba.conf)
[X] [.014069954s] Usuario 'maria' denegado (pg_hba.conf)




postgres@serv-test /sysx/data17 $ ./pg_bruteforce.sh -h 127.0.0.1 -p 5432 -d postgres -U test -f mis_passwords.txt -T 1
[*] Validando puerto 5432 en 127.0.0.1... ¡Alcanzable!
[!] Probando contraseñas para: test (Timeout: 1s)
[!] [1.007113335s] Salto por Timeout (> 1s) en pass: 'admin123'
[!] [1.006565826s] Salto por Timeout (> 1s) en pass: 'password'
[!] [1.006572080s] Salto por Timeout (> 1s) en pass: 'qwerty'
[!] [1.006561784s] Salto por Timeout (> 1s) en pass: '1231234'
[!] [1.007149991s] Salto por Timeout (> 1s) en pass: 'root'
[->] [.028259804s] ¡PASS ENCONTRADA! -> test:123123



```

# pg_bruteforce

**pg_bruteforce** es un script ligero en Bash diseñado para realizar pruebas de fuerza bruta  sobre   PostgreSQL. Su objetivo principal es validar la eficacia de configuraciones de seguridad como `auth_delay` y la extensión `credcheck`.

## 🚀 Características

* **Validación Previa de Conectividad:** Comprueba si el puerto está abierto antes de iniciar el ataque para ahorrar tiempo.
* **Personalización Total:** Permite definir host, puerto, base de datos y usuario mediante argumentos.
* **Simulación Real:** Utiliza el binario `psql` para replicar un intento de acceso auténtico.
* **Modo Silencioso:** Soporta la omisión de la verificación de puerto mediante el flag `-S`.

## 🛠️ Requisitos

* `psql` (Cliente de PostgreSQL instalado).
* Acceso por red al servidor objetivo.
* Un archivo de texto con el listado de contraseñas.

## 💻 Uso

### 1. Crear diccionario de prueba

```bash
cat <<EOF > mis_passwords.txt
admin123
password
qwerty
1231234
root
EOF

```

### 2. Ejecutar el script

```bash
chmod +x pg_bruteforce.sh
./pg_bruteforce.sh -f mis_passwords.txt -p 5417 -h 127.0.0.1 -U test

```

### Argumentos disponibles:

* `-f`: Ruta al archivo de contraseñas (**Obligatorio**).
* `-h`: Host del servidor (Default: `127.0.0.1`).
* `-p`: Puerto de conexión (Default: `5432`).
* `-d`: Base de datos (Default: `postgres`).
* `-U`: Usuario de PostgreSQL (Default: `postgres`).
* `-S`: Saltar la validación de alcance de puerto TCP.

---

## 🛡️ Configuración de Seguridad Sugerida

Este script es ideal para probar las siguientes configuraciones en tu `postgresql.conf`:

### Opción A: Extensión nativa `auth_delay`

```ini
shared_preload_libraries = 'auth_delay'
auth_delay.milliseconds = '1000'

```

### Opción B: Extensión `credcheck` (Recomendado)

Proporciona un control más fino sobre las políticas de autenticación.

```ini
shared_preload_libraries = 'credcheck'
credcheck.auth_delay_ms = '1000'

```

---

## 🔍 Monitoreo

Para observar cómo el servidor reacciona a los intentos del script, monitorea los logs en tiempo real:

```bash
tail -f /var/lib/pgsql/data/log/postgresql.log

```

## 🔗 Referencias

* [Credcheck Extension GitHub](https://github.com/HexaCluster/credcheck)
* [Documentación Oficial auth_delay](https://www.postgresql.org/docs/current/auth-delay.html)

