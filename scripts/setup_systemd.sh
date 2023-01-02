#!/bin/bash -e

sudo ln -s . /usr/bin/yorstory
sudo cp ./scripts/yorstory.service /etc/systemd/system/yorstory.service
sudo systemctl daemon-reload
sudo systemctl enable yorstory
sudo systemctl start yorstory