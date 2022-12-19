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

[[ ! -f ./ansible_hostvars.yaml ]] && echo "Error: Missing Ansible Hostvars" && exit 1

export LABGROUP=lab$(awk '/^tz_workshop_lab_set/ {print $2; exit 0}' ./ansible_hostvars.yaml)
[[ -z $LABGROUP ]] && echo "Error: Missing lab set" && exit 1
echo "Preparing lab set $LABGROUP"

export RAMDOMSEED=$(awk '/tz_randomseed/ {print $2; exit 0}' ./ansible_hostvars.yaml)
[[ -z $RAMDOMSEED ]] && echo "Error: Missing randomseed" && exit 1
export HEADERS=$(echo $RAMDOMSEED | base64 -d |sed 's/9/:/')
[[ $? != 0 ]] && echo "Error: Problem extracting header" && exit 1

export MAINDOMAIN=power10.pro

##############################################################################
# Networking and haproxy changes
##############################################################################
if [ $(ip a sh |grep "global noprefixroute env32"|awk '{print $2}' |cut -d/ -f1 |wc -l) -eq 1 ]
then
    export INITIALIP=$(ip a sh |grep "global noprefixroute env32"|awk '{print $2}' |cut -d/ -f1)

    FIRST=$(echo $INITIALIP |cut -d. -f1-3)
    SECOND=$(echo $INITIALIP |cut -d. -f4)

    export VIRTUALIP=$FIRST.$(echo $SECOND+3|bc)
    export MASTERIP=$FIRST.$(echo $SECOND+2|bc)

    nmcli con mod "System env32" +ipv4.addresses "$VIRTUALIP/28"
    nmcli conn down "System env32" ; nmcli conn up "System env32"

    sed -i "s/*:80/$INITIALIP:80/" /etc/haproxy/haproxy.cfg
    sed -i "s/*:443/$INITIALIP:443/" /etc/haproxy/haproxy.cfg

    if [ $(grep vanity /etc/haproxy/haproxy.cfg|wc -l) -eq 0 ]
    then
        echo "frontend ingress-http-vanity
    bind $VIRTUALIP:80
    default_backend ingress-http-vanity
    option tcplog   

backend ingress-http-vanity
    balance source
    server http-router1 $MASTERIP:32080 check

frontend ingress-https-vanity
    bind $VIRTUALIP:443
    default_backend ingress-https-vanity
    option tcplog
​
backend ingress-https-vanity
    balance source
    server https-router1 $MASTERIP:32443 check" >> /etc/haproxy/haproxy.cfg
    fi
    systemctl restart haproxy
    [[ $? != 0 ]] && echo "Error: Problem restarting haproxy" && exit 1
​else
    export INITIALIP=$(ip a sh |grep "global noprefixroute env32"|awk '{print $2}' |cut -d/ -f1|head -1)
    export VIRTUALIP=$(ip a sh |grep "global noprefixroute env32"|awk '{print $2}' |cut -d/ -f1|head -2)
fi

##############################################################################
# Spectrum Scale changes
##############################################################################
if [[ ! -f /tmp/scale-setup.complete ]] ; then
    echo "Adjusting Scale config"
    mmchconfig pagepool=256M -i
    [[ $? != 0 ]] && echo "Error: Problem changing Scale pagepool" && exit 1
    mmshutdown --accept
    [[ $? != 0 ]] && echo "Error: Problem shutting down Scale" && exit 1
    mmstartup
    [[ $? != 0 ]] && echo "Error: Problem starting up Scale" && exit 1
    touch /tmp/scale-setup.complete
fi

##############################################################################
# Clone acme repo, this clones into root and unsure this needed since it is
# then cloned under certusr and configured there...
##############################################################################
if [[ ! -d ~root/acmecert ]] ; then
    git clone https://github.com/DanielCasali/acmecert.git
    if [[ $? != 0 ]] ; then
        echo "Error: Problem cloning https://github.com/DanielCasali/acmecert.git"
        rm -rf ~root/acmecert
        exit 1
    fi
fi

##############################################################################
# Update DNS entry
##############################################################################
if [[ ! -f /tmp/dns-setup.complete ]] ; then
    echo "Updating DNS"
    curl -X PUT -H "$HEADERS" -H "Content-Type: application/json" -d '[ { "data": "'$VIRTUALIP'", "name": "subdomainName", "port": 65535, "priority": 10, "protocol": "string", "service": "string", "ttl": 600, "type": "A" } ]' "https://api.godaddy.com/v1/domains/$MAINDOMAIN/records/A/*.$LABGROUP"
    [[ $? != 0 ]] && echo "Error: Problem adding DNS record" && exit 1
    touch /tmp/dns-setup.complete
fi

##############################################################################
# Certificate generation and staging
##############################################################################
if [[ ! -f /tmp/acme-setup.complete ]] ; then
    echo "Preparing certificate"
    grep -Eq "^certusr" /etc/passwd
    if [[ $? != 0 ]] ; then
        useradd certusr
        [[ $? != 0 ]] && echo "Error: Problem creating certusr" && exit 1
    fi

    if [[ ! -d /home/certusr/acmecert ]] ; then
        su - certusr -c "cd /home/certusr ; git clone https://github.com/DanielCasali/acmecert.git"
        if [[ $? != 0 ]] ; then
            echo "Error: Problem cloning https://github.com/DanielCasali/acmecert.git"
            rm -rf /home/certusr/acmecert
            exit 1
        fi
    fi

    su - certusr -c " cd /home/certusr/acmecert ; /home/certusr/acmecert/acme.sh --install -m danielc.domain@gmail.com"
    [[ $? != 0 ]] && echo "Error: Problem installing acme.sh" && exit 1

    su - certusr -c " cd /home/certusr/acmecert ; /home/certusr/acmecert/acme.sh --set-default-ca --server letsencrypt"
    ​[[ $? != 0 ]] && echo "Error: Problem setting default ca for acme.sh" && exit 1

    export TXTENTRY=$(su - certusr -c "/home/certusr/acmecert/acme.sh --issue  --dns  -d *.$LABGROUP.$MAINDOMAIN  --yes-I-know-dns-manual-mode-enough-go-ahead-please 2>&1 "|grep 'value:' |awk '{print $NF}'|tr -d \')
    [[ -z $TXTENTRY ]] && echo "Error: Problem obaining challenge text entry" && exit 1
​
    echo "Adding $TXTENTRY to DNS for challenge response"
    curl -X PUT -H "$HEADERS" -H "Content-Type: application/json" -d '[ { "data": "'$TXTENTRY'", "name": "subdomainName", "port": 65535, "priority": 10, "protocol": "string", "service": "string", "ttl": 600, "type": "TXT" } ]' "https://api.godaddy.com/v1/domains/$MAINDOMAIN/records/TXT/_acme-challenge.$LABGROUP"
    [[ $? != 0 ]] && echo "Error: Problem adding challenge response text to DNS" && exit 1

    sleep 20
    su - certusr -c "cd /home/certusr/acmecert ; /home/certusr/acmecert/acme.sh --renew -d *.$LABGROUP.$MAINDOMAIN  --yes-I-know-dns-manual-mode-enough-go-ahead-please"
    [[ $? != 0 ]] && echo "Error: Problem completing challenge" && exit 1

    ​mkdir /home/cecuser/certs
    cp /home/certusr/.acme.sh/*.$LABGROUP.$MAINDOMAIN/fullchain.cer /home/cecuser/certs/fullchain.cer
    [[ $? != 0 ]] && echo "Error: Problem copying fullchain.cer to cecuser certs" && exit 1
    cp /home/certusr/.acme.sh/*.$LABGROUP.$MAINDOMAIN/*.$LABGROUP.$MAINDOMAIN.key /home/cecuser/certs/fullchainkey.key
    [[ $? != 0 ]] && echo "Error: Problem copying fullchainkey.key to cecuser certs" && exit 1
    chown -R cecuser:cecuser /home/cecuser/certs
    touch /tmp/acme-setup.complete
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

rm -f ./ansible_hostvars.yaml ./ansible_hostvars.json
rm -f /tmp/lab_setup.stdout /tmp/lab_setup.stderr
exit 0
