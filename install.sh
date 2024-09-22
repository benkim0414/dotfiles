#!/usr/bin/bash

apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get -y install --no-install-recommends rcm
rm -rf /var/lib/apt/lists/*

cp rcrc.devpod $HOME/.rcrc
rcup -v
