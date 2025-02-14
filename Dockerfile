# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# THIS DOCKERFILE IS INTENDED FOR PRODUCTION USE AND DEPLOYMENT.
# NOTE! IT IS ALPHA-QUALITY FOR NOW - WE ARE IN A PROCESS OF TESTING IT
#
#
# This is a multi-segmented image. It actually contains two images:
#
# airflow-build-image  - there all airflow dependencies can be installed (and
#                        built - for those dependencies that require
#                        build essentials). Airflow is installed there with
#                        --user switch so that all the dependencies are
#                        installed to ${HOME}/.local
#
# main                 - this is the actual production image that is much
#                        smaller because it does not contain all the build
#                        essentials. Instead the ${HOME}/.local folder
#                        is copied from the build-image - this way we have
#                        only result of installation and we do not need
#                        all the build essentials. This makes the image
#                        much smaller.
#
ARG AIRFLOW_VERSION="2.0.0.dev0"
ARG AIRFLOW_EXTRAS="async,amazon,celery,cncf.kubernetes,docker,dask,elasticsearch,ftp,grpc,hashicorp,http,ldap,google,microsoft.azure,mysql,postgres,redis,sendgrid,snowflake,sftp,slack,ssh,statsd,virtualenv"
ARG ADDITIONAL_AIRFLOW_EXTRAS=""
ARG ADDITIONAL_PYTHON_DEPS=""

ARG AIRFLOW_HOME=/opt/airflow
ARG AIRFLOW_UID="50000"
ARG AIRFLOW_GID="50000"

ARG CASS_DRIVER_BUILD_CONCURRENCY="8"

ARG PYTHON_BASE_IMAGE="python:3.8-slim-buster"
ARG PYTHON_MAJOR_MINOR_VERSION="3.8"

ARG AIRFLOW_PIP_VERSION=20.3.3

##############################################################################################
# This is the build image where we build all dependencies
##############################################################################################
FROM ${PYTHON_BASE_IMAGE} as airflow-build-image
SHELL ["/bin/bash", "-o", "pipefail", "-e", "-u", "-x", "-c"]

ARG PYTHON_BASE_IMAGE
ENV PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE}

ARG PYTHON_MAJOR_MINOR_VERSION
ENV PYTHON_MAJOR_MINOR_VERSION=${PYTHON_MAJOR_MINOR_VERSION}

ARG AIRFLOW_PIP_VERSION
ENV AIRFLOW_PIP_VERSION=${AIRFLOW_PIP_VERSION}

# Make sure noninteractive debian install is used and language variables set
ENV DEBIAN_FRONTEND=noninteractive LANGUAGE=C.UTF-8 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 LC_MESSAGES=C.UTF-8

# Install curl and gnupg2 - needed for many other installation steps
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           curl \
           gnupg2 \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG DEV_APT_DEPS="\
     apt-transport-https \
     apt-utils \
     build-essential \
     ca-certificates \
     gnupg \
     dirmngr \
     freetds-bin \
     freetds-dev \
     gosu \
     krb5-user \
     ldap-utils \
     libffi-dev \
     libkrb5-dev \
     libldap2-dev \
     libpq-dev \
     libsasl2-2 \
     libsasl2-dev \
     libsasl2-modules \
     libssl-dev \
     locales  \
     lsb-release \
     nodejs \
     openssh-client \
     postgresql-client \
     python-selinux \
     sasl2-bin \
     software-properties-common \
     sqlite3 \
     sudo \
     unixodbc \
     unixodbc-dev \
     yarn"
ENV DEV_APT_DEPS=${DEV_APT_DEPS}

ARG ADDITIONAL_DEV_APT_DEPS=""
ENV ADDITIONAL_DEV_APT_DEPS=${ADDITIONAL_DEV_APT_DEPS}

ARG DEV_APT_COMMAND="\
    curl --fail --location https://deb.nodesource.com/setup_10.x | bash - \
    && curl https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - > /dev/null \
    && echo 'deb https://dl.yarnpkg.com/debian/ stable main' > /etc/apt/sources.list.d/yarn.list"
ENV DEV_APT_COMMAND=${DEV_APT_COMMAND}

ARG ADDITIONAL_DEV_APT_COMMAND="echo"
ENV ADDITIONAL_DEV_APT_COMMAND=${ADDITIONAL_DEV_APT_COMMAND}

ARG ADDITIONAL_DEV_APT_ENV=""

# Note missing man directories on debian-buster
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
# Install basic and additional apt dependencies
RUN mkdir -pv /usr/share/man/man1 \
    && mkdir -pv /usr/share/man/man7 \
    && export ${ADDITIONAL_DEV_APT_ENV?} \
    && bash -o pipefail -e -u -x -c "${DEV_APT_COMMAND}" \
    && bash -o pipefail -e -u -x -c "${ADDITIONAL_DEV_APT_COMMAND}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
           ${DEV_APT_DEPS} \
           ${ADDITIONAL_DEV_APT_DEPS} \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG INSTALL_MYSQL_CLIENT="true"
ENV INSTALL_MYSQL_CLIENT=${INSTALL_MYSQL_CLIENT}

COPY scripts/docker /scripts/docker
COPY docker-context-files /docker-context-files
# fix permission issue in Azure DevOps when running the script
RUN chmod a+x /scripts/docker/install_mysql.sh
RUN ./scripts/docker/install_mysql.sh dev

ARG AIRFLOW_REPO=apache/airflow
ENV AIRFLOW_REPO=${AIRFLOW_REPO}

ARG AIRFLOW_BRANCH=master
ENV AIRFLOW_BRANCH=${AIRFLOW_BRANCH}

ARG AIRFLOW_EXTRAS
ARG ADDITIONAL_AIRFLOW_EXTRAS=""
ENV AIRFLOW_EXTRAS=${AIRFLOW_EXTRAS}${ADDITIONAL_AIRFLOW_EXTRAS:+,}${ADDITIONAL_AIRFLOW_EXTRAS}

ARG AIRFLOW_CONSTRAINTS_REFERENCE="constraints-master"
ARG AIRFLOW_CONSTRAINTS_LOCATION="https://raw.githubusercontent.com/apache/airflow/${AIRFLOW_CONSTRAINTS_REFERENCE}/constraints-${PYTHON_MAJOR_MINOR_VERSION}.txt"
ENV AIRFLOW_CONSTRAINTS_LOCATION=${AIRFLOW_CONSTRAINTS_LOCATION}

ENV PATH=${PATH}:/root/.local/bin
RUN mkdir -p /root/.local/bin

RUN if [[ -f /docker-context-files/.pypirc ]]; then \
        cp /docker-context-files/.pypirc /root/.pypirc; \
    fi

RUN pip install --upgrade "pip==${AIRFLOW_PIP_VERSION}"

# By default we do not use pre-cached packages, but in CI/Breeze environment we override this to speed up
# builds in case setup.py/setup.cfg changed. This is pure optimisation of CI/Breeze builds.
ARG AIRFLOW_PRE_CACHED_PIP_PACKAGES="false"
ENV AIRFLOW_PRE_CACHED_PIP_PACKAGES=${AIRFLOW_PRE_CACHED_PIP_PACKAGES}

# In case of Production build image segment we want to pre-install master version of airflow
# dependencies from GitHub so that we do not have to always reinstall it from the scratch.
RUN if [[ ${AIRFLOW_PRE_CACHED_PIP_PACKAGES} == "true" ]]; then \
       if [[ ${INSTALL_MYSQL_CLIENT} != "true" ]]; then \
          AIRFLOW_EXTRAS=${AIRFLOW_EXTRAS/mysql,}; \
       fi; \
       pip install --user \
          "https://github.com/${AIRFLOW_REPO}/archive/${AIRFLOW_BRANCH}.tar.gz#egg=apache-airflow[${AIRFLOW_EXTRAS}]" \
          --constraint "${AIRFLOW_CONSTRAINTS_LOCATION}" \
          && pip uninstall --yes apache-airflow; \
    fi

# By default we install latest airflow from PyPI so we do not need to copy sources of Airflow
# but in case of breeze/CI builds we use latest sources and we override those
# those SOURCES_FROM/TO with "." and "/opt/airflow" respectively
ARG AIRFLOW_SOURCES_FROM="empty"
ENV AIRFLOW_SOURCES_FROM=${AIRFLOW_SOURCES_FROM}

ARG AIRFLOW_SOURCES_TO="/empty"
ENV AIRFLOW_SOURCES_TO=${AIRFLOW_SOURCES_TO}

COPY ${AIRFLOW_SOURCES_FROM} ${AIRFLOW_SOURCES_TO}

ARG CASS_DRIVER_BUILD_CONCURRENCY
ENV CASS_DRIVER_BUILD_CONCURRENCY=${CASS_DRIVER_BUILD_CONCURRENCY}

# This is airflow version that is put in the label of the image build
ARG AIRFLOW_VERSION
ENV AIRFLOW_VERSION=${AIRFLOW_VERSION}

ARG ADDITIONAL_PYTHON_DEPS=""
ENV ADDITIONAL_PYTHON_DEPS=${ADDITIONAL_PYTHON_DEPS}

# Determines the way airflow is installed. By default we install airflow from PyPI `apache-airflow` package
# But it also can be `.` from local installation or GitHub URL pointing to specific branch or tag
# Of Airflow. Note That for local source installation you need to have local sources of
# Airflow checked out together with the Dockerfile and AIRFLOW_SOURCES_FROM and AIRFLOW_SOURCES_TO
# set to "." and "/opt/airflow" respectively.
ARG AIRFLOW_INSTALLATION_METHOD="apache-airflow"
ENV AIRFLOW_INSTALLATION_METHOD=${AIRFLOW_INSTALLATION_METHOD}

# By default latest released version of airflow is installed (when empty) but this value can be overridden
# and we can install specific version of airflow this way.
ARG AIRFLOW_INSTALL_VERSION=""
ENV AIRFLOW_INSTALL_VERSION=${AIRFLOW_INSTALL_VERSION}

# We can seet this value to true in case we want to install .whl .tar.gz packages placed in the
# docker-context-files folder. This can be done for both - additional packages you want to install
# and for airflow as well (you have to set INSTALL_FROM_PYPI to false in this case)
ARG INSTALL_FROM_DOCKER_CONTEXT_FILES=""
ENV INSTALL_FROM_DOCKER_CONTEXT_FILES=${INSTALL_FROM_DOCKER_CONTEXT_FILES}

# By default we install latest airflow from PyPI. You can set it to false if you want to install
# Airflow from the .whl or .tar.gz packages placed in `docker-context-files` folder.
ARG INSTALL_FROM_PYPI="true"
ENV INSTALL_FROM_PYPI=${INSTALL_FROM_PYPI}

# By default we install providers from PyPI but in case of Breze build we want to install providers
# from local sources without the neeed of preparing provider packages upfront. This value is
# automatically overridden by Breeze scripts.
ARG INSTALL_PROVIDERS_FROM_SOURCES="false"
ENV INSTALL_PROVIDERS_FROM_SOURCES=${INSTALL_PROVIDERS_FROM_SOURCES}

ARG UPGRADE_TO_NEWER_DEPENDENCIES="false"
ENV UPGRADE_TO_NEWER_DEPENDENCIES=${UPGRADE_TO_NEWER_DEPENDENCIES}

WORKDIR /opt/airflow

# remove mysql from extras if client is not installed
RUN if [[ ${INSTALL_MYSQL_CLIENT} != "true" ]]; then \
        AIRFLOW_EXTRAS=${AIRFLOW_EXTRAS/mysql,}; \
    fi; \
    if [[ ${INSTALL_FROM_PYPI} == "true" ]]; then \
        if [[ "${UPGRADE_TO_NEWER_DEPENDENCIES}" != "false" ]]; then \
            pip install --user "${AIRFLOW_INSTALLATION_METHOD}[${AIRFLOW_EXTRAS}]${AIRFLOW_INSTALL_VERSION}" \
                --upgrade --upgrade-strategy eager; \
        else \
            pip install --user "${AIRFLOW_INSTALLATION_METHOD}[${AIRFLOW_EXTRAS}]${AIRFLOW_INSTALL_VERSION}" \
                --constraint "${AIRFLOW_CONSTRAINTS_LOCATION}"; \
        fi; \
    fi; \
    if [[ -n "${ADDITIONAL_PYTHON_DEPS}" ]]; then \
        if [[ "${UPGRADE_TO_NEWER_DEPENDENCIES}" != "false" ]]; then \
            pip install --user ${ADDITIONAL_PYTHON_DEPS} --upgrade --upgrade-strategy eager; \
        else \
            pip install --user ${ADDITIONAL_PYTHON_DEPS} --constraint "${AIRFLOW_CONSTRAINTS_LOCATION}"; \
        fi; \
    fi; \
    if [[ ${INSTALL_FROM_DOCKER_CONTEXT_FILES} == "true" ]]; then \
        if ls /docker-context-files/*.{whl,tar.gz} 1> /dev/null 2>&1; then \
            pip install --user --no-deps /docker-context-files/*.{whl,tar.gz}; \
        fi ; \
    fi; \
    find /root/.local/ -name '*.pyc' -print0 | xargs -0 rm -r || true ; \
    find /root/.local/ -type d -name '__pycache__' -print0 | xargs -0 rm -r || true

RUN AIRFLOW_SITE_PACKAGE="/root/.local/lib/python${PYTHON_MAJOR_MINOR_VERSION}/site-packages/airflow"; \
    if [[ -f "${AIRFLOW_SITE_PACKAGE}/www_rbac/package.json" ]]; then \
        WWW_DIR="${AIRFLOW_SITE_PACKAGE}/www_rbac"; \
    elif [[ -f "${AIRFLOW_SITE_PACKAGE}/www/package.json" ]]; then \
        WWW_DIR="${AIRFLOW_SITE_PACKAGE}/www"; \
    fi; \
    if [[ ${WWW_DIR:=} != "" ]]; then \
        yarn --cwd "${WWW_DIR}" install --frozen-lockfile --no-cache; \
        yarn --cwd "${WWW_DIR}" run prod; \
        rm -rf "${WWW_DIR}/node_modules"; \
        rm -vf "${WWW_DIR}"/{package.json,yarn.lock,.eslintignore,.eslintrc,.stylelintignore,.stylelintrc,compile_assets.sh,webpack.config.js} ;\
    fi

# make sure that all directories and files in .local are also group accessible
RUN find /root/.local -executable -print0 | xargs --null chmod g+x && \
    find /root/.local -print0 | xargs --null chmod g+rw


ARG BUILD_ID
ENV BUILD_ID=${BUILD_ID}
ARG COMMIT_SHA
ENV COMMIT_SHA=${COMMIT_SHA}


LABEL org.apache.airflow.distro="debian" \
  org.apache.airflow.distro.version="buster" \
  org.apache.airflow.module="airflow" \
  org.apache.airflow.component="airflow" \
  org.apache.airflow.image="airflow-build-image" \
  org.apache.airflow.version="${AIRFLOW_VERSION}" \
  org.apache.airflow.buildImage.buildId=${BUILD_ID} \
  org.apache.airflow.buildImage.commitSha=${COMMIT_SHA}

##############################################################################################
# This is the actual Airflow image - much smaller than the build one. We copy
# installed Airflow and all it's dependencies from the build image to make it smaller.
##############################################################################################
FROM ${PYTHON_BASE_IMAGE} as main
SHELL ["/bin/bash", "-o", "pipefail", "-e", "-u", "-x", "-c"]

ARG AIRFLOW_UID
ARG AIRFLOW_GID

LABEL org.apache.airflow.distro="debian" \
  org.apache.airflow.distro.version="buster" \
  org.apache.airflow.module="airflow" \
  org.apache.airflow.component="airflow" \
  org.apache.airflow.image="airflow" \
  org.apache.airflow.uid="${AIRFLOW_UID}" \
  org.apache.airflow.gid="${AIRFLOW_GID}"

ARG PYTHON_BASE_IMAGE
ENV PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE}

ARG AIRFLOW_VERSION
ENV AIRFLOW_VERSION=${AIRFLOW_VERSION}

# Make sure noninteractive debian install is used and language variables set
ENV DEBIAN_FRONTEND=noninteractive LANGUAGE=C.UTF-8 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 LC_MESSAGES=C.UTF-8

ARG AIRFLOW_PIP_VERSION
ENV AIRFLOW_PIP_VERSION=${AIRFLOW_PIP_VERSION}

# Install curl and gnupg2 - needed for many other installation steps
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           curl \
           gnupg2 \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG RUNTIME_APT_DEPS="\
       apt-transport-https \
       apt-utils \
       ca-certificates \
       curl \
       dumb-init \
       freetds-bin \
       gnupg \
       gosu \
       krb5-user \
       ldap-utils \
       libffi6 \
       libldap-2.4-2 \
       libsasl2-2 \
       libsasl2-modules \
       libssl1.1 \
       locales  \
       lsb-release \
       netcat \
       openssh-client \
       postgresql-client \
       rsync \
       sasl2-bin \
       sqlite3 \
       sudo \
       unixodbc"
ENV RUNTIME_APT_DEPS=${RUNTIME_APT_DEPS}

ARG ADDITIONAL_RUNTIME_APT_DEPS=""
ENV ADDITIONAL_RUNTIME_APT_DEPS=${ADDITIONAL_RUNTIME_APT_DEPS}

ARG RUNTIME_APT_COMMAND="echo"
ENV RUNTIME_APT_COMMAND=${RUNTIME_APT_COMMAND}

ARG ADDITIONAL_RUNTIME_APT_COMMAND=""
ENV ADDITIONAL_RUNTIME_APT_COMMAND=${ADDITIONAL_RUNTIME_APT_COMMAND}

ARG ADDITIONAL_RUNTIME_APT_ENV=""

# Note missing man directories on debian-buster
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
# Install basic and additional apt dependencies
RUN mkdir -pv /usr/share/man/man1 \
    && mkdir -pv /usr/share/man/man7 \
    && export ${ADDITIONAL_RUNTIME_APT_ENV?} \
    && bash -o pipefail -e -u -x -c "${RUNTIME_APT_COMMAND}" \
    && bash -o pipefail -e -u -x -c "${ADDITIONAL_RUNTIME_APT_COMMAND}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
           ${RUNTIME_APT_DEPS} \
           ${ADDITIONAL_RUNTIME_APT_DEPS} \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG INSTALL_MYSQL_CLIENT="true"
ENV INSTALL_MYSQL_CLIENT=${INSTALL_MYSQL_CLIENT}

COPY scripts/docker /scripts/docker
# fix permission issue in Azure DevOps when running the script
RUN chmod a+x /scripts/docker/install_mysql.sh
RUN ./scripts/docker/install_mysql.sh prod

ENV AIRFLOW_UID=${AIRFLOW_UID}
ENV AIRFLOW_GID=${AIRFLOW_GID}

ENV AIRFLOW__CORE__LOAD_EXAMPLES="false"

ARG AIRFLOW_USER_HOME_DIR=/home/airflow
ENV AIRFLOW_USER_HOME_DIR=${AIRFLOW_USER_HOME_DIR}

RUN addgroup --gid "${AIRFLOW_GID}" "airflow" && \
    adduser --quiet "airflow" --uid "${AIRFLOW_UID}" \
        --gid "${AIRFLOW_GID}" \
        --home "${AIRFLOW_USER_HOME_DIR}"

ARG AIRFLOW_HOME
ENV AIRFLOW_HOME=${AIRFLOW_HOME}

# Make Airflow files belong to the root group and are accessible. This is to accommodate the guidelines from
# OpenShift https://docs.openshift.com/enterprise/3.0/creating_images/guidelines.html
RUN mkdir -pv "${AIRFLOW_HOME}"; \
    mkdir -pv "${AIRFLOW_HOME}/dags"; \
    mkdir -pv "${AIRFLOW_HOME}/logs"; \
    chown -R "airflow:root" "${AIRFLOW_USER_HOME_DIR}" "${AIRFLOW_HOME}"; \
    find "${AIRFLOW_HOME}" -executable -print0 | xargs --null chmod g+x && \
        find "${AIRFLOW_HOME}" -print0 | xargs --null chmod g+rw

COPY --chown=airflow:root --from=airflow-build-image /root/.local "${AIRFLOW_USER_HOME_DIR}/.local"

COPY --chown=airflow:root scripts/in_container/prod/entrypoint_prod.sh /entrypoint
COPY --chown=airflow:root scripts/in_container/prod/clean-logs.sh /clean-logs
RUN chmod a+x /entrypoint /clean-logs

RUN pip install --upgrade "pip==${AIRFLOW_PIP_VERSION}"

# Make /etc/passwd root-group-writeable so that user can be dynamically added by OpenShift
# See https://github.com/apache/airflow/issues/9248
RUN chmod g=u /etc/passwd

ENV PATH="${AIRFLOW_USER_HOME_DIR}/.local/bin:${PATH}"
ENV GUNICORN_CMD_ARGS="--worker-tmp-dir /dev/shm"

WORKDIR ${AIRFLOW_HOME}

EXPOSE 8080

USER ${AIRFLOW_UID}

ARG BUILD_ID
ENV BUILD_ID=${BUILD_ID}
ARG COMMIT_SHA
ENV COMMIT_SHA=${COMMIT_SHA}

LABEL org.apache.airflow.distro="debian" \
  org.apache.airflow.distro.version="buster" \
  org.apache.airflow.module="airflow" \
  org.apache.airflow.component="airflow" \
  org.apache.airflow.image="airflow" \
  org.apache.airflow.version="${AIRFLOW_VERSION}" \
  org.apache.airflow.uid="${AIRFLOW_UID}" \
  org.apache.airflow.gid="${AIRFLOW_GID}" \
  org.apache.airflow.mainImage.buildId=${BUILD_ID} \
  org.apache.airflow.mainImage.commitSha=${COMMIT_SHA}

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint"]
CMD ["--help"]
