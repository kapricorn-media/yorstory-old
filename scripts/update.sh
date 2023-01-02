#!/bin/bash -e

rm -rf yorstory*
curl $1 --output yorstory.tar.gz
tar -xf yorstory.tar.gz
sudo systemctl restart yorstory
sudo systemctl status yorstory