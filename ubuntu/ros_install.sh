#!/bin/bash -e

sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
sudo apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654
sudo apt update


if [ $(lsb_release -sc) == "bionic" ]; then
    ros_ver=melodic
elif [ $(lsb_release -sc) == "focal" ]; then
    ros_ver=noetic
else
    echo "No support version of ros !!!"
    exit 1
fi

sudo apt -y install ros-$ros_ver-desktop-full

echo "source /opt/ros/${ros_ver}/setup.bash" >> ~/.bashrc
source ~/.bashrc

if [ $ros_ver == "melodic" ]; then
    sudo apt-get -y install python-rosinstall python-rosinstall-generator python-wstool build-essential
fi



