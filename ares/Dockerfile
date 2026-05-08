FROM docker.io/rocker/r-ver:4.2.3

ARG ACHILLES_GITHUB_REF=main
ARG ARESINDEXER_GITHUB_REF=dockerfile

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-11-jdk \
    build-essential \
    gfortran \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpcre2-dev \
    liblzma-dev \
    libbz2-dev \
    zlib1g-dev \
    libicu-dev \
    libtirpc-dev \
    git \
    make \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV LD_LIBRARY_PATH=${JAVA_HOME}/lib/server:${LD_LIBRARY_PATH}

RUN R CMD javareconf

RUN install2.r --error --ncpus 2 --skipinstalled --repos "https://packagemanager.posit.co/cran/latest" \
    rJava \
    remotes \
    ParallelLogger \
    SqlRender \
    DatabaseConnector

RUN R -e "library(rJava); library(SqlRender); library(DatabaseConnector)"

RUN --mount=type=secret,id=GITHUB_PAT,required=false \
    if [ -f /run/secrets/GITHUB_PAT ]; then \
      export GITHUB_PAT="$(cat /run/secrets/GITHUB_PAT)"; \
    fi; \
    R -e "remotes::install_github(repo = 'OHDSI/Achilles', ref = '${ACHILLES_GITHUB_REF}')"

RUN --mount=type=secret,id=GITHUB_PAT,required=false \
    if [ -f /run/secrets/GITHUB_PAT ]; then \
      export GITHUB_PAT="$(cat /run/secrets/GITHUB_PAT)"; \
    fi; \
    R -e "remotes::install_github(repo = 'alondhe/AresIndexer', ref = '${ARESINDEXER_GITHUB_REF}')"

RUN R -e "library(Achilles)"