#!/bin/bash

echo $* 1> /tmp/userexit.$$ 2>&1
exit 0
