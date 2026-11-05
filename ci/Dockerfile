# Imagen para compilar y probar la app Flutter en CI (Jenkins).
# Trae: Flutter SDK, Android SDK, cliente de Docker (base de datos y Gitleaks en contenedores),
# Supabase CLI, psql, mobsfscan y osv-scanner.
#
# Dependabot actualiza la imagen base (FROM), pero NO estos ARG: cámbialos a mano.
# JDK 21: el mismo que trae Android Studio (AGP 9 y Gradle 9 lo soportan).
FROM eclipse-temurin:21-jdk-jammy

# Flutter fijo (el mismo que en la laptop: flutter --version).
ARG FLUTTER_VERSION=3.47.6
# Lo que pide Flutter 3.47 (FlutterExtension.kt): compileSdk 36, NDK 28.2. Algún plugin usa la 35.
ARG ANDROID_PLATFORMS="platforms;android-36 platforms;android-35"
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_NDK=28.2.13676358
ARG ANDROID_CMAKE=3.22.1
# Android command-line tools (https://dl.google.com/android/repository/repository2-3.xml)
ARG CMDLINE_TOOLS_VERSION=16111833
ARG CMDLINE_TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60
ARG SUPABASE_CLI_VERSION=2.118.0
ARG OSV_SCANNER_VERSION=2.7.0
ARG MOBSFSCAN_VERSION=1.1.0
# Node LTS + Wrangler (CLI de Cloudflare) para desplegar la página y la PWA en Cloudflare Pages.
ARG NODE_VERSION=24.22.2
ARG WRANGLER_VERSION=4.157.0

# Jenkins corre el contenedor con un usuario no root: todo lo que se escribe queda con permisos abiertos.
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_USER_HOME=/tmp/.android \
    FLUTTER_ROOT=/opt/flutter \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_ENVIRONMENT=ci:jenkins \
    LANG=C.UTF-8
ENV PATH="${PATH}:${FLUTTER_ROOT}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git gnupg unzip wget xz-utils \
        postgresql-client python3 python3-pip \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Android SDK
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" -O /tmp/cmdline-tools.zip \
    && echo "${CMDLINE_TOOLS_SHA1}  /tmp/cmdline-tools.zip" | sha1sum -c - \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install "platform-tools" ${ANDROID_PLATFORMS} \
        "build-tools;${ANDROID_BUILD_TOOLS}" "ndk;${ANDROID_NDK}" "cmake;${ANDROID_CMAKE}" > /dev/null \
    && chmod -R a+rwX "${ANDROID_HOME}" \
    && mkdir -p "${ANDROID_USER_HOME}" && chmod 1777 "${ANDROID_USER_HOME}"

# Flutter SDK (solo Android: iOS se compila en un agente macOS, §11.6)
RUN git clone --depth 1 -b "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_ROOT}" \
    && git config --system --add safe.directory '*' \
    && flutter config --no-analytics --no-cli-animations --no-enable-web \
        --no-enable-linux-desktop --no-enable-windows-desktop --no-enable-macos-desktop \
    && flutter precache --android --no-ios --no-web \
    && dart --disable-analytics \
    && chmod -R a+rwX "${FLUTTER_ROOT}"

# Supabase CLI (etapa "Base de datos")
RUN curl -fsSL "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin supabase \
    && supabase --version

# Escáneres de seguridad (etapa "Seguridad"). Gitleaks corre en su propio contenedor.
RUN curl -fsSL -o /usr/local/bin/osv-scanner \
        "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/osv-scanner_linux_amd64" \
    && chmod +x /usr/local/bin/osv-scanner \
    && pip3 install --no-cache-dir "mobsfscan==${MOBSFSCAN_VERSION}"

# Node + Wrangler (etapa "Desplegar web"). El tarball se verifica contra SHASUMS256.txt oficial.
RUN cd /tmp \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " node-v${NODE_VERSION}-linux-x64.tar.xz$" | sha256sum -c - \
    && tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 \
    && rm "node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && npm install -g --no-fund --no-audit "wrangler@${WRANGLER_VERSION}" \
    && wrangler --version
