# Changelog

All notable changes to this image.

This image has no version number of its own. Its version is the version it runs:
a tag is the tag of the official [tomcat](https://hub.docker.com/_/tomcat) image
it is built on, so `11.0-jre21` is Tomcat 11.0 on JRE 21.

Those tags move. Every one of them is rebuilt weekly and then holds a newer
Tomcat and a newer JRE than before, and a change from this file reaches a tag
with its next build. Which versions a particular image really holds is written
into the image:

```
docker image inspect --format '{{index .Config.Labels "image.tomcat.version"}}' epicsoft/tomcat:11.0-jre21
```

`image.java.version` says the same for the JRE, and
`org.opencontainers.image.base.digest` names the exact official image the build
came out of. Entries here are dated, because there is no number to give them.
Each date is also a git tag with a release on GitHub. New Tomcat and JRE
releases from the weekly build are summed up once a quarter, a fix rated
important or critical right away.

---

## 2026-10-18

A mirror on GitHub, and a pipeline that keeps its tokens out of the process
list. The image itself does not change.

### Added

- **A mirror on GitHub**: `github.com/epicsoft-llc/tomcat`. GitLab stays the
source, issues are welcome on both.

### Security

- **The pipeline keeps its tokens out of the process list.** The registry
logins passed them with `-p` and the upload of the Docker Hub description with
`-e NAME=value`, where every process on the runner could read them. They go in
over stdin and through the environment now.

### Changed

- The short description is the same text on Docker Hub, GitLab and GitHub, and
the image labels carry it too.
- README: current GitLab links, the GitHub mirror and a section on reporting
problems. The upload stops if the README ever exceeds the 25,000 characters
Docker Hub takes, instead of publishing a cut-off text.

---

## 2026-09-06

The environment translation was rewritten. Values are now passed on as they were
written, and a name that cannot become a property no longer takes the server down
with it.

### Fixed

- **A value is passed on literally.** The properties were assembled in a
generated file that was sourced afterwards, which sent every value through the
shell a second time: `$`, a backtick and `"` in a value were evaluated there. A
password like `pa$(id -u)ss` did not arrive as it was written - the command in it
ran. Values are now built in the shell of `catalina.sh` itself and quoted for the
`eval` it does, so a `$`, a `$(...)`, a quote or a backslash in a value stays
what it is.
- **A name that cannot be a property name no longer stops the start.** An
environment such as `APP_MY NAME` ended up as a second word on the java command
line, and the container died with `Could not find or load main class` naming the
value. Names with anything other than letters, digits and `_` after `APP_` are
now skipped, with a line in the log that says which one.
- **Only a matching pair of quotes is removed.** A leading and a trailing
quotation mark were stripped independently, so `he said "hi" and "bye"` lost its
last character and `"a" and "b"` became `a" and "b`. A pair is only taken off now
when the same quote does not appear inside the value as well.
- **The image is tested before it is published**, not after. The version check
ran after both pushes, so an image that could not start was already on docker hub
by the time anyone saw it.
- **Only the default branch and the weekly schedule publish.** Every push to
every branch built all nine tags, pushed them to docker hub and overwrote the
description there.
- **The line endings are pinned** with a `.gitattributes`. On a checkout that
converts to CRLF, `setenv.sh` reached the image with carriage returns and the
container died with `$'\r': command not found`.

### Added

- **Three tags on JRE 25**: `11.0-jre25`, `10-jre25` and `9-jre25`. `latest` has
been running on JRE 25 for a while - these are the tags for anyone who wants that
JRE together with a name that does not change its Tomcat version underneath.
- **The versions an image really holds are written into it.** A tag names a
Tomcat and a JRE but moves from build to build; `image.tomcat.version`,
`image.java.version` and `org.opencontainers.image.base.digest` say which ones
went in, so two builds of the same tag can be told apart.
- **A local test environment** under `test/`, container-only:
`bash test/test.sh default`. It runs in the pipeline before the build stage, so
a failing test keeps the weekly build from publishing.
- **OCI image labels** (`org.opencontainers.image.*`) next to the label-schema
ones, plus the commit the image was built from.
- A `.dockerignore`, so the build context is the one file the image copies.

### Changed

- **`bin/dockerappenv.sh` is not generated any more.** It was internal and
undocumented; nothing has to be written to the filesystem at startup now, and the
image starts with a read-only root filesystem.
- Upper and lower case are both accepted in a name: `app_database_name` works
like `APP_DATABASE_NAME`. That was always the case, it is documented now.

---

Earlier changes are in the git history of this repository.
