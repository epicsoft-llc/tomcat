ARG IMAGE_TAG=latest
FROM tomcat:$IMAGE_TAG

ARG IMAGE_TAG
ARG BUILD_DATE
ARG VCS_REF
ARG TOMCAT_VERSION
ARG JAVA_VERSION
ARG BASE_DIGEST
LABEL org.label-schema.name="Tomcat" \
      org.label-schema.description="Automatically passes Docker environments to the application, based on official Tomcat image" \
      org.label-schema.vendor="epicsoft LLC / Alexander Schwarz <info@epicsoft.one>" \
      org.label-schema.url="https://gitlab.com/epicsoft-networks/tomcat" \
      org.label-schema.vcs-url="https://gitlab.com/epicsoft-networks/tomcat/tree/main" \
      org.label-schema.vcs-ref=${VCS_REF} \
      org.label-schema.version=${IMAGE_TAG} \
      org.label-schema.schema-version="1.0" \
      org.label-schema.build-date=${BUILD_DATE}

LABEL org.opencontainers.image.title="Tomcat" \
      org.opencontainers.image.description="Automatically passes Docker environments to the application, based on official Tomcat image" \
      org.opencontainers.image.vendor="epicsoft LLC" \
      org.opencontainers.image.authors="Alexander Schwarz <info@epicsoft.one>" \
      org.opencontainers.image.url="https://hub.docker.com/r/epicsoft/tomcat" \
      org.opencontainers.image.source="https://gitlab.com/epicsoft-networks/tomcat" \
      org.opencontainers.image.documentation="https://gitlab.com/epicsoft-networks/tomcat/blob/main/README.md" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version=${IMAGE_TAG} \
      org.opencontainers.image.revision=${VCS_REF} \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.base.name="docker.io/library/tomcat:${IMAGE_TAG}" \
      org.opencontainers.image.base.digest=${BASE_DIGEST}

LABEL image.name="epicsoft_tomcat" \
      image.description="Automatically passes Docker environments to the application, based on official Tomcat image" \
      maintainer="epicsoft LLC" \
      maintainer.name="Alexander Schwarz <info@epicsoft.one>" \
      maintainer.url="https://epicsoft.one/" \
      maintainer.copyright="Copyright 2024-2026 epicsoft LLC / Alexander Schwarz" \
      license="MIT"

# A tag is the version of this image, and it moves: '11.0-jre21' is rebuilt weekly and holds
# a different Tomcat and a different JRE over time. These two say which ones went in, and the
# base digest above says exactly which image they came out of - without them two builds of
# the same tag cannot be told apart.
LABEL image.tomcat.version=${TOMCAT_VERSION} \
      image.java.version=${JAVA_VERSION}

COPY setenv.sh /usr/local/tomcat/bin/setenv.sh
COPY setenv.sh /usr/local/tomcat/bin/dockerenv.sh

RUN chmod 755 /usr/local/tomcat/bin/setenv.sh \
              /usr/local/tomcat/bin/dockerenv.sh
