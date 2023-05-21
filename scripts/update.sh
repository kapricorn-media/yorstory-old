#!/bin/bash -e

mv yorstory yorstory-prev
mv yorstory.tar.gz yorstory-prev.tar.gz

curl $1 --output yorstory.tar.gz
tar -xf yorstory.tar.gz
cp -r yorstory-prev/data yorstory/data

sudo systemctl restart yorstory
sudo systemctl status yorstory