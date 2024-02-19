# Tomcat

This Docker image is managed and kept up to date by [epicsoft LLC](https://epicsoft.one).

Tomcat based on official [tomcat](https://hub.docker.com/_/tomcat) image.

Automatically passes Docker environments to the application, based on official Tomcat image.

* Base image:https://hub.docker.com/_/tomcat
* Dockerfiles: https://gitlab.com/epicsoft-networks/tomcat/tree/main
* Repository: https://gitlab.com/epicsoft-networks/tomcat/tree/main
* Container-Registry: https://gitlab.com/epicsoft-networks/tomcat/container_registry
* Docker Hub: https://hub.docker.com/r/epicsoft/tomcat

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

If you use your own `setenv.sh` file and still use the functionality of the Docker envirements, 
then add the following line to your own `setenv.sh` file.

`source $(dirname "$0")/dockerenv.sh`

## Versions

`latest` based on `tomcat:latest` - build `weekly`

`11.0-jre21` based on `tomcat:11.0-jre21` - build `weekly`

`10-jre21` based on `tomcat:10-jre21` - build `weekly`

`10-jre17` based on `tomcat:10-jre17` - build `weekly`

`10-jre11` based on `tomcat:10-jre11` - build `weekly`

`9-jre21` based on `tomcat:9-jre21` - build `weekly`

`9-jre17` based on `tomcat:9-jre17` - build `weekly`

`9-jre11` based on `tomcat:9-jre11` - build `weekly`

`9.0-jre11` based on `tomcat:9.0-jre11` - build `weekly`

All versions match the base image. If you need more, just ask.

## Examples

### Example use in a docker-compose file

`docker-compose.yml`

```yaml
version: '3.8'
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

## License

MIT License see [LICENSE](https://gitlab.com/epicsoft-networks/tomcat/blob/main/LICENSE)

Please note that the MIT license only applies to the files created by epicsoft LLC. Other software may be licensed under other licenses.
