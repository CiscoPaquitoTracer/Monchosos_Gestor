# Imagen para compilar y probar la app en CI (Jenkins).
# JDK 25 (LTS): AGP 9 exige JDK 17+ y Gradle 9 ya corre sobre Java 25.
FROM eclipse-temurin:25-jdk-jammy

# Versiones del proyecto (app/build.gradle.kts: compileSdk = 37; AGP 9.4 usa build-tools 36.0.0).
# Dependabot actualiza la imagen base (FROM), pero NO estos ARG: cámbialos a mano si cambia compileSdk.
ARG ANDROID_COMPILE_SDK=37.0
ARG ANDROID_BUILD_TOOLS=36.0.0
# Android command-line tools (https://dl.google.com/android/repository/repository2-3.xml)
ARG CMDLINE_TOOLS_VERSION=16111833
ARG CMDLINE_TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60

# Jenkins corre el contenedor con un usuario sin HOME (HOME=/): AGP necesita dónde escribir.
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_USER_HOME=/tmp/.android
ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git unzip wget \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" -O /tmp/cmdline-tools.zip \
    && echo "${CMDLINE_TOOLS_SHA1}  /tmp/cmdline-tools.zip" | sha1sum -c - \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
    # Jenkins ejecuta el contenedor con un usuario no root.
    && chmod -R a+rwX "${ANDROID_HOME}" \
    && mkdir -p "${ANDROID_USER_HOME}" && chmod 1777 "${ANDROID_USER_HOME}"
