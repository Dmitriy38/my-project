#!/bin/bash -xe
sudo apt update -y
sudo apt install nginx -y
systemctl start nginx
