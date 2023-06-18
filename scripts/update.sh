#!/bin/bash -e

PROJECT_NAME=yorstory

if [ "$#" -ne 1 ]; then
    echo "Missing argument <url>"
    exit 1
fi

if test -f "$PROJECT_NAME-prev.tar.gz"; then
    mv $PROJECT_NAME $PROJECT_NAME-prev
    mv $PROJECT_NAME.tar.gz $PROJECT_NAME-prev.tar.gz
fi

curl $1 --output $PROJECT_NAME.tar.gz
tar -xf $PROJECT_NAME.tar.gz
cp -r $PROJECT_NAME-prev/data $PROJECT_NAME/data

sudo systemctl restart $PROJECT_NAME
sudo systemctl status $PROJECT_NAME