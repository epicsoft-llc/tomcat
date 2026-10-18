# Tomcat

This Docker image is managed and kept up to date by [epicsoft LLC](https://epicsoft.one).

The official [tomcat](https://hub.docker.com/_/tomcat) image, extended by one feature: Docker environment variables
with the prefix `APP_` are passed to the application as system properties.

* Base image: https://hub.docker.com/_/tomcat, platform `linux/amd64`
* Dockerfile: https://gitlab.com/epicsoft-networks/tomcat/-/blob/main/Dockerfile
* Repository: https://gitlab.com/epicsoft-networks/tomcat, mirrored to [GitHub](https://github.com/epicsoft-llc/tomcat) — issues are welcome on both; code changes only as merge requests on GitLab, the mirror overwrites anything pushed to GitHub
* Container registry: https://gitlab.com/epicsoft-networks/tomcat/container_registry
* Docker Hub: https://hub.docker.com/r/epicsoft/tomcat
* Changelog: https://gitlab.com/epicsoft-networks/tomcat/-/blob/main/CHANGELOG.md
* License: MIT

## Description

### TL;DR - for technicians

```
Docker environments                              Tomcat App environments
  - APP_DATABASE_NAME="exampleDatabaseName"        - app.database.name=exampleDatabaseName
  - APP_CUSTOM_ENV1=Hello from Docker 1            - app.custom.env1=Hello from Docker 1
  - APP_CUSTOM_ENV2="Hello from Docker 2"          - app.custom.env2=Hello from Docker 2
  - APP_CUSTOM_ENV3='Hello from Docker 3'          - app.custom.env3=Hello from Docker 3
                                                 example for use in configuration: ${app.database.name}
```

### A little more detailed

All environments with the prefix `APP_` are passed on to the application.  
The environment variable can be used in the application or configuration.  
The name of the environment variable is written in lower case and separated with dots `.` instead of underscores `_`, for example `APP_DATABASE_NAME` is called `app.database.name` in the application or configuration.

Example for use in configuration: `${app.database.name}`.

Single `'` and double `"` quotation marks can be used in Docker environments, 
these are removed for transfer to the application.  
Only a matching pair around the whole value is removed, a value like `he said "hi"` keeps its quotation marks.  
Apart from that the value is passed on unchanged, a `$`, a backtick or a `$(...)` in a value stays what it is and is never executed.

After the prefix `APP_` the name may only contain letters, digits and underscores `_`.  
An environment like `APP_MY NAME` cannot become a property name, it is ignored and a line is written to the log.  
Upper and lower case are both accepted, `app_database_name` works like `APP_DATABASE_NAME`.

If you use your own `setenv.sh` file and still use the functionality of the Docker environments, 
then add the following line to your own `setenv.sh` file.

`source $(dirname "$0")/dockerenv.sh`

## Versions

`latest` based on `tomcat:latest` - build `weekly`

`11.0-jre25` based on `tomcat:11.0-jre25` - build `weekly`

`11.0-jre21` based on `tomcat:11.0-jre21` - build `weekly`

`10-jre25` based on `tomcat:10-jre25` - build `weekly`

`10-jre21` based on `tomcat:10-jre21` - build `weekly`

`10-jre17` based on `tomcat:10-jre17` - build `weekly`

`10-jre11` based on `tomcat:10-jre11` - build `weekly`

`9-jre25` based on `tomcat:9-jre25` - build `weekly`

`9-jre21` based on `tomcat:9-jre21` - build `weekly`

`9-jre17` based on `tomcat:9-jre17` - build `weekly`

`9-jre11` based on `tomcat:9-jre11` - build `weekly`

`9.0-jre11` based on `tomcat:9.0-jre11` - build `weekly`

All versions match the base image. If you need more, just ask.

A tag is the version: it names the Tomcat and the JRE in the image, and it is rebuilt weekly, so it follows the official image.  
Which versions an image really holds is written into it.

```
docker image inspect --format '{{index .Config.Labels "image.tomcat.version"}}' epicsoft/tomcat:11.0-jre21
docker image inspect --format '{{index .Config.Labels "image.java.version"}}' epicsoft/tomcat:11.0-jre21
```

Changes to this image are recorded in the [changelog](https://gitlab.com/epicsoft-networks/tomcat/-/blob/main/CHANGELOG.md).

## Examples

### Example use in a docker-compose file

`docker-compose.yml`

```yaml
services:
  tomcat:
    image: epicsoft/tomcat:latest
    container_name: tomcat
    hostname: tomcat
    restart: unless-stopped
    environment:
      - APP_DATABASE_NAME="exampleDatabaseName"
      - APP_CUSTOM_ENV1=Hello from Docker 1
      - APP_CUSTOM_ENV2="Hello from Docker 2"
      - APP_CUSTOM_ENV3='Hello from Docker 3'
    volumes:
      - /srv/tomcat/webapps:/usr/local/tomcat/webapps:rw
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    tmpfs:
      - /usr/local/tomcat/temp:exec,mode=777,uid=0,gid=0
    networks:
      - tomcat
    ports:
      - "8080:8080"
networks:
  tomcat:
    name: tomcat
```

`Tomcat logs` _(shortened / sequence of rows does not have to match)_

```log
INFO [main] ...catalina...log Command line argument: -Dapp.database.name=exampleDatabaseName
INFO [main] ...catalina...log Command line argument: -Dapp.custom.env1=Hello from Docker 1
INFO [main] ...catalina...log Command line argument: -Dapp.custom.env2=Hello from Docker 2
INFO [main] ...catalina...log Command line argument: -Dapp.custom.env3=Hello from Docker 3
```

### Example of using your own `setenv.sh`

`docker-compose.yml` _(shortened)_

```yml
volumes:
  - /srv/tomcat/setenv.sh:/usr/local/tomcat/bin/setenv.sh:ro
```

`setenv.sh`

```bash
#!/bin/bash

# <CUSTOM CODE>

#### Load Docker environments
source $(dirname "$0")/dockerenv.sh
```

## Reporting problems

Issues are welcome on [GitLab](https://gitlab.com/epicsoft-networks/tomcat/-/issues) and
[GitHub](https://github.com/epicsoft-llc/tomcat/issues). Please report a security problem as a
**confidential issue** on GitLab instead of a public one.

## License

[MIT](https://gitlab.com/epicsoft-networks/tomcat/-/blob/main/LICENSE) — Copyright (c) 2024-2026 epicsoft LLC / Alexander Schwarz

The MIT license applies only to files created by epicsoft LLC. Third-party software in the image — Apache Tomcat, the
JRE and the official `tomcat` image — remains under its own licenses.
