## Agregar opcion para validar 
```bash
1.-  Alcance al puerto.
2.- (no existe el usuario o la ip no esta registrada en pg_hba) FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "maria", database "postgres", no encryption
3.- (la contraseña esta mal , esto quiere decir que si existe el usuario y esta dado de alta la ip en el pg_hba) Password authentication failed


Agregarle la opcion de validar nombres de usuarios de fuerza bruta.
Agregarle opcion de contraseñas de fuerza bruta.


postgres@serv-pruebas /sysx/data17 $ psql -h 127.0.0.1 -p 5432 -d postgres -U test
Password for user test:
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  password authentication failed for user "test"

postgres@serv-pruebas /sysx/data17 $ psql -h 127.0.0.1 -p 5432 -d postgres -U maria
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "maria", database "postgres", no encryption

postgres@serv-pruebas /sysx/data17 $ psql -h 127.0.0.1 -p 5432 -d postgres -U test
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "test", database "postgres", no encryption

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

