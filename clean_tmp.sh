#!/usr/bin/env bash

sudo find /tmp -type f -mtime +0 -exec sudo rm -f {} \;