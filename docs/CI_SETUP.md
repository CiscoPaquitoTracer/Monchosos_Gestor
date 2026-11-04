# Configurar Jenkins (CI/CD)

En este repo **todo el CI/CD corre en Jenkins**: no hay GitHub Actions. GitHub queda como repositorio, con PRs, reglas de ramas, auto-merge, Dependabot, Releases y Pages.

Esta guía junta los pasos que hay que hacer **a mano** para que Jenkins pruebe cada PR (incluidos los de Dependabot) y genere el **release firmado** y la página de descarga en `main`.

## Cómo está armado

```
GitHub ◄── Jenkins revisa cada 5 min ── Jenkins (infra/jenkins, Docker Compose, http://localhost:8081)
                                           │ usa el Docker de la computadora (docker.sock)
                                           ▼
                                        Contenedor de build (ci/Dockerfile: Flutter + Android SDK + herramientas)
                                           └─ Jenkinsfile
```

| Etapa | Cuándo | Qué hace |
|---|---|---|
| Configuración | Siempre | Genera `env.json` desde las credenciales (la app no arranca sin él) |
| Dependencias | Siempre | `flutter pub get` |
| Análisis | Siempre | `dart format --set-exit-if-changed` y `flutter analyze` |
| Pruebas | Siempre | `flutter test` |
| Base de datos | `main`, PRs a `main` y cuando cambia `supabase/` | `supabase db start`, `supabase db lint` y `supabase/tests/pruebas.sql` |
| Seguridad | Siempre | Gitleaks (secretos), mobsfscan (Android) y osv-scanner (`pubspec.lock`) |
| Build Debug | Siempre | `flutter build apk --debug` (se archiva el APK) |
| Build Release | `main` con la llave | APK y AAB firmados, versión `2.0.<build>` con build-number `100 + build` |
| Publicar en GitHub | `main` con la llave | Release `v2.0.<build>` con `monchosos-2.0.<build>.apk` y `monchosos.apk` |
| Página | `main`, si cambió `pagina/` o si `gh-pages` no existe | Sube `pagina/` a la rama `gh-pages` |
| iOS | `main`, si `IOS_HABILITADO=true` | Necesita un agente Mac con la etiqueta `macos` (pendiente) |

El resultado llega al PR como el check **`continuous-integration/jenkins/pr-merge`**. Es el **único** check obligatorio.

**Importante:** si la laptop o Docker Desktop están apagados, no corre el CI: no se puede fusionar nada y no sale ningún release.

## 1. Levantar Jenkins

Requiere Docker Desktop.

```bash
cd infra/jenkins
cp .env.example .env          # en PowerShell: Copy-Item .env.example .env
```

En `.env`: `DOCKER_GID=0` (Docker Desktop) y `JENKINS_PORT=8081` (el 8080 lo ocupa XAMPP).

```bash
docker compose up -d --build
```

Jenkins queda en **http://localhost:8081**, solo accesible desde esta computadora, a propósito.

> **Si Jenkins ya estaba instalado** (el del proyecto Kotlin), no hace falta reinstalarlo. Solo agrega el job `monchosos-flutter` (paso 4).

## 2. Contraseña inicial (solo en una instalación nueva)

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

1. Entra a http://localhost:8081 y pega la contraseña.
2. Elige **"Install suggested plugins"**. Los que necesita el pipeline ya vienen en la imagen.
3. Crea tu usuario administrador **con una contraseña fuerte**.
4. En **Manage Jenkins → Security**, verifica que **"Allow users to sign up"** esté **desactivado**. Jenkins controla Docker, así que quien entre puede controlar la computadora.

## 3. Credenciales

En **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**, con **exactamente** estos IDs:

| ID | Tipo | Contenido |
|---|---|---|
| `android-keystore` | Secret file | El `.jks` de la llave de release (**la misma** de la app Kotlin) |
| `keystore-password` | Secret text | Contraseña del keystore |
| `key-alias` | Secret text | `monchosos` |
| `key-password` | Secret text | Contraseña de la llave |
| `google-web-client-id` | Secret text | ID de cliente web de Google (`…apps.googleusercontent.com`) |
| `supabase-url` | Secret text | `https://<proyecto>.supabase.co` |
| `supabase-publishable-key` | Secret text | Llave `sb_publishable_…`. **Nunca** la `service_role`/`secret` |
| `github-token` | Username with password | Usuario de GitHub + token con **Contents: Read and write** en este repo |

- Si `github-token` es un token *fine-grained*, agrégale el repo `Monchosos_Gestor` en GitHub → Settings → Developer settings → Personal access tokens. Sin eso, Jenkins no ve el repo, no manda el check a los PRs y no puede crear releases.
- Mientras no exista `android-keystore`, el build de `main` **omite** el release (lo avisa en el log) y queda en verde.
- **La llave tiene que ser la misma de la app Kotlin.** Si cambia, los teléfonos no aceptan la actualización.

## 4. Crear el job `monchosos-flutter`

El job viene en `infra/jenkins/jobs/monchosos-flutter/config.xml`. Solo descubre `main` y los PRs del propio repo, nunca de forks, y revisa GitHub cada 5 minutos (sin webhook ni túnel).

**En un Jenkins que ya existe**, cópialo y reinicia (en Git Bash, desde `infra/jenkins`):

```bash
MSYS_NO_PATHCONV=1 docker compose exec jenkins mkdir -p /var/jenkins_home/jobs/monchosos-flutter
MSYS_NO_PATHCONV=1 docker compose cp jobs/monchosos-flutter/config.xml jenkins:/var/jenkins_home/jobs/monchosos-flutter/config.xml
docker compose restart jenkins
```

En una instalación nueva, la imagen lo copia sola la primera vez.

El job de Kotlin (`monchosos`) y este comparten el único ejecutor y hacen fila. Cuando se retire el proyecto Kotlin, borra su job.

## 5. Reglas de ramas en GitHub

**Settings → Rules → New branch ruleset**, una para `main` y otra para `develop`:

- **Enforcement:** Active.
- **Restrict deletions**, **Block force pushes** y **Require a pull request before merging**, con 0 aprobaciones.
- **Require status checks to pass** con un solo check: `continuous-integration/jenkins/pr-merge`. Aparece en el buscador después del primer build de Jenkins en un PR; si no, escríbelo a mano.
- "Require branches to be up to date" **sin marcar**.
- **No agregues checks de Actions:** aquí no hay Actions, y un check que nadie manda deja los PRs bloqueados para siempre.

Además:

- **Settings → General → Pull Requests:** marca **Allow auto-merge**.
- **Settings → Pages → Source:** **Deploy from a branch**, rama `gh-pages`, carpeta `/ (root)`. La rama la crea Jenkins en el primer build de `main`.

Flujo: `francisco` → PR → `develop` → PR → `main`. `main` y `develop` solo cambian por PR.

## 6. Solución de problemas

| Síntoma | Causa y solución |
|---|---|
| `permission denied` en `/var/run/docker.sock` | `DOCKER_GID` incorrecto en `.env`. Revísalo y ejecuta `docker compose up -d` |
| Falta una plataforma, el NDK o CMake | Los `ARG` de `ci/Dockerfile` no coinciden con lo que pide la versión de Flutter |
| `$'\r': command not found` | Un script con finales de Windows. `.gitattributes` lo evita; revisa que no se haya cambiado |
| `Gradle build daemon disappeared unexpectedly` | Se acabó la memoria de Docker. `init.groovy.d/ejecutores.groovy` deja un solo build a la vez |
| El primer build tarda mucho | Normal: construye la imagen y descarga Gradle y paquetes. Los cachés quedan en `jenkins_home/caches/monchosos-flutter` |
| La etapa Base de datos no conecta | Desde el contenedor de build la base está en `host.docker.internal:54322`, no en `127.0.0.1` |
| El PR se queda esperando el check | Jenkins apagado, `github-token` sin acceso al repo, o el nombre del check en la regla no coincide |
| El release no inicia sesión con Google | Falta registrar el SHA-1 de la llave en Google Cloud |
| El release no se conecta a Supabase | Faltan `supabase-url` o `supabase-publishable-key` |

## Mantenimiento

- Si cambias `jobs/monchosos-flutter/config.xml`, Jenkins **no** lo toma solo: cópialo a mano como en el paso 4.
- **Dependabot** abre PRs semanales a `develop` (paquetes `pub`, Gradle de `android/` y las imágenes de `ci/` e `infra/jenkins/`). Solo actualiza el `FROM`; los `ARG` del Dockerfile (Flutter, SDK, NDK, herramientas) se cambian a mano.
- Para actualizar Jenkins: acepta el PR de Dependabot y ejecuta `docker compose up -d --build` en `infra/jenkins`. Los datos están en el volumen `jenkins_home`.
