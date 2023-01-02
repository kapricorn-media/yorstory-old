#!/bin/bash -e

sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
sudo certbot certonly --standalone --agree-tos --email kapricornmedia@gmail.com -d yorstory.ca -d www.yorstory.ca