#!/bin/bash -e

# 配置变量
cur_dir=$(pwd)

# 更换阿里源;
if [ ! -e /etc/apt/sources.list.bak ]; then
	sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
fi
sudo chmod 777 /etc/apt/sources.list

sudo sed -i "s@http://.*archive.ubuntu.com@https://mirrors.tuna.tsinghua.edu.cn@g" /etc/apt/sources.list
sudo sed -i "s@http://.*security.ubuntu.com@https://mirrors.tuna.tsinghua.edu.cn@g" /etc/apt/sources.list

sudo apt update

# 设置sudo的超时为10分钟
sudo sed -i 's/env_reset$/env_reset,timestamp_timeout=10/' /etc/sudoers

# 安装一个终端打印标题的软件;
sudo apt install -y figlet

# 拉取.config目录
figlet ".config"
rm -rf ~/.config
git clone --recurse-submodules git@github.com:mogeku/.config.git ~/.config
rm ~/.bashrc && ln -sf ~/.config/.bashrc ~/.bashrc

# 安装一些工具；
figlet 'tools'
sudo apt install -y neofetch
sudo apt install -y tree
sudo apt install -y curl
sudo apt install -y ripgrep
sudo apt install -y feh
sudo apt install -y tldr
sudo apt install -y openssl-server
sudo apt install -y trayer
sudo apt install -y xsel xclip
sudo apt install -y blueman

tldr tldr

sudo apt install -y apt-file
sudo apt-file update

# 安装 fd
sudo apt install -y fd-find
sudo ln -sf $(which fdfind) /usr/local/bin/fd

# fish
figlet 'fish'
sudo apt-add-repository -y ppa:fish-shell/release-3
sudo apt update
sudo apt install -y fish
chsh -s /usr/bin/fish

# 安装exa
sudo ln -sf $HOME/.config/script/exa/bin/exa /usr/local/bin/exa
sudo cp $HOME/.config/script/exa/completions/exa.fish /usr/share/fish/vendor_completions.d/
sudo cp $HOME/.config/script/exa/man/* /usr/share/man/man1/

# 安装dwm
figlet 'dwm'
sudo apt install -y xorg libx11-dev libxft-dev libxinerama-dev suckless-tools dmenu
git clone git@github.com:mogeku/dwm.git ~/.config/dwm
cd ~/.config/dwm && sudo make clean install
sudo cp $HOME/.config/dwm/dwm.desktop /usr/share/xsessions/

# 安装st
figlet 'st'
sudo apt install -y fonts-symbola
git clone git@github.com:mogeku/st.git ~/.config/st
cd ~/.config/st && sudo make clean install

# 安装node.js
figlet 'node.js'
# NodeSource 添加NodeSource源, 安装最新版本的nodejs
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt install -y nodejs
echo node.js version:
node --version

# 安装gcc, g++, make, clang
figlet 'c/c++'
sudo apt install -y gcc g++ gdb clang make

# 安装golang
figlet 'golang'
sudo apt install -y golang
echo golang version:
go version

# 安装python
figlet 'python2'
sudo apt install -y python2 python2-dev
echo python2 version:
python2 --version
figlet 'python3'
sudo apt install -y gsettings-desktop-schemas python3 python3-dev python3-pip
echo python3 version:
python3 --version

sudo rm -rf /usr/bin/python
sudo ln -sf /usr/bin/python3 /usr/bin/python

# 安装 nvim
figlet 'nvim'
sudo apt-add-repository -y ppa:neovim-ppa/stable
sudo apt update
sudo apt install -y neovim
git clone git@github.com:mogeku/nvim.git ~/.config/nvim
# 新开一个终端开始安装 vimplus 编辑器;
gnome-terminal -- bash -c 'nvim;exec bash'
sudo npm i -g bash-language-server;
#nvim

# 安装nerd font
figlet 'NerdFont'
mkdir -p ~/.local/share/fonts
cp ~/.config/fonts/JetBrains\ Mono\ Bold\ Nerd\ Font\ Complete\ Mono.ttf ~/.local/share/fonts/

sudo chmod 744 ~/.local/share/fonts/JetBrains\ Mono\ Bold\ Nerd\ Font\ Complete\ Mono.ttf

fc-cache -vf

# 安装 ranger;
figlet 'ranger'
sudo apt install -y ranger     	    # ranger 的主程序
sudo apt install -y caca-utils 	    # img2txt 图片
sudo apt install -y highlight  	    # 代码高亮
sudo apt install -y w3m        	    # html页面预览
# sudo apt install -y pdftotext 	    # pdf预览
sudo apt install -y mediainfo  	    # 多媒体文件预览
sudo apt install -y catdoc     	    # doc预览
sudo apt install -y docx2txt  	 	# docx预览
sudo apt install -y xlsx2csv   	    # xlsx预览
sudo apt install -y fzf             # 模糊查找
sudo apt install -y exiftool        # 图片信息查看
sudo apt install -y atool           # 压缩文件
sudo apt install -y rar             # 压缩文件

sudo pip3 install ueberzug          # 图片预览

ranger --copy-config=all

mkdir -p ~/.local/share/Trash/files

# cmake
figlet 'cmake'
sudo python -m pip install --upgrade pip
sudo python -m pip install cmake

# lazygit
figlet 'lazygit'
sudo apt-add-repository -y ppa:lazygit-team/release
sudo apt update
sudo apt install -y lazygit

# autojump
figlet 'autojump'
git clone https://github.com/wting/autojump.git ~/tmp1111
cd ~/tmp1111 && ./install.py
cd ~ && rm -rf ~/tmp1111

# 安装edge
figlet 'edge'
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/
sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge-dev.list'
sudo rm microsoft.gpg
sudo apt update
sudo apt install microsoft-edge-dev

# 安装中文输入法
sudo apt remove -y ibus
sudo apt install -y fcitx
sudo apt install -y fcitx-sunpinyin
im-config
im-launch fcitx
fcitx-configtool


# 配置git
# git config --global user.email "1209816754@qq.com"
# git config --global user.name "momo"

# add some script
if [ ! -e /usr/bin/explorer ];then 
    sudo ln -s /usr/bin/nautilus /usr/bin/explorer 
fi
if [ ! -e /usr/bin/addssh ];then 
    sudo ln -s ~/script/addssh.sh /usr/bin/addssh
fi
if [ ! -e /usr/bin/edge ];then 
    sudo ln -s /usr/bin/microsoft-edge /usr/bin/edge
fi

# 完成;
figlet 'finished'

$SHELL
