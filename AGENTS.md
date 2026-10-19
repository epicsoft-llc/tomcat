# AGENTS.md

Guidance for AI coding agents and contributors working in this repository.

## What this repository is

A thin Docker image layer on top of the official `tomcat` image (published as `epicsoft/tomcat`).
Its only functionality: translate Docker environment variables prefixed with `APP_` into Tomcat
system properties, so `APP_DATABASE_NAME=foo` becomes `-Dapp.database.name=foo` and is usable in
app config as `${app.database.name}`.

The product is three files - `Dockerfile`, `setenv.sh`, `.gitlab-ci.yml`; the rest is documentation
and the tests under `test/`. There is no application code and no build tooling beyond Docker, and the
tests are plain bash and docker as well.

`.dockerignore` is a whitelist (`*`, then `!setenv.sh`, `!Dockerfile`): a new file that has to end up
in the image needs its own `!` line, otherwise the `COPY` fails with "file not found".

| | |
|---|---|
| **Repository** | developed on `gitlab.com/epicsoft-networks/tomcat` (branch `main`), mirrored to `github.com/epicsoft-llc/tomcat` |
| **Registries** | `registry.gitlab.com/epicsoft-networks/tomcat` and Docker Hub `epicsoft/tomcat` |
| **Platforms** | `linux/amd64` |

## Build and run

```bash
# Build one variant (IMAGE_TAG must be a valid tag of the official tomcat image). The three
# version arguments are read out of the base image; leaving them off gives a working image
# with empty version labels, which is fine locally but not what the pipeline publishes.
docker pull tomcat:11.0-jre21
docker build --pull -t epicsoft/tomcat:11.0-jre21 . \
  --build-arg IMAGE_TAG=11.0-jre21 \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VCS_REF=$(git rev-parse --short HEAD) \
  --build-arg TOMCAT_VERSION=$(docker run --rm tomcat:11.0-jre21 /usr/local/tomcat/bin/version.sh | sed -n 's/^Server number:[[:space:]]*//p') \
  --build-arg JAVA_VERSION=$(docker run --rm tomcat:11.0-jre21 /usr/local/tomcat/bin/version.sh | sed -n 's/^JVM Version:[[:space:]]*//p') \
  --build-arg BASE_DIGEST=$(docker image inspect -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' tomcat:11.0-jre21 | cut -d@ -f2)

# Smoke test used by CI: the image must start and report its Tomcat version
docker run --rm epicsoft/tomcat:11.0-jre21 /usr/local/tomcat/bin/version.sh

# Verify the env translation end to end — look for the -Dapp.* command line arguments
docker run --rm -e APP_DATABASE_NAME=exampleDatabaseName -p 8080:8080 epicsoft/tomcat:latest
```

## Tests

`test/test.sh` is a local, container-only test environment; it needs nothing but a reachable
docker. It builds the image itself and asserts inside throwaway containers and against a really
started Tomcat. Called without an argument it prints its usage.

```bash
bash test/test.sh default            # docs unit image tomcat custom - about a minute
bash test/test.sh unit               # only the setenv.sh translation, no server start
bash test/test.sh all                # additionally 'versions': builds every published tag
bash test/test.sh --keep tomcat      # leave the containers up for a look
bash test/clean.sh env               # remove leftovers of an interrupted run
bash test/clean.sh all               # additionally the built test images and test/.logs

TOMCAT_TEST_TAG=9-jre11 bash test/test.sh default            # build on another base tag
TOMCAT_TEST_VERSIONS="9-jre11" bash test/test.sh versions    # only these tags
```

The pipeline runs `bash test/test.sh default` in a `test` stage before the build stage, so a red test
keeps the weekly build from publishing. Each build job additionally runs `version.sh` and a one-line
`APP_` check against the image *before* it pushes it.

Everything the tests create carries the docker label `tomcat-test`, which is how `clean.sh` removes
the leftovers of any run without knowing what ran. The image is built as `epicsoft-tomcat:test`, not
`tomcat:test`: the latter is in the same repository as the official image the Dockerfile builds
`FROM`. Per-case output lands in `test/.logs` (gitignored).

The groups: `docs` (the version list in README.md matches the build jobs, line endings), `unit`
(what `setenv.sh` writes into `CATALINA_OPTS`, no server needed), `image` (file modes, labels, the
two copies of the script, `version.sh`), `tomcat` (the `-Dapp.*` arguments on a started server's
command line), `custom` (an own `setenv.sh` with and without the `dockerenv.sh` line, baked into a
derived image), `versions` (builds every tag from `.gitlab-ci.yml` and checks the reported Tomcat
and JRE version against the tag - slow, not in `default`).

Two details a new test has to respect. The snippet run in the container gets
`/usr/local/tomcat/bin/catalina.sh` as `$0`, because that is what a sourced script sees in a real
start; `setenv.sh` itself no longer depends on it, but the `dockerenv.sh` line users put in their own
`setenv.sh` does, so the tests keep resolving it the way the container would. And a value with spaces
only stays one argument because catalina.sh expands `CATALINA_OPTS` through `eval`, which is why the
unit group asserts the quoted string and the tomcat group the unquoted value in the log.

## How the env translation works

`setenv.sh` is copied into the image **twice**, as `bin/setenv.sh` and as `bin/dockerenv.sh`. That
duplication is the extension point: users who mount their own `setenv.sh` (Tomcat only ever calls
that one file) keep the feature by adding `source $(dirname "$0")/dockerenv.sh`. Any change to the
script must keep working under both names.

Inside the script:

- The loop reads from a process substitution (`done < <(env -0)`), not from `env -0 | while ...`.
  A pipe would run the loop in a subshell and every assignment to `CATALINA_OPTS` would be lost with
  it. An earlier version worked around that by writing `export` lines into a generated
  `bin/dockerappenv.sh` and sourcing it - which sent every value through the shell a second time and
  so expanded a `$` and executed a `$(...)` that was only meant as data. Do not go back to that.
- The value is quoted twice over, for two different readers. catalina.sh does not exec the java
  command, it hands it to `eval`, so `CATALINA_OPTS` is parsed as shell syntax again: the single
  quotes the script writes around each value are what keeps a value with spaces one argument there
  and what stops a `$` inside a value from being expanded. A single quote in the value would end
  that protection, so each one is replaced by `'\''`.
- The name is not protected by that quoting - it stands in the same line and is read by the same
  `eval`. So a name that cannot be a property name (a space, a quote, or nothing after `APP_`) is
  skipped with a message on stderr; a space in it used to make the rest of the line a second java
  argument and the server died at startup with `Could not find or load main class`.
- Only a *matching* pair of quotes around the whole value is removed, and only when that quote does
  not appear inside as well. Stripping a leading and a trailing quote independently ate the last
  character of `he said "hi" and "bye"`.
- `declare -u _K` / `declare -l _KEY` do the case conversion via Bash variable attributes. Key and
  value are handled with parameter expansion only - no `sed`, no `echo`, no subshell, so a value is
  never word-split or glob-expanded on the way through.
- It is sourced into the shell of catalina.sh, which runs on afterwards. Nothing may be left behind
  there: no `readonly` (a second source cannot overwrite it), and the helper variables are `unset`
  at the end.

Requires Bash (`declare -u/-l`, `env -0`, process substitution). catalina.sh is `#!/usr/bin/env bash`
in every published tag, checked down to `9-jre11`.

## Adding or removing a version variant

Versions are hardcoded, one CI job per tag, and the tag name is passed straight through as
`IMAGE_TAG` and used as the published tag, as `org.label-schema.version` and as
`org.opencontainers.image.version`. Changing the set of supported versions means editing three
places consistently:

1. a job in `.gitlab-ci.yml` - three lines, `extends: .build` plus the `VERSION` variable.
   Everything else (stage, `retry`, the publish `rules`, the steps) comes from the template, and a
   job that carries its own copy of those is a job that can publish from any branch,
2. the "Versions" list in `README.md`,
3. any scheduled-pipeline configuration in GitLab (builds are weekly).

`README.md` is not just documentation: the `uploadReadme` release job pushes it to Docker Hub as the
repository description, so README edits are user-visible releases. That job hands the file over with
`docker cp` into a volume rather than a bind mount: under dind the daemon resolves `-v $PWD` on its
own filesystem, where this job's checkout does not exist, and would publish an empty description.

## Versioning

There is no version number of this image. A tag *is* the version: it is the tag of the official
image it is built on, and it moves - every tag is rebuilt weekly and then holds a newer Tomcat and
a newer JRE. So the tag alone does not identify a build, and three labels do: `image.tomcat.version`,
`image.java.version` and `org.opencontainers.image.base.digest`.

Those three are build arguments, read out of the base image *before* the build (`version.sh` in a
throwaway container, `RepoDigests` from `docker image inspect`). That happens in two places which
have to stay in step - the `.build` template in `.gitlab-ci.yml` and `buildImage()` in
`test/test.sh` - so the labels the tests assert are built the way the published ones are. A new
build argument means editing both.

`CHANGELOG.md` follows from this: dated entries, no numbers, because there is no number to give
them. A change worth telling users about gets an entry under today's date.

Each entry is also a git tag of its date, such as `2026-10-18`, set on the green commit of `main`
that carries it; until then the entry may still grow, once tagged it is fixed and a correction goes
into the next entry. The tag pipeline runs `github-release`, which creates the GitHub release from
that entry, and `test`; it builds nothing. Tags are protected, because `GITHUB_TOKEN` is a protected
variable.

New Tomcat and JRE releases reach the images with the weekly build and need no commit. They get one
entry per quarter, after the quarterly Java update in January, April, July and October, listing the
Tomcat and JRE versions of the latest build; a release that fixes a vulnerability rated important or
critical gets its entry right away.

## Pipeline structure (`.gitlab-ci.yml`)

| Job | Trigger | Action |
|---|---|---|
| `test` | every push | `bash test/test.sh default` — a red test keeps the build stage from running |
| `tomcatLatest`, `tomcat<tag>` | branch `main` (push, weekly schedule) | read the versions of the official image, build, test (`version.sh` and one `APP_` check), push to both registries |
| `uploadReadme` | branch `main` (push, weekly schedule) | README as Docker Hub description, at most 25,000 bytes |
| `github-release` | tag `YYYY-MM-DD` | the GitHub release from the changelog entry of that date |

CI variables: `DOCKER_HUB_USER` (protected), `DOCKER_HUB_TOKEN` and `GITHUB_TOKEN` (masked,
protected). The tokens go in over stdin and through the environment, never onto a command line,
where every process on the runner could read them.

**GitHub mirror:** a push mirror in the GitLab project settings (Repository → Mirroring
repositories) with its own token — not part of the pipeline. Changes are never pushed to GitHub
directly; the mirror would overwrite them. Every changelog entry is a git tag and a GitHub release,
see Versioning.

## Conventions

`.editorconfig` applies: LF, UTF-8, 2-space indent, final newline, trailing whitespace trimmed
(except in Markdown, where trailing double-spaces are used as line breaks in README.md).

Commit messages follow Conventional Commits (`feat:`, `fix:`, `ci:`, `chore:`).
