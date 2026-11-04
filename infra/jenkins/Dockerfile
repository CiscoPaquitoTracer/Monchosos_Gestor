# Jenkins con la CLI de Docker para crear los contenedores de build (ci/Dockerfile) vía el socket del host.
# Se usa JDK 21: la imagen lts-jdk17 dejó de actualizarse (Jenkins ya no da soporte a Java 17).
FROM jenkins/jenkins:2.580.2-lts-jdk21

USER root
# CLI de Docker (solo el cliente) desde el repositorio oficial de Docker.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*
USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Pipeline multirrama ya configurado (se copia a jenkins_home solo si aún no existe).
COPY --chown=jenkins:jenkins jobs/ /usr/share/jenkins/ref/jobs/
# Configuración que se aplica en cada arranque (un build a la vez).
COPY --chown=jenkins:jenkins init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/
