#!/bin/bash
##############################################################################
# Setup
##############################################################################
if [[ -f /tmp/lab_setup.complete ]] ; then
    echo "Error: Found lab setup already completed"
    echo
    echo "If you need to rerun then remove /tmp/lab_setup.complete first"
    echo "and also consider if any of following should be removed otherwise"
    echo "their setup steps will be skipped:"
    echo
    echo "  /tmp/scale-setup.complete"
    echo "  /tmp/dns-setup.complete"
    echo "  /tmp/acme-setup.complete"
    echo "  /tmp/image-setup.complete"
    exit 1
fi

exec 1> /tmp/lab_setup.stdout
exec 2> /tmp/lab_setup.stderr
set -x

[[ ! -f ./ansible_hostvars.yaml ]] && echo "Error: Missing Ansible Hostvars" && exit 1


##############################################################################
# Spectrum Scale changes
##############################################################################
if [[ ! -f /tmp/scale-setup.complete ]] ; then
    echo "Adjusting Scale config"
    export PATH=$PATH:/usr/lpp/mmfs/bin
    mmchconfig pagepool=256M -i
    [[ $? != 0 ]] && echo "Error: Problem changing Scale pagepool" && exit 1
    mmshutdown --accept
    [[ $? != 0 ]] && echo "Error: Problem shutting down Scale" && exit 1
    mmstartup
    [[ $? != 0 ]] && echo "Error: Problem starting up Scale" && exit 1
    touch /tmp/scale-setup.complete
fi

##############################################################################
# Stage assets
##############################################################################
if [[ ! -d /home/cecuser/assets ]] ; then
    echo "Cloning https://github.com/DanielCasali/assets.git"
    su - cecuser -c "cd /home/cecuser ; git clone https://github.com/DanielCasali/assets.git"
    if [[ $? != 0 ]] ; then
        echo "Error: Problem cloning https://github.com/DanielCasali/assets.git"
        rm -rf /home/cecuser/assets
        exit 1
    fi
fi

##############################################################################
# Pull needed images
##############################################################################
if [[ ! -f /tmp/image-setup.complete ]] ; then
    podman pull quay.io/daniel_casali/source-golang:1.17.7-alpine3.15
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-golang:1.17.7-alpine3.15" && exit 1

    podman tag quay.io/daniel_casali/source-golang:1.17.7-alpine3.15 docker.io/library/golang:1.17.7-alpine3.15
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-golang:1.17.7-alpine3.15" && exit 1

    podman pull quay.io/daniel_casali/source-maven:3.6-jdk-11-openj9
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-maven:3.6-jdk-11-openj9" && exit 1

    podman tag quay.io/daniel_casali/source-maven:3.6-jdk-11-openj9 docker.io/ppc64le/maven:3.6-jdk-11-openj9
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-maven:3.6-jdk-11-openj9" && exit 1

    podman tag quay.io/daniel_casali/source-maven:3.6-jdk-11-openj9 docker.io/library/maven:3.6-jdk-11-openj9
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-maven:3.6-jdk-11-openj9" && exit 1

    podman pull quay.io/daniel_casali/source-ibmjava:8
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-ibmjava:8" && exit 1

    podman tag quay.io/daniel_casali/source-ibmjava:8 docker.io/library/ibmjava:8
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-ibmjava:8" && exit 1

    podman pull quay.io/daniel_casali/usvc-rabbitmq-exporter:ppc64le
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/usvc-rabbitmq-exporter:ppc64le" && exit 1

    podman tag quay.io/daniel_casali/usvc-rabbitmq-exporter:ppc64le docker.io/library/rabbitmq-exporter:ppc64le
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/usvc-rabbitmq-exporter:ppc64le" && exit 1

    podman pull quay.io/daniel_casali/usvc-rabbitmq:management
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/usvc-rabbitmq:management" && exit 1

    podman tag quay.io/daniel_casali/usvc-rabbitmq:management docker.io/library/rabbitmq:management
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/usvc-rabbitmq:management" && exit 1

    podman pull quay.io/daniel_casali/source-golang:1.11
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-golang:1.11" && exit 1

    podman tag quay.io/daniel_casali/source-golang:1.11 docker.io/library/golang:1.11
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-golang:1.11" && exit 1

    podman pull quay.io/daniel_casali/source-alpine:latest
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-alpine:latest" && exit 1

    podman tag quay.io/daniel_casali/source-alpine:latest docker.io/library/alpine:latest
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-alpine:latest" && exit 1

    podman pull quay.io/daniel_casali/source-node:10-alpine
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-node:10-alpine"

    podman tag quay.io/daniel_casali/source-node:10-alpine docker.io/library/node:10-alpine
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-node:10-alpine" && exit 1

    podman pull quay.io/daniel_casali/source-mariadb:10.2.18
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/source-mariadb:10.2.18" && exit 1

    podman tag quay.io/daniel_casali/source-mariadb:10.2.18 docker.io/library/mariadb:10.2.18
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/source-mariadb:10.2.18" && exit 1

    podman pull quay.io/daniel_casali/usvc-redis:alpine
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/usvc-redis:alpine" && exit 1

    podman tag quay.io/daniel_casali/usvc-redis:alpine docker.io/library/redis:alpine
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/usvc-redis:alpine" && exit 1

    podman pull quay.io/daniel_casali/trivy_ppc64le:latest
    [[ $? != 0 ]] && echo "Error: Problem pulling quay.io/daniel_casali/trivy_ppc64le:latest" && exit 1

    podman tag quay.io/daniel_casali/trivy_ppc64le:latest docker.io/aquasec/trivy:latest
    [[ $? != 0 ]] && echo "Error: Problem tagging quay.io/daniel_casali/trivy_ppc64le:latest" && exit 1
    touch /tmp/image-setup.complete
fi

##############################################################################
# Setup complete, cleanup artifacts so no credentials laying around
##############################################################################
date +"%Y/%m/%d %H:%M:%S setup completed" > /tmp/lab_setup.complete

#rm -f ./ansible_hostvars.yaml ./ansible_hostvars.json
#rm -f /tmp/lab_setup.stdout /tmp/lab_setup.stderr
exit 0
