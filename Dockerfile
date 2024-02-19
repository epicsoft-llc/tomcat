ARG IMAGE_TAG=latest
FROM tomcat:$IMAGE_TAG

ARG BUILD_DATE
LABEL org.label-schema.name="Ansible" \
      org.label-schema.description="Tomcat based on official Tomcat image" \
      org.label-schema.vendor="epicsoft LLC / Alexander Schwarz <as@epicsoft.one>" \
      org.label-schema.version=${IMAGE_TAG} \
      org.label-schema.schema-version="1.0" \
      org.label-schema.build-date=${BUILD_DATE}

LABEL image.name="epicsoft_ansible" \
      image.description="Tomcat based on official Tomcat image" \
      maintainer="epicsoft LLC" \
      maintainer.name="Alexander Schwarz <as@epicsoft.one>" \
      maintainer.copyright="Copyright 2024 epicsoft LLC / Alexander Schwarz" \
      license="MIT"

COPY setenv.sh /usr/local/tomcat/bin/setenv.sh
COPY setenv.sh /usr/local/tomcat/bin/dockerenv.sh

RUN chmod 755 /usr/local/tomcat/bin/setenv.sh \
              /usr/local/tomcat/bin/dockerenv.sh
