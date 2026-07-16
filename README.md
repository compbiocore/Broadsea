# OHDSI Broadsea 3.5

[![default profile](https://github.com/OHDSI/Broadsea/actions/workflows/default.yml/badge.svg?branch=develop)](https://github.com/OHDSI/Broadsea/actions/workflows/default.yml) [![perseus profile](https://github.com/OHDSI/Broadsea/actions/workflows/perseus.yml/badge.svg?branch=develop)](https://github.com/OHDSI/Broadsea/actions/workflows/perseus.yml) [![openldap profile](https://github.com/OHDSI/Broadsea/actions/workflows/openldap.yml/badge.svg?branch=develop)](https://github.com/OHDSI/Broadsea/actions/workflows/openldap.yml) [![solr-vocab Profile](https://github.com/OHDSI/Broadsea/actions/workflows/solr-vocab.yml/badge.svg?branch=develop)](https://github.com/OHDSI/Broadsea/actions/workflows/solr-vocab.yml) [![achilles Profile](https://github.com/OHDSI/Broadsea/actions/workflows/achilles.yml/badge.svg?branch=develop)](https://github.com/OHDSI/Broadsea/actions/workflows/achilles.yml)

## Contents

- [Introduction](#introduction)
  - [Brown VM deployment](#brown-vm-deployment)
  - [What runs locally](#what-runs-locally)
- [Local installation](#local-installation)
  - [Prerequisites](#prerequisites)
  - [Clone and configure](#clone-and-configure)
  - [Start the core stack](#start-the-core-stack)
  - [Verify the installation](#verify-the-installation)
  - [Optional local deployment script](#optional-local-deployment-script)
- [Configuration guide](#configuration-guide)
  - [Host, HTTP, and TLS](#host-http-and-tls)
  - [Architecture and Apple silicon](#architecture-and-apple-silicon)
  - [Secrets](#secrets)
  - [Persistence and ports](#persistence-and-ports)
- [Broadsea - Community Contributions](#community-contributions)
- [Broadsea - Advanced Usage](#broadsea---advanced-usage)
  - [.env file](#env-file)
  - [Docker Secrets (New for 3.5)](#docker-secrets-new-for-35)
  - [Remote Servers](#remote-servers)
  - [Docker Profiles](#docker-profiles)
  - [Traefik Dashboard](#traefik-dashboard)
  - [SSL](#ssl)
  - [Broadsea Content Page](#broadsea-content-page)
  - [Vocabulary Loading](#vocabulary-loading)
  - [OHDSI Web Applications](#ohdsi-web-applications)
  - [CDM ETL Design and Execution](#cdm-etl-design-and-execution)
  - [CDM Post Processing](#cdm-post-processing-cdm-post-processing)
  - [Evidence Generation](#evidence-generation)
  - [Evidence Dissemination](#evidence-dissemination)
- [Shutting Down Broadsea](#shutting-down-broadsea)
- [Broadsea Intended Uses](#broadsea-intended-uses)
- [Troubleshooting](#troubleshooting)
  - [View the status of the running Docker containers](#view-the-status-of-the-running-docker-containers)
  - [Viewing Log Files](#viewing-log-files)
  - [Atlasdb upgrade - Docker volume error](#Atlasdb-upgrade-docker-volume-error)
- [Hardware/OS Requirements for Installing Docker](#hardwareos-requirements-for-installing-docker)
- [License](#license)

## Introduction

Broadsea runs the core OHDSI technology stack using cross-platform Docker container technology.

This fork also includes a CompBioCore local deployment and smoke-test workflow for running
Achilles, DataQualityDashboard (DQD), and AresIndexer against the included demonstration CDM.
The instructions below distinguish the standard Broadsea Compose workflow from that optional,
fork-specific workflow.

[Information on Observational Health Data Sciences and Informatics (OHDSI)](http://www.ohdsi.org/ "OHDSI Website")

This repository contains the Docker Compose file used to launch the OHDSI Broadsea Docker containers:

- OHDSI R HADES - in RStudio Server
  - [OHDSI Broadsea R HADES GitHub repository](https://github.com/OHDSI/Broadsea-Hades/ "OHDSI Broadsea R HADES GitHub Repository")
  - [OHDSI Broadsea R HADES Docker Hub container image](https://hub.docker.com/r/ohdsi/broadsea-hades "OHDSI Broadsea HADES Docker Image Repository")
- OHDSI Atlas - including WebAPI REST services
  - [Atlas GitHub repository](https://github.com/OHDSI/Atlas "OHDSI Atlas GitHub Repository")
  - [Atlas Docker Hub container image](https://hub.docker.com/r/ohdsi/atlas "OHDSI Atlas Docker Image Repository")
  - [WebAPI GitHub repository](https://github.com/OHDSI/WebAPI "OHDSI WebAPI GitHub Repository")
  - [WebAPI Docker Hub container image](https://hub.docker.com/r/ohdsi/webapi "OHDSI WebAPI Docker Image Repository")
  - [Atlas application PostgreSQL database GitHub repository](https://github.com/OHDSI/Broadsea-Atlasdb "OHDSI Broadsea Atlas application PostgreSQL database GitHub Repository")
  - [Atlas application PostgreSQL databbase Docker Hub container image](https://hub.docker.com/repository/docker/ohdsi/broadsea-atlasdb "OHDSI Broadsea Atlas application PostgreSQL database Docker Image Repository")
  - SOLR based OMOP Vocab search
- OHDSI Ares
  - [Ares GitHub repository](https://github.com/OHDSI/Ares "OHDSI Ares GitHub Repository")
- OHDSI Perseus (Experimental)
  - [Perseus GitHub repository](https://github.com/OHDSI/Perseus "OHDSI Perseus GitHub Repository")

Additionally, Broadsea offers limited support for services not specifically needed for OHDSI applications that often are useful:

- OpenLDAP for testing security in Atlas
- Open Shiny Server for deploying Shiny apps without a commercial license
- Posit Connect for sites with commercial Posit licenses, for deploying Shiny apps
- DBT for ETL design

### Brown VM deployment

This setup is currently deployed on Brown University's VM at
`devexcite.services.brown.edu`. Access requires an authorized Brown account:

1. Connect to Brown's VPN.
2. SSH into the VM, replacing `<brown-username>` with your Brown username:

   ```shell
   ssh <brown-username>@devexcite.services.brown.edu
   ```

### What runs locally

The `default` profile starts Traefik plus the following application services:

| Component | Purpose | Local route or port |
|---|---|---|
| Traefik | Reverse proxy and path-based routing | `http://127.0.0.1/`; host ports 80 and 443 |
| Broadsea content | Landing page | `/` |
| Atlas | OHDSI web interface | `/atlas` |
| WebAPI | Atlas REST API | `/WebAPI` |
| Broadsea AtlasDB | PostgreSQL for WebAPI and the demo data | host port 5432 |
| HADES | RStudio Server with OHDSI tools | `/hades` |

Compose profiles add services such as Ares, Solr, vocabulary loading, CDM
post-processing, pgAdmin, OpenLDAP, Shiny, Jupyter, DBT, and Perseus. Traefik is
not assigned to a profile, so it starts whenever any profile is started.

## Local installation

### Prerequisites

- A 64-bit Linux, macOS, or Windows machine. On Windows, use Docker Desktop with
  the WSL 2 backend and run the commands from a WSL terminal.
- Docker Engine or Docker Desktop with the Compose v2 plugin. Commands in this
  repository use `docker compose`, not the retired `docker-compose` command.
- Git and a Chromium-based browser.
- At least 4 GB of memory available to Docker for the core profile; 8 GB or more
  is recommended when adding Ares or CDM post-processing.
- Free host ports 80, 443, and 5432. See [Persistence and ports](#persistence-and-ports)
  if another web server or PostgreSQL instance already uses them.

Confirm the required tools before continuing:

```shell
git --version
docker version
docker compose version
docker info
```

If `docker info` cannot reach the daemon, start Docker Desktop or the Docker
service. On Linux, configure Docker for non-root use or prefix Docker commands
with `sudo` consistently.

### Clone and configure

Clone this fork and enter its root directory:

```shell
git clone https://github.com/compbiocore/Broadsea.git
cd Broadsea
```

The tracked `.env` is configured for the hosted CompBioCore deployment. **Do not
start it unchanged for a localhost-only installation.** At minimum, edit Section
1 of `.env` to use:

```dotenv
BROADSEA_HOST="127.0.0.1"
HTTP_TYPE="http"
BROADSEA_CERTS_FOLDER="./certs"
```

`BROADSEA_HOST` must contain only a host name or IP address—no scheme, port, or
path. Traefik uses it in host-routing rules, while `HTTP_TYPE` chooses the HTTP
or HTTPS Traefik configuration. Review the remainder of `.env` before starting;
its numbered sections are summarized under [Configuration guide](#configuration-guide).

The files under `secrets/` are mounted as Docker secrets. Replace development
or placeholder values for any enabled service. Keep every `*_FILE` variable as
a path to a file; do not replace it with the secret value itself.

Validate interpolation and profile selection without starting containers:

```shell
docker compose --profile default config --quiet
```

### Start the core stack

Pull images and start the default profile from the repository root:

```shell
docker compose --profile default pull
docker compose --profile default up -d
```

The initial start can take several minutes while images download, PostgreSQL is
initialized, and WebAPI migrations run. `up --pull always -d` may be used when
you intentionally want to refresh images, but it can change an otherwise
repeatable installation because some services use floating image tags.

### Verify the installation

Check container state and follow the initialization logs:

```shell
docker compose --profile default ps
docker compose --profile default logs --tail=100 broadsea-atlasdb ohdsi-webapi-from-image
```

When AtlasDB is healthy and WebAPI has finished starting, open:

- Landing page: <http://127.0.0.1/>
- Atlas: <http://127.0.0.1/atlas>
- WebAPI status: <http://127.0.0.1/WebAPI/info>
- HADES/RStudio: <http://127.0.0.1/hades>
- Traefik dashboard: <http://127.0.0.1/dashboard/>

The HADES username comes from `HADES_USER` in `.env`; its password is the
contents of the file named by `HADES_PASSWORD_FILE`. A container marked
`Exited (0)` can be normal for one-shot jobs such as vocabulary loaders and CDM
post-processing. It is not normal for the core Atlas, WebAPI, database, HADES,
content, or Traefik services.

### Optional local deployment script

`deploy.sh` is a fork-specific smoke test. It starts the `default` and `ares`
profiles, pulls CompBioCore Achilles/DQD/AresIndexer images from GHCR, waits for
AtlasDB, checks endpoints, and runs `Achilles -> DQD -> AresIndexer` against the
configured CDM. It is more resource-intensive than the core installation.

```shell
./deploy.sh --help
./deploy.sh --skip-postprocessing  # core plus Ares; no CDM processing
./deploy.sh                        # full smoke test and post-processing
```

Useful options are `--skip-pull`, `--clean-ares`, and `--full-ares`. The last
option generates `.env.local.generated` from `.env` with `ARES_RUN_NETWORK=TRUE`.
`--clean-ares` deletes existing files under `ares/data/`, so preserve any output
you need before using it. Override `TAG`, `GHCR_ORG`, or `PLATFORM` only when you
intend to test different post-processing images.

## Configuration guide

The `.env` file is the configuration source for Compose. Its sections cover:

| Sections | Configuration area |
|---|---|
| 1 | Host, protocol, certificates, architecture, and GitHub token file |
| 2–3 | Atlas UI and WebAPI database/runtime settings |
| 4–5 | Atlas/WebAPI authentication providers |
| 6–10 | Git builds, Solr vocabulary, HADES, vocabulary loading, and Phoebe |
| 11–15 | Ares, landing-page links, OpenLDAP, Shiny, and Posit Connect |
| 16–18 | Perseus/DBT, CDM post-processing, and pgAdmin |

Change only the sections required by the profiles you enable. Run
`docker compose --profile <profile> config --quiet` after each configuration
change to catch missing variables, files, and Compose syntax errors.

### Host, HTTP, and TLS

For localhost, use `BROADSEA_HOST=127.0.0.1` and `HTTP_TYPE=http`. For access
from other machines, use a DNS name or server IP that clients can resolve and
allow inbound TCP 80/443 through the host and network firewalls.

For HTTPS, set `HTTP_TYPE=https`, place the certificate and private key at
`BROADSEA_CERTS_FOLDER/broadsea.crt` and
`BROADSEA_CERTS_FOLDER/broadsea.key`, and ensure the certificate covers
`BROADSEA_HOST`. Do not expose this stack to untrusted networks with default
credentials, disabled Atlas authentication, or the Traefik dashboard enabled.

### Architecture and Apple silicon

Several core services are explicitly pinned to `linux/amd64` in
`docker-compose.yml`. Apple silicon can run them through Docker Desktop
emulation, but startup and post-processing will be slower. Leave
`DOCKER_ARCH=linux/amd64` unless every selected image is known to provide and
support an ARM64 variant. If an image fails with an architecture or Rosetta
error, enable Docker Desktop's x86/amd64 emulation support and retry.

### Secrets

Compose maps the `*_FILE` variables in `.env` to files below `secrets/`. The
file should contain only the secret (a trailing newline is acceptable). Treat
the provided values as development defaults, replace those used by enabled
profiles, restrict file permissions, and never put production credentials in a
commit. Changing the file on the host may require recreating the consuming
container:

```shell
docker compose --profile default up -d --force-recreate
```

### Persistence and ports

PostgreSQL, RStudio home/tmp, OpenLDAP, JDBC drivers, post-processing results,
Perseus, Jupyter, and pgAdmin use named Docker volumes declared at the top of
`docker-compose.yml`. `docker compose down` removes containers and the Compose
network but preserves these volumes. `docker compose down -v` deletes persistent
data and should be used only for an intentional reset.

The core deployment binds ports 80 and 443 for Traefik and 5432 for AtlasDB. If
a port is occupied, stop the conflicting local service or deliberately change
the host side of the relevant `ports:` mapping (for example, `55432:5432` for
AtlasDB). Container-to-container connection strings should continue to use the
container port and service name, such as `broadsea-atlasdb:5432`.

## Community Contributions

Community contributions are welcome! Here are the steps for making Community contributions to OHDSI Broadsea:

- Create a new GitHub issue in the OHDSI/Broadsea repo with a short summary describing the proposed changes
- After discussion of the issue is completed in the GitHub repo, and the issue is approved, create a GitHub Pull Request, linked to the GitHub issue. 
- The OHDSI/Broadsea GitHub repository maintainer will review, request changes to the Pull Request if needed, and then merge the Pull Request

Here are some guiding principles for making contributions - these items should be addressed in the issue & issue discussion.

- If a new application is added it must be useful for a large section of the OHDSI community.
- The changes should maintain backwards compatibility for existing Broadsea deployments. There are some valid exceptions like bug fixes, and new Broadsea releases may allow breaking changes. 
- The changes must fit within the Broadsea framework. For example, each new application gets a subdirectory,  secrets files are added if needed, a new section added to the .env file etc.
- The contributor agrees to support the changes and respond to any related issues in the OHDSI/Broadsea GitHub repository and the OHDSI forums.
- OHDSI Broadsea is cross platform, so the contributor will test the changes on each targeted OS (Windows, Linux and Mac), before submitting a Pull Request. 

## Broadsea - Advanced Usage

### .env file

The tracked `.env` contains deployment values for this fork, not universal
localhost defaults. Review it profile by profile and use the local Section 1
settings described above before running Broadsea on a workstation.

### Docker Secrets (New for 3.5)

Broadsea leverages [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/ "Docker Secrets") to handle sensitive passwords and secret keys.

> In Broadsea 3.0, these were handled via plain-text environment variables, which is not best security practice

Now in Broadsea 3.5, each sensitive password or secret key is to be stored in a file; the paths to these files is then set in the .env file per Section. Please refer to the default `./secrets` folder for examples on how to set up these files for your site.

### Remote Servers

In Section 1 of the .env file, set BROADSEA_HOST as the IP address or host name **(without http/https)** of the remote server.

### Docker Profiles

Broadsea makes use of [Docker profiles](https://docs.docker.com/compose/profiles/ "Docker Profiles") to allow for either a full default deployment ("default"), or a more a-la-carte approach in which you can pick and choose which services you'd like to deploy.

You can use this syntax for this approach, substituting profile names in:

```shell
docker compose --env-file .env --profile profile1 --profile profile2 ... up -d
```

#### Standard Profiles

| Profile              | Description |
|----------------------|-------------|
| default              | <ul><li>Atlas ("/atlas")</li><li>WebAPI ("/WebAPI")</li><li>AtlasDB (a Postgres instance for Atlas/WebAPI)</li><li>HADES ("/hades")</li><li>A splash page for Broadsea ("/")</li></ul> |
| atlas-from-image     | <ul><li>Pulls the standard Atlas image from Docker Hub</li></ul> |
| atlas-from-git       | <ul><li>Builds Atlas from a Git repo</li><li>Useful for testing new versions of Atlas that aren't in Docker Hub</li></ul> |
| webapi-from-image    | <ul><li>Pulls the standard WebAPI image from Docker Hub</li><li>Mac Silicon users, see "Mac Silicon" section above</li></ul> |
| webapi-from-git      | <ul><li>Builds WebAPI from a Git repo</li><li>Useful for testing new versions of WebAPI that aren't in Docker Hub</li><li>Mac Silicon users, see "Mac Silicon" section above</li></ul> |
| atlasdb              | <ul><li>Pulls the standard Atlas DB image, a Postgres instance for Atlas/WebAPI</li><li>Useful if you do not have an existing Postgres instance for Atlas/WebAPI</li></ul> |
| solr-vocab-no-import | <ul><li>Pulls the standard SOLR image from Docker Hub</li><li>Initializes a core for the OMOP Vocabulary specified in the .env file</li><li>No data is imported into the core, left to you to run through the SOLR Admin GUI at "/solr"</li></ul> |
| solr-vocab-with-import | <ul><li>Pulls the standard SOLR image from Docker Hub</li><li>Initializes a core for the OMOP Vocabulary specified in the .env file</li><li>Runs the data import for that core</li><li>Once complete, the solr-run-import container will finish with an exit status; you can remove this container</li></ul> |
| ares                 | <ul><li>Builds Ares web app from Ares GitHub repo</li><li>Exposes a volume mount point for adding Ares files (see [Ares GitHub IO page](https://ohdsi.github.io/Ares/ "Ares GitHub IO"))</li></ul> |
| content              | <ul><li>A splash page for Broadsea ("/broadsea")</li></ul> |
| omop-vocab-pg-load   | <ul><li>Using OMOP Vocab files downloaded from Athena, this can load them into a Postgres instance (can be Broadsea's atlasdb or an external one)</li><li>Rebuilds the CPTs using the CPT jar file from Athena, with UMLS API Key (see .env file Section 9)</li><li>Creates the schema if necessary</li><li>Runs copy command for each vocabulary CSV file</li><li>Creates all necessary Postgres indices</li><li>Once complete, the omop-vocab-load container will finish with an exit status; you can remove this container</li></ul> |
| phoebe-pg-load       | <ul><li>For Atlas 2.12+, which offers Concept Recommendation options based on the [Phoebe project](https://forums.ohdsi.org/t/phoebe-2-0/17410 "Phoebe Project")</li><li>Loads Phoebe files into an existing OMOP Vocabulary hosted in a Postgres instance (can be Broadsea's atlasdb or an external one)</li><li>Note: your Atlas instance must use this OMOP Vocabulary as its default vocabulary source in order to use this feature</li><li>Once complete, the phoebe-load container will finish with an exit status; you can remove this container</li></ul> |
| openldap             | <ul><li>For testing security in Atlas, this Open LDAP container can be used to assess security needs</li><li>You can specify a comma separated list of user ids and passwords</li><li>This is not recommended for any production level setup</li></ul> |

#### Experimental Profiles

We also offer profiles for Perseus and other useful services, but please note, **these are EXPERIMENTAL and not guaranteed to work**:

| Profile                 | Description |
|-------------------------|-------------|
| perseus                 | <ul><li>Deploys the entire Perseus stack of services, but in the Broadsea network</li><li>Currently, does have overlapping capabilities (e.g. Solr, OMOP Vocab on Postgres</li></ul> |
| perseus-shareddb        | <ul><li>Deploys only the shareddb Postgres backend for Perseus</li></ul> |
| perseus-files-manager   | <ul><li>Deploys only the files-manager backend for Perseus</li></ul> |
| perseus-user            | <ul><li>Deploys only the user management system for Perseus</li></ul> |
| perseus-backend         | <ul><li>Deploys only the API backend for Perseus</li></ul> |
| perseus-frontend        | <ul><li>Deploys only the Perseus web application</li></ul> |
| perseus-vocabularydb    | <ul><li>Deploys only the Vocabulary Postgres for Perseus</li></ul> |
| perseus-cdm-builder     | <ul><li>Deploys only the CDM Builder tool for Perseus</li></ul> |
| perseus-solr            | <ul><li>Deploys only the Solr instance for Perseus</li></ul> |
| perseus-athena          | <ul><li>Deploys only the Athena instance for Perseus</li></ul> |
| perseus-usagi           | <ul><li>Deploys only the Usagi instance for Perseus</li></ul> |
| perseus-r-serve         | <ul><li>Deploys the R Server instance for Perseus</li></ul> |
| perseus-dqd             | <ul><li>Deploys the DataQualityDashboard instance for Perseus</li></ul> |
| perseus-swagger         | <ul><li>Deploys the Swagger instance for Perseus</li></ul> |
| perseus-white-rabbit    | <ul><li>Deploys the White Rabbit instance for Perseus</li></ul> |
| open-shiny-server    | <ul><li>An open source version of Shiny Server, where you can drop shiny apps into a mounted folder.</li><li>Recommended if your organization does not have a Posit Connect license.</li></ul> |
| posit-connect        | <ul><li>For sites with commercial Posit Connect licenses
| pgadmin4                | <ul><li>Deploys the pgAdmin4 web application with a single admin user.</li></ul>
| jupyter-notebook        | <ul><li>Deploys a simple Jupyter Data Science Notebook with no authentication.</li></ul>

### Traefik Dashboard

Broadsea uses Traefik as a proxy for all containers within. The traefik dashboard is enabled by default at `/dashboard/`, and can be useful for debugging the proxy network.

### SSL

Traefik can be set up with SSL to enable HTTPS:

1. Obtain a crt and key file. Rename them to "broadsea.crt" and "broadsea.key", respectively.
2. In Section 1 of the .env file:

- Update the BROADSEA_CERTS_FOLDER to the folder that holds these cert files.
- Update the HTTP_TYPE to "https"

### Broadsea Content Page

To adjust which app links to display on the Broadsea content page ("/"), refer to Section 12 of the .env file. Use "show" to display the div or "none" to hide it.

### Vocabulary Loading

#### OMOP Vocabulary in Postgres

To load a new OMOP Vocabulary into a Postgres schema, review and fill out Section 9 of the .env file. Please note: this service will attempt to run the CPT4 import process for the CONCEPT table, so you will need a UMLS API Key from <https://uts.nlm.nih.gov/uts/profile>; store this in a file and set the path to the file as UMLS_API_KEY_FILE.

The Broadsea atlasdb Postgres instance is listed by default, but you can use an external Postgres instance. You need to copy your Athena downloaded files into ./omop_vocab/files.

#### Build SOLR Vocab for Atlas

>Note: with WebAPI 2.14, you will need to use the webapi-from-git profile and set WEBAPI_MAVEN_PROFILE to webapi-docker,webapi-solr

To enable the use of SOLR for fast OMOP Vocab search in Atlas, review and fill out Section 7 of the .env file. You can either point to an existing SOLR instance, or have Broadsea build one. The JDBC jar file is needed in the Broadsea root folder in order for Solr to perform the dataimport step.

### OHDSI Web Applications

#### Atlas/WebAPI Security

To enable a security provider for authentication and identity management in Atlas/WebAPI, review and fill out Sections 4 and 5 in the .env file.

##### Broadsea-AtlasDB Security  

Atlas database based security is pre-configured by the [Broadsea-AtlasDB](https://github.com/OHDSI/Broadsea-atlasdb) project and can be used as a demo. To enable this security:

1. Update these environment variables in Sections 2, 4, and 5 in the .env file:
    - section 2:
        - ATLAS_USER_AUTH_ENABLED="true"
    - section 4:
        - ATLAS_SECURITY_PROVIDER_TYPE="db"
        - ATLAS_SECURITY_PROVIDER_NAME="DB Security"
        - ATLAS_SECURITY_USE_FORM="true"
        - ATLAS_SECURITY_USE_AJAX="true
    - section 5:
        - WEBAPI_SECURITY_PROVIDER="AtlasRegularSecurity"
        - SECURITY_AUTH_JDBC_ENABLED="true"
2. Start the Broadsea docker containers
3. Login to ATLAS with a demo user defined
    | Role      | Username  | Password  |
    |-----------|-----------|-----------|
    | Admin     | admin     | admin     |
    | Atlas user| ohdsi     | ohdsi     |

#### Bring Your Own JDBC driver

The Docker implementation of WebAPI does not come with all JDBC drivers supported by OHDSI (for example, Snowflake). To add a JDBC driver to the WebAPI build, refer to Section 3 of the .env file and edit the WEBAPI_ADDITIONAL_JDBC_FILE_PATH variable to point to your JDBC driver file.

#### Bring Your Own Cacerts (Java Keystore) for LDAP and Snowflake connections

Some deployments require a Java Keystore (cacerts) file that establishes trust with Root Certificate Authorities for LDAP or Snowflake connections.

To allow this, alter the env variable WEBAPI_CACERTS_FILE to point to your cacerts file. WebAPI can then leverage it for these external Java SSL connections.

For Snowflake, you will need to also set the CDM_SNOWFLAKE_PRIVATE_KEY_FILE env variable in Section 3.

#### Open LDAP

OpenLDAP is provided for testing purposes, and is not recommended for any production deployment. Refer to Section 13 of the .env file to establish user accounts (using secrets files) for this LDAP instance. A GUI-based LDAP explorer, such as [Apache Directory Studio](https://directory.apache.org/studio/ "Apache Directory Studio") is recommended for managing this instance.

#### Atlas/WebAPI from Git repo

To build either Atlas or WebAPI from a git repo instead of from Docker Hub, use Section 6 to specify the Git repo paths. Branches and commits can be in the URL after a "\#".

#### Phoebe Integration for Atlas

With Atlas 2.12.0 and above, a new concept recommendation feature is available, based upon the [Phoebe project](https://forums.ohdsi.org/t/phoebe-2-0/17410 "Phoebe Project"). Review and fill out Section 10 of the .env file to load the concept_recommended table needed for this feature into a Postgres hosted OMOP Vocabulary.

#### Ares Web Application

To mount files prepared for Ares (see [CDM Post Processing](#cdm-post-processing)), add your Ares data folder path to ARES_DATA_FOLDER in Section 11. By default, it will use the Broadsea shared volume `cdm-postprocessing-data/ares` used by the aresindexer service.

### CDM ETL Design and Execution

#### DBT

DBT provides a command-line tool for ETL design. See Section 16 for configuring DBT.

#### Perseus (Experimental)

Perseus offers a full suite of services for data profiling, vocabulary mapping, ETL design, and ETL execution. See Section 16 for configuring Perseus.

#### pgAdmin4 (Experimental) 

New to Broadsea, there's now a profile for deploying the pgAdmin4 web application for database management of Postgres. See Section 18 for setting up the initial default admin username and the password secret file.

### CDM Post Processing

Once you have a CDM database available, it is important to run summary level statistics and data quality analyses prior to publishing the source to users. Broadsea provides services for running Achilles, DataQualityDashboard, and AresIndexer. See Section 17 for setting up the CDM connection details and the various application settings needed.

### Evidence Generation

#### HADES in RStudio

The credentials for the RStudio user can be established in Section 8 of the .env file (with a password stored in a secrets file).

##### Sharing/Saving files between RStudio and Docker host machine

To permanently retain the "rstudio" user files in the "rstudio" user home directory, and make local R packages available to RStudio in the Broadsea Hades container the following steps are required:

- In the same directory where the docker-compose.yml is stored create a sub-directory tree called "home/rstudio" and a sub-directory called "site-library"
- **Set the file permissions for the "home/rstudio" sub-directory tree and the "site-library" sub-directory to public read, write and execute.**
- Add the below volume mapping statements to the end of the broadsea-hades section of the docker-compose.yml file.

```yaml
volumes:
      - ./home/rstudio:/home/rstudio
      - ./site-library:/usr/local/lib/R/site-library
```

Any files added to the home/rstudio or site-library sub-directories on the Docker host can be accessed by RStudio in the container.

The Broadsea Hades container RStudio /usr/lib/R/site-library originally contains the "littler" and "rgl" R packages. Volume mapping masks the original files in the directory so you will need to add those 2 packages to your Docker host site-library sub-directory if you need them.

#### Jupyter Data Science Notebook (Experimental)

New to Broadsea, there's now a profile for launching a simple, single user instance of Jupyter Data Science Notebook.

### Evidence Dissemination

#### Open Shiny Server

To configure an open-source Shiny Server, refer to Section 14 of the .env file. Use the OPEN_SHINY_SERVER_APP_ROOT variable to point to a folder that will host Shiny apps.

#### Posit Connect

The pattern for using Posit Connect deviates from the rest of Broadsea due to the many configuration options available. A sample .gcfg file is included, but you likely will need to make modifications to it. See [Posit Connect configuration guide](https://docs.posit.co/connect/admin/appendix/configuration "Posit Connect Configuration") for more information.

## Shutting Down Broadsea

### Compose Stop vs. Compose Down

If you want to keep a container for use later, you can use ```docker compose stop```. This may be useful when you plan to restart the services later and want to persist the container's state and networks. If you want to remove the containers and recreate them later, use ```docker compose down```. This will remove the containers and networks, but it will keep the volumes.

### Stop Containers

Use the following CLI commands to stop and start Broadsea's containers.

```shell
docker compose stop
docker compose start
```

Or target a specific profile using ```--profile```

```shell
docker compose --profile profile1 stop
docker compose --profile profile1 start
```

### Down Containers

Use the following commands to down and then up Broadsea's containers.

```shell
docker compose down
docker compose --profile default up -d
```

Or target a specific profile using ```--profile```

```shell
docker compose --profile profile1 down
docker compose --profile profile1 up -d
```

## Down and Remove Volumes

By default Docker will create volumes and persist them. Any saved files or custom configs made in the containers themselves will persist through these containers. However, if you want to remove these volumes you can pass ```-v``` with ```docker compose down``` and the next time you compose up new volumes will be created.

```shell
docker compose down -v
docker compose --profile default up -d
```

## Broadsea Intended Uses

Broadsea can deploy the OHDSI stack on any of the following infrastructure alternatives:

- laptop / desktop
- internally hosted server
- cloud provider hosted server
- cluster of servers (internally or cloud provider hosted)

It supports any database management system that the OHDSI stack supports, though some services are specific to Postgresql.

It supports any OS where Docker containers can run, including Windows, Mac OS X, and Linux (including Ubuntu, CentOS & CoreOS).

------------------------------------------------------------------------

## Troubleshooting

### View the status of the running Docker containers

```shell
docker compose ps
```

### Viewing Log Files

Logs per container are available using this syntax:

```shell
docker compose logs --tail=200 service-name
docker compose logs --follow service-name
```

Use Compose service names (for example, `ohdsi-webapi-from-image`) in these
commands. Run `docker compose ps --services` to list them.

### Atlasdb upgrade docker volume error

Remove the `atlasdb-postgres-data` volume only when an intentional database
reset is acceptable. **This permanently deletes the local Atlas/WebAPI database
and any data stored in that volume.** Export or back up anything you need first.

```shell
docker compose down
docker volume rm atlasdb-postgres-data
docker compose --profile default up -d
```

## Hardware/OS Requirements for Installing Docker

Use a currently supported 64-bit operating system and follow Docker's official
[installation documentation](https://docs.docker.com/engine/install/). Docker
Desktop for macOS and Windows includes Compose v2. Linux users install Docker
Engine and the Compose plugin using the packages for their distribution.

On Windows, the WSL 2 backend is recommended. Keep the repository inside the
Linux filesystem for better bind-mount performance and consistent permissions.
Do not mix PowerShell and WSL Docker contexts while operating one deployment.

On macOS, allocate enough memory in Docker Desktop and see
[Architecture and Apple silicon](#architecture-and-apple-silicon). On Linux,
verify that the user running Broadsea can access the Docker daemon and that the
host firewall permits only the intended clients.

## License

Licensed under the Apache License, Version 2.0 (the "License"); you may not use the Broadsea software except in compliance with the License. You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
