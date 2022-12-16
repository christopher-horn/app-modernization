#!/bin/bash

[[ -f ./ansible_hostvars.json ]] && echo "Found ansible_hostvars.json"
[[ -f ./ansible_hostvars.yaml ]] && echo "Found ansible_hostvars.yaml"
echo
env

exit 0
