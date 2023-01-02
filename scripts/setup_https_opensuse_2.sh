#!/bin/bash -e

# Ensure we have the latest version of snapd
sudo snap install core
sudo snap refresh core

# Install certbot
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot certonly --standalone --agree-tos --email kapricornmedia@gmail.com -d yorstory.ca -d www.yorstory.ca