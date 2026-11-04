// CI/CD de Monchosos (Flutter) en Jenkins. Todo el CI/CD corre aquí: no hay GitHub Actions.
//
// En cada PR: análisis, pruebas, base de datos (si aplica), seguridad y APK debug.
// En main:    además, el release firmado, el release en GitHub y la página de descarga.
// El resultado llega al PR como el check continuous-integration/jenkins/pr-merge.
//
// Guía: docs/CI_SETUP.md. Ojo: dentro de sh '''…''' NO se usan barras invertidas para
// continuar líneas (rompen el script).
pipeline {
    agent {
        dockerfile {
            filename 'Dockerfile'
            dir 'ci'
            // Socket de Docker del host: la base de datos y Gitleaks corren en contenedores hermanos.
            args '-v /var/run/docker.sock:/var/run/docker.sock --group-add 0'
        }
    }

    environment {
        // Cachés fuera del workspace (así no los revisan dart format ni flutter analyze) y
        // compartidos entre ramas: con un solo ejecutor no hay builds simultáneos.
        CACHES = "${JENKINS_HOME}/caches/monchosos-flutter"
        HOME = "${CACHES}/home"
        PUB_CACHE = "${CACHES}/pub"
        GRADLE_USER_HOME = "${CACHES}/gradle"
        GRADLE_OPTS = '-Dorg.gradle.daemon=false'
        REPO = 'CiscoPaquitoTracer/Monchosos_Gestor'
        // Primera versión Flutter: 2.0.N con build-number > 8 (la última Kotlin fue la v1.0.8,
        // versionCode 8), para que se instale encima como actualización.
        BUILD_NAME = "2.0.${BUILD_NUMBER}"
        BUILD_NUMBER_APP = "${100 + (BUILD_NUMBER as int)}"
        GITLEAKS_IMAGEN = 'zricethezav/gitleaks:v8.30.1'
    }

    options {
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15'))
        disableConcurrentBuilds()
        timestamps()
    }

    stages {
        stage('Configuración') {
            steps {
                // env.json (ignorado por git): la app no arranca sin él, también en debug.
                // La llave publishable no es secreta (la seguridad la da RLS), pero no se versiona.
                withCredentials([
                    string(credentialsId: 'google-web-client-id', variable: 'GOOGLE_WEB_CLIENT_ID'),
                    string(credentialsId: 'supabase-url', variable: 'SUPABASE_URL'),
                    string(credentialsId: 'supabase-publishable-key', variable: 'SUPABASE_PUBLISHABLE_KEY'),
                ]) {
                    sh '''
                        set -eu
                        mkdir -p "$HOME" "$PUB_CACHE" "$GRADLE_USER_HOME"
                        printf '{"SUPABASE_URL": "%s", "SUPABASE_PUBLISHABLE_KEY": "%s", "GOOGLE_WEB_CLIENT_ID": "%s", "GOOGLE_IOS_CLIENT_ID": ""}' "$SUPABASE_URL" "$SUPABASE_PUBLISHABLE_KEY" "$GOOGLE_WEB_CLIENT_ID" > env.json
                    '''
                }
                sh 'flutter --version'
            }
        }

        stage('Dependencias') {
            steps {
                sh 'flutter pub get'
            }
        }

        stage('Análisis') {
            steps {
                sh 'dart format --output=none --set-exit-if-changed lib test'
                sh 'flutter analyze'
            }
        }

        stage('Pruebas') {
            steps {
                sh 'flutter test --reporter expanded'
            }
        }

        // Migraciones, linter de la BD y supabase/tests/pruebas.sql en un Postgres de Supabase
        // desechable (ci/base_de_datos.sh). Corre en main, en los PRs a main y cuando cambia supabase/.
        stage('Base de datos') {
            when {
                anyOf {
                    branch 'main'
                    changeRequest target: 'main'
                    changeset 'supabase/**'
                }
            }
            steps {
                sh 'sh ci/base_de_datos.sh probar'
            }
            post {
                always {
                    sh 'sh ci/base_de_datos.sh limpiar'
                }
            }
        }

        stage('Seguridad') {
            steps {
                // Secretos en todo el historial de git. --volumes-from: el contenedor de Gitleaks ve
                // el mismo workspace que este (el workspace no existe como carpeta del host).
                sh 'docker run --rm --volumes-from "$(hostname)" -w "$WORKSPACE" "$GITLEAKS_IMAGEN" detect --source "$WORKSPACE" --no-banner --redact'
                // Configuración insegura en el código Android (manifiesto, red, etc.).
                sh 'mobsfscan --config .mobsf android/'
                // Dependencias de Dart con vulnerabilidades conocidas.
                sh 'osv-scanner scan source --lockfile=pubspec.lock'
            }
        }

        stage('Build Debug') {
            steps {
                sh 'flutter build apk --debug --dart-define-from-file=env.json'
                archiveArtifacts artifacts: 'build/app/outputs/flutter-apk/app-debug.apk', fingerprint: true
            }
        }

        stage('Build Release') {
            when {
                allOf {
                    branch 'main'
                    // Sin la llave en Jenkins se omite el release (main queda en verde y lo avisa).
                    expression { hayLlaveDeRelease() }
                }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'android-keystore', variable: 'KEYSTORE_FILE'),
                    string(credentialsId: 'keystore-password', variable: 'KEYSTORE_PASSWORD'),
                    string(credentialsId: 'key-alias', variable: 'KEY_ALIAS'),
                    string(credentialsId: 'key-password', variable: 'KEY_PASSWORD'),
                ]) {
                    // La MISMA llave que la app Kotlin: si cambia, los teléfonos no aceptan la actualización.
                    sh '''
                        set -eu
                        printf 'storeFile=%s\\nstorePassword=%s\\nkeyAlias=%s\\nkeyPassword=%s\\n' "$KEYSTORE_FILE" "$KEYSTORE_PASSWORD" "$KEY_ALIAS" "$KEY_PASSWORD" > android/key.properties
                        flutter build appbundle --release --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER_APP" --dart-define-from-file=env.json
                        flutter build apk --release --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER_APP" --dart-define-from-file=env.json
                    '''
                }
                archiveArtifacts artifacts: 'build/app/outputs/bundle/release/*.aab, build/app/outputs/flutter-apk/app-release.apk',
                    fingerprint: true
            }
            post {
                always {
                    sh 'rm -f android/key.properties'
                }
            }
        }

        // CD: cada build de main con llave se publica como release de GitHub (tag v2.0.N) con el APK
        // firmado. La página de descarga apunta a releases/latest/download/monchosos.apk.
        stage('Publicar en GitHub') {
            when {
                allOf {
                    branch 'main'
                    expression { hayLlaveDeRelease() }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-token',
                        usernameVariable: 'GH_USUARIO', passwordVariable: 'GH_TOKEN')]) {
                    sh '''
                        set -eu
                        APK="monchosos-$BUILD_NAME.apk"
                        cp build/app/outputs/flutter-apk/app-release.apk "$APK"
                        printf '{"tag_name": "v%s", "target_commitish": "%s", "name": "Monchosos %s", "make_latest": "true", "body": "APK firmado por Jenkins (build %s de main)."}' "$BUILD_NAME" "$GIT_COMMIT" "$BUILD_NAME" "$BUILD_NUMBER" > release-pedido.json
                        curl -fsS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" --data @release-pedido.json -o release.json "https://api.github.com/repos/$REPO/releases"
                        ID=$(grep -m1 -o '"id": *[0-9]*' release.json | grep -o '[0-9]*$')
                        curl -fsS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/vnd.android.package-archive" --data-binary @"$APK" -o /dev/null "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=$APK"
                        curl -fsS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/vnd.android.package-archive" --data-binary @"$APK" -o /dev/null "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=monchosos.apk"
                        echo "Publicado: https://github.com/$REPO/releases/tag/v$BUILD_NAME"
                    '''
                }
            }
        }

        // Página de descarga en la rama gh-pages (GitHub → Settings → Pages → Deploy from a branch).
        // Solo cuando cambia pagina/ o si gh-pages todavía no existe. Es la única rama con force-push.
        stage('Página') {
            when {
                allOf {
                    branch 'main'
                    anyOf {
                        changeset 'pagina/**'
                        expression { !existeGhPages() }
                    }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-token',
                        usernameVariable: 'GH_USUARIO', passwordVariable: 'GH_TOKEN')]) {
                    sh '''
                        set -eu
                        rm -rf .pagina-publicar
                        cp -r pagina .pagina-publicar
                        cd .pagina-publicar
                        touch .nojekyll
                        git init -q -b gh-pages
                        git -c user.name="Jenkins" -c user.email="jenkins@localhost" add -A
                        git -c user.name="Jenkins" -c user.email="jenkins@localhost" commit -q -m "Página de descarga (build $BUILD_NUMBER)"
                        git push -q --force "https://$GH_USUARIO:$GH_TOKEN@github.com/$REPO.git" HEAD:gh-pages
                        echo "Página: https://ciscopaquitotracer.github.io/Monchosos_Gestor/"
                    '''
                }
            }
            post {
                always {
                    sh 'rm -rf .pagina-publicar'
                }
            }
        }

        // iOS necesita un agente Jenkins en una Mac con la etiqueta "macos" (§11.6). Mientras no
        // exista, se omite. Para activarlo: variable global IOS_HABILITADO=true en Jenkins.
        stage('iOS') {
            when {
                allOf {
                    branch 'main'
                    expression { env.IOS_HABILITADO == 'true' }
                }
            }
            agent { label 'macos' }
            steps {
                echo 'Pendiente: flutter build ipa y subida a TestFlight (MIGRACION_FLUTTER.md §11.6).'
            }
        }
    }
}

/** true si la credencial de la llave de release existe en Jenkins; si no, lo avisa en el log. */
def hayLlaveDeRelease() {
    try {
        withCredentials([file(credentialsId: 'android-keystore', variable: 'KEYSTORE_FILE')]) { }
        return true
    } catch (err) {
        echo 'Sin la credencial android-keystore: se omite el release (ver docs/CI_SETUP.md).'
        return false
    }
}

/** true si la rama gh-pages ya existe en GitHub. */
def existeGhPages() {
    return sh(script: 'git ls-remote --exit-code --heads origin gh-pages > /dev/null 2>&1', returnStatus: true) == 0
}
