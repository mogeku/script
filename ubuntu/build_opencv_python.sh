#!/bin/bash -e

sudo apt -y install pkg-config libavcodec-dev libavformat-dev libavutil-dev libswscale-dev

git clone --recursive https://github.com/opencv/opencv-python.git

cd opencv-python

pip wheel . --verbose
