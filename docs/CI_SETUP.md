# Configurar Jenkins (CI/CD)

Guía de los pasos que hay que hacer **a mano** para que Jenkins compile y pruebe cada push y cada PR (incluidos los de Dependabot), y genere el **release firmado** en `main`.

## Cómo está armado

```
GitHub ──webhook──► Jenkins (infra/jenkins, Docker Compose)
                       │ usa el Docker de la computadora (docker.sock)
                       ▼
                    Contenedor de build (ci/Dockerfile: JDK 25 + Android SDK 37)
                       └─ Jenkinsfile: Lint → Unit Tests → Build Debug → Build Release → Publicar en GitHub (las dos últimas solo en main)
```

GitHub Actions **sigue funcionando en paralelo**. Las pruebas de la base de datos (Supabase) y el análisis de seguridad (CodeQL, MobSF, Gitleaks) **solo** corren en Actions.

## 1. Levantar Jenkins

Requiere Docker (Docker Desktop en Windows/macOS).

```bash
cd infra/jenkins
cp .env.example .env          # en PowerShell: Copy-Item .env.example .env
```

Llena `DOCKER_GID` en `.env`:

- **Docker Desktop (Windows/macOS):** normalmente `DOCKER_GID=0`. Para comprobarlo:
  `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine stat -c %g /var/run/docker.sock`
- **Linux:** `getent group docker | cut -d: -f3`

```bash
docker compose up -d --build
```

Jenkins queda en **http://localhost:8080** (o el puerto que pongas en `JENKINS_PORT` dentro de `.env`, si el 8080 ya está ocupado, por ejemplo por XAMPP). Solo es accesible desde esa computadora, a propósito.

El pipeline `monchosos` ya viene creado (`infra/jenkins/jobs/monchosos/config.xml`): revisa GitHub cada 5 minutos y solo construye **`main` y los PRs** del propio repo, nunca de forks. `develop` y las ramas de trabajo no se compilan solas porque ya se prueban en su PR. Solo le falta la credencial `github-token` (paso 3). Puedes saltarte el paso 4.

## 2. Contraseña inicial

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

1. Entra a http://localhost:8080 y pega la contraseña.
2. Elige **"Install suggested plugins"**. Los que necesita el pipeline ya vienen en la imagen.
3. Crea tu usuario administrador **con una contraseña fuerte**.
4. Ve a **Manage Jenkins → Security** y verifica que **"Allow users to sign up"** esté **desactivado**. Jenkins controla Docker, así que quien entre puede controlar la computadora.

## 3. Credenciales

Ve a **Manage Jenkins → Credentials → System → Global credentials → Add Credentials** y crea estas, con **exactamente** estos IDs:

| ID | Tipo | Contenido |
|---|---|---|
| `android-keystore` | Secret file | El archivo `.jks` de la llave de release |
| `keystore-password` | Secret text | Contraseña del keystore |
| `key-alias` | Secret text | Alias de la llave |
| `key-password` | Secret text | Contraseña de la llave |
| `google-web-client-id` | Secret text | ID de cliente web de Google (`…apps.googleusercontent.com`) |
| `supabase-url` | Secret text | `https://<proyecto>.supabase.co` |
| `supabase-publishable-key` | Secret text | Llave `sb_publishable_…`. **Nunca** la `service_role`/`secret` |
| `github-token` | Username with password | Usuario de GitHub + *Personal Access Token* (permisos `repo` y `admin:repo_hook`) |

Mientras no exista `android-keystore`, el build de `main` **omite** Build Release y Publicar en GitHub (lo avisa en el log) y queda en verde. En cuanto cargues la llave, cada build de `main` genera el APK y el AAB firmados y crea el release `v1.0.<número de build>` en GitHub con el APK. Para eso `github-token` necesita permiso de escritura en el repositorio (`repo` en un token clásico, o *Contents: Read and write* en uno fine-grained).

### Crear la llave de release (una sola vez)

```bash
keytool -genkeypair -v -keystore monchosos-release.jks -alias monchosos \
        -keyalg RSA -keysize 2048 -validity 10000
```

- **Guarda el `.jks` y sus contraseñas en un lugar seguro, fuera del repositorio** (por ejemplo, un gestor de contraseñas). Si se pierde, no podrás publicar actualizaciones de la app en Play Store.
- **Registra su SHA-1 en Google Cloud,** o el login con Google no funcionará en el release. Obtén el SHA-1 con `keytool -list -v -keystore monchosos-release.jks -alias monchosos`; luego, en Google Cloud Console → Clientes, crea **otro** cliente **Android** con el paquete `com.monchosos.app` y ese SHA-1.

## 4. Crear el pipeline

1. **New Item →** nombre `monchosos` **→ Multibranch Pipeline**.
2. **Branch Sources → Add source → GitHub**:
   - Credentials: `github-token`
   - Repository HTTPS URL: `https://github.com/CiscoPaquitoTracer/Gestor_Hamburgueseria`
   - Behaviours: deja descubrir ramas y PRs (incluye los de Dependabot).
3. **Build Configuration:** `by Jenkinsfile`, script path `Jenkinsfile`.
4. Guarda. Jenkins escanea el repositorio y crea un job por cada rama y PR.

## 5. Webhook de GitHub

Para que Jenkins compile en cuanto haya un push, sin esperar:

1. Jenkins corre en tu computadora, así que necesitas un túnel: `ngrok http 8080`. Copia la URL `https://….ngrok-free.app`.
2. En GitHub, ve a **Settings → Webhooks → Add webhook**:
   - Payload URL: `https://<url-de-ngrok>/github-webhook/` (**con la barra final**)
   - Content type: `application/json`
   - Eventos: **Pushes** y **Pull requests**

Mientras el túnel esté abierto, Jenkins es accesible desde internet, así que el usuario administrador y el registro desactivado (paso 2) son obligatorios.

**Alternativa sin túnel:** en el Multibranch Pipeline, usa **Scan Multibranch Pipeline Triggers → Periodically if not otherwise run → 5 minutes**. Jenkins revisará GitHub cada 5 minutos y nada queda expuesto.

## 6. Exigir que Jenkins pase antes de mezclar

En GitHub, ve a **Settings → Rules** (o Branches) y edita la regla de `main` y `develop`:

- **Require status checks to pass:** agrega el check de Jenkins (`continuous-integration/jenkins/pr-merge` o el nombre que aparezca después del primer build). Así **los PR de Dependabot** tampoco se pueden mezclar si Jenkins falla.
- Mantén también el check de Actions **"Base de datos (migraciones, linter y pruebas)"**, porque eso no lo prueba Jenkins.

## 7. Solución de problemas

| Síntoma | Causa y solución |
|---|---|
| `permission denied` en `/var/run/docker.sock` | `DOCKER_GID` incorrecto en `.env`. Revísalo con el comando del paso 1 y ejecuta `docker compose up -d` |
| `SDK location not found` o falta una plataforma | Los `ARG` de `ci/Dockerfile` (`ANDROID_COMPILE_SDK`, `ANDROID_BUILD_TOOLS`) no coinciden con `compileSdk` |
| `$'\r': command not found` | `gradlew` con finales de Windows. `.gitattributes` ya lo evita; si pasa, revisa que no se haya cambiado |
| `Gradle build daemon disappeared unexpectedly` | Se acabó la memoria de Docker por dos builds simultáneos. `infra/jenkins/init.groovy.d/ejecutores.groovy` deja un solo build a la vez; si cambiaste la imagen, ejecuta `docker compose up -d --build` |
| El primer build tarda mucho | Normal: descarga Gradle y dependencias. Los siguientes reutilizan `.gradle-home` del workspace |
| El release no inicia sesión con Google | Falta registrar el SHA-1 de la llave de release en Google Cloud (paso 3) |
| El release no se conecta a Supabase | Faltan las credenciales `supabase-url` o `supabase-publishable-key` |

## Mantenimiento

- Si cambias `infra/jenkins/jobs/monchosos/config.xml`, Jenkins **no** lo toma solo, porque la imagen solo lo copia la primera vez. Cópialo y reinicia: `docker compose cp jobs/monchosos/config.xml jenkins:/var/jenkins_home/jobs/monchosos/config.xml` y `docker compose restart jenkins` (en Git Bash, con `MSYS_NO_PATHCONV=1`).

- **Dependabot** abre PRs para las imágenes de `ci/` e `infra/jenkins/`. Solo actualiza el `FROM`; las versiones del SDK (`ARG`) se cambian a mano cuando cambie `compileSdk` en `app/build.gradle.kts`.
- Para actualizar Jenkins: acepta el PR de Dependabot y luego ejecuta `docker compose up -d --build` en `infra/jenkins`. Los datos están en el volumen `jenkins_home` y no se pierden.
