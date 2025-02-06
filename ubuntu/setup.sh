#!/bin/bash -e

# 配置变量
script_dir=$(cd `dirname $0`; pwd)
home_dir=$(cd ~; pwd)

github_repo="github.com"               # 默认 github 仓库域名
github_raw="raw.githubusercontent.com" # 默认 github raw 域名

script_list=("app_update_init" "swap_set" "term_config" "app_install" "app_remove" "docker_init" "docker_install" "docker_update" "docker_remove" "apt_clean" "sys_reboot")                                                                           # 脚本列表
script_list_info=("APT 软件更新、默认软件安装" "设置 swap 内存" "配置终端" "自选软件安装" "自选软件卸载" "安装，更新 Docker" "从 Docker compose 部署 docker 容器" "更新 docker 镜像和容器" "删除 docker 镜像和容器" "清理 APT 空间" "重启系统")                  # 脚本列表说明
docker_list=("code-server" "nginx" "pure-ftpd" "web_object_detection" "zfile" "subconverter" "sub-web" "mdserver-web" "qinglong" "webdav-client" "watchtower" "jsxm")                                                                                 # 可安装容器列表
docker_list_info=("在线 Web IDE" "Web 服务器" "FTP 服务器" "在线 web 目标识别" "在线云盘" "订阅转换后端" "订阅转换前端" "一款简单Linux面板服务" "定时任务管理面板" "Webdav 客户端，同步映射到宿主文件系统" "自动化更新 Docker 镜像和容器" "Web 在线 xm 音乐播放器") # 可安装容器列表说明
app_list=("mw" "bt" "1pctl" "kubesphere")                                                                                                                                                                                                             # 自选软件列表
app_list_info=("一款简单Linux面板服务" "aaPanel面板（宝塔国外版）" "现代化、开源的 Linux 服务器运维管理面板" "在 Kubernetes 之上构建的面向云原生应用的分布式操作系统")                                                                                          # 自选软件列表说明

# 设置 github 镜像域名
function github_proxy_set() {
  while true; do
    read -rp "是否启用 Github 国内加速? [Y/n] " input
    case $input in
    [yY]) # 使用国内镜像域名
      # git config --global url."https://hub.fastgit.xyz/".insteadOf https://github.com/
      github_repo="githubfast.com"
      github_raw="raw.gitmirror.com"
      break
      ;;

    [nN]) # 使用原始域名
      # git config --global --remove-section url."https://hub.fastgit.xyz/"
      github_repo="github.com"
      github_raw="raw.githubusercontent.com"
      break
      ;;

    *) echo "错误选项：$REPLY" ;;
    esac
  done
}

function pull_git_config() {
  echo
  echo "---------- 拉取config仓库 ----------"
  echo
# 安装一个终端打印标题的软件;
  sudo apt install -y git
  sudo rm -rf ~/.config
  git clone --recurse-submodules https://$github_repo/mogeku/.config.git ~/.config
  sudo rm -rf ~/.bashrc && ln -sf ~/.config/.bashrc ~/.bashrc
  sudo rm -rf ~/.zshrc && ln -sf ~/.config/.zshrc ~/.zshrc

  while true; do
    read -rp "是否启用 Github 国内加速? [Y/n] " input
    case $input in
    [yY]) # 使用国内镜像域名
      # git config --global url."https://hub.fastgit.xyz/".insteadOf https://github.com/
      github_repo="githubfast.com"
      github_raw="raw.gitmirror.com"
      break
      ;;

    [nN]) # 使用原始域名
      # git config --global --remove-section url."https://hub.fastgit.xyz/"
      github_repo="github.com"
      github_raw="raw.githubusercontent.com"
      break
      ;;

    *) echo "错误选项：$REPLY" ;;
    esac
  done
}

# APT 软件更新、默认软件安装
function app_update_init() {
  echo
  echo "---------- APT 软件更新、默认软件安装 ----------"
  echo
  sudo apt install curl wget lsb-release -y
  read -rp "是否使用 LinuxMirrors 脚本，更换国内软件源? [Y/n] " input
  while true; do
    case $input in
    [yY])
      # 使用脚本 LinuxMirrors 官方地址：https://gitee.com/SuperManito/LinuxMirrors
      # read -rsp "输入 root 密码: " sudo_password
      # echo $sudo_password | sudo bash -c "$(curl -fsSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh)"
      sudo bash -c "$(curl -fsSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh)"
      break
      ;;

    [nN])
      break
      ;;

    *) echo "错误选项：$REPLY" ;;
    esac
  done
  sudo apt update -y  # 更新软件列表
  sudo apt upgrade -y # 更新所有软件
  # 默认安装：
  #   zsh - 命令行界面
  #   git - 版本控制工具
  #   vim - 文本编辑器
  #   unzip - 解压缩zip文件
  #   bc - 计算器
  #   curl - 网络文件下载
  #   wget - 网络文件下载
  #   rsync - 文件同步
  #   bottom - 图形化系统监控
  #   neofetch - 系统信息工具
  sudo apt install zsh git vim unzip bc rsync jq -y

  if ! type btm >/dev/null 2>&1; then
    # 如果没有安装 bottom
    # 从官方仓库下载安装包
    wget https://$github_repo/ClementTsang/bottom/releases/download/0.10.2/bottom_0.10.2-1_amd64.deb -P ~ 
    # 使用 Debian 软件包管理器，安装 bottom
    sudo dpkg -i ~/bottom_0.10.2-1_amd64.deb
    # 开启 bottom 的 cache_memory 显示
    if [ -e ~/.config/bottom/bottom.toml ]; then
      sed -i "s/^.*enable_cache_memory.*/enable_cache_memory = true/g" ~/.config/bottom/bottom.toml
    else
      mkdir -p ~/.config/bottom
      echo "enable_cache_memory = true" > ~/.config/bottom/bottom.toml
    fi

    echo "alias btm='btm --enable_cache_memory'" >> ~/.bashrc
    echo "alias btm='btm --enable_cache_memory'" >> ~/.zshrc
    source ~/.bashrc
    
  else
    echo "已安装 bottom"
  fi

  if ! type neofetch >/dev/null 2>&1; then
    if ! sudo apt install neofetch -y; then
      git clone https://$github_repo/dylanaraps/neofetch
      sudo make -C ~/neofetch install # 手动从 makefile 编译安装
    fi
  else
    echo "已安装 neofetch"
  fi

  # 下载 vim 自定义配置文件
  wget https://$github_raw/Tsanfer/Setup_server/main/.vimrc -P ~

  neofetch
  read -rp "按回车键继续"
}

# 清理 APT 空间
function apt_clean() {
  echo
  echo "---------- 清理 APT 空间 ----------"
  echo
  while true; do
    read -rp "是否清理 APT 空间？(Y/n): " input
    case $input in
    [yY])
      sudo apt clean -y &&     # 删除存储在本地的软件安装包
        sudo apt purge -y &&   # 删除软件配置文件
        sudo apt autoremove -y # 删除不再需要的依赖软件包
      break
      ;;

    [nN]) break ;;
    *) echo "错误选项：$REPLY" ;;
    esac
  done
}

# 重启系统
function sys_reboot() {
  echo
  echo "---------- 重启系统 ----------"
  echo
  while true; do
    read -rp "是否重启系统？(Y/n): " input
    case $input in
    [yY])
      reboot # 重启系统
      exit
      ;;

    [nN]) break ;;
    *) echo "错误选项：$REPLY" ;;
    esac
  done
}

# ----- 程序开始位置 -----
github_proxy_set

if grep "Ubuntu" /etc/issue; then # 判断系统发行版是否为 Ubuntu
  while true; do
    echo
    echo "选择要运行的脚本: "
    for i in "${!script_list[@]}"; do
      printf "%2s. %-20s%-s\n" "$i" "${script_list[$i]}" "${script_list_info[$i]}" # 显示脚本列表
    done
    echo "i. 初始化配置脚本"
    read -r -p "选择要进行的操作 (q:退出): " input
    case $input in
    [iI])
      app_update_init &&
        swap_set &&
        term_config &&
        docker_init &&
        app_install &&
        docker_install &&
        apt_clean &&
        sys_reboot
      ;;
    [qQ]) break ;;
    *) ${script_list[$input]} ;;
      # *) echo "错误选项：$REPLY" ;;
    esac
  done
  echo "Done!!!"
  zsh # 进入新终端
else
  echo "linux 系统不是 Ubuntu"
fi

# 设置sudo的超时为10分钟
sudo sed -i 's/env_reset$/env_reset,timestamp_timeout=10/' /etc/sudoers

# 安装一个终端打印标题的软件;
sudo apt install -y figlet

# 拉取.config目录
figlet ".config"
sudo rm -rf ~/.config
git clone --recurse-submodules git@github.com:mogeku/.config.git ~/.config
sudo rm -rf ~/.bashrc && ln -sf ~/.config/.bashrc ~/.bashrc
sudo rm -rf ~/.zshrc && ln -sf ~/.config/.zshrc ~/.zshrc

# 安装gcc, g++, make, clang
figlet 'c/c++'
sudo apt install -y gcc g++ gdb clang make


# 安装一些工具；
figlet 'tools'
sudo apt install -y neofetch
sudo apt install -y tree
sudo apt install -y curl
sudo apt install -y ripgrep
sudo apt install -y feh
sudo apt install -y tldr
# sudo apt install -y openssl-server
sudo apt install -y trayer
sudo apt install -y xsel xclip
sudo apt install -y blueman
sudo apt install -y light
sudo dpkg -i $script_dir/bat_0.22.1_amd64.deb
sudo dpkg -i $script_dir/hyperfine_1.15.0_amd64.deb

tldr tldr

sudo apt install -y apt-file
sudo apt-file update

# httpie
figlet 'httpie'
sudo apt install -y httpie

# shell_check
figlet 'shellcheck'
sudo apt install -y shellcheck

# bottom
figlet 'btm'
curl -LO https://github.com/ClementTsang/bottom/releases/download/0.6.8/bottom_0.6.8_amd64.deb
sudo dpkg -i bottom_0.6.8_amd64.deb
rm -rf bottom_0.6.8_amd64.deb

# 安装 fd
sudo apt install -y fd-find
sudo ln -sf $(which fdfind) /usr/local/bin/fd

# fish
# figlet 'fish'
# sudo apt-add-repository -y ppa:fish-shell/release-3
# sudo apt update
# sudo apt install -y fish

# zsh
figlet 'zsh'
sudo apt install -y zsh
figlet 'oh-my-zsh'
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://gitee.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting


# 安装exa
figlet 'exa'
sudo ln -sf $HOME/.config/script/exa/bin/exa /usr/local/bin/exa
sudo cp $HOME/.config/script/exa/completions/exa.fish /usr/share/fish/vendor_completions.d/
sudo cp $HOME/.config/script/exa/man/* /usr/share/man/man1/

# 安装 picom
figlet 'picom'
git clone https://github.com/yshui/picom.git ~/.config/picom
git submodule update --init --recursive

sudo apt install -y libxext-dev libxcb1-dev libxcb-damage0-dev libxcb-xfixes0-dev libxcb-shape0-dev libxcb-render-util0-dev libxcb-render0-dev libxcb-randr0-dev libxcb-composite0-dev libxcb-image0-dev libxcb-present-dev libxcb-xinerama0-dev libxcb-glx0-dev libpixman-1-dev libdbus-1-dev libconfig-dev libgl1-mesa-dev libpcre2-dev libpcre3-dev libevdev-dev uthash-dev libev-dev libx11-xcb-dev meson

cd ~/.config/picom
meson --buildtype=release . build
sudo ninja -C build install


# 安装dwm
figlet 'dwm'
sudo apt install -y xorg libx11-dev libxft-dev libxinerama-dev suckless-tools dmenu
git clone git@github.com:mogeku/dwm.git ~/.config/dwm
cd ~/.config/dwm && sudo make clean install
sudo cp $HOME/.config/dwm/dwm.desktop /usr/share/xsessions/
ln -sf $HOME/.config/.xinitrc $HOME/.xinitrc

# 安装st
figlet 'st'
sudo apt install -y fonts-symbola
git clone git@github.com:mogeku/st.git ~/.config/st
cd ~/.config/st && sudo make clean install

# i3lock 锁屏
sudo apt install -y i3lock

# 安装node.js
figlet 'node.js'
# NodeSource 添加NodeSource源, 安装最新版本的nodejs
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt install -y nodejs
echo node.js version:
node --version

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
sudo apt install -y neovim ccls
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


# 配置git
# git config --global user.email "1209816754@qq.com"
# git config --global user.name "momo"

# config backlight
if [ ! -e /etc/X11/xorg.conf ]; then
    sudo cp $script_dir/xorg.conf /etc/X11/xorg.conf
    sudo chmod 644 /etc/X11/xorg.conf
fi

# add some script
if [ ! -e /usr/bin/explorer ];then 
    sudo ln -sf /usr/bin/nautilus /usr/bin/explorer 
fi
if [ ! -e /usr/bin/addssh ];then 
    sudo ln -sf ~/script/addssh.sh /usr/bin/addssh
fi
if [ ! -e /usr/bin/edge ];then 
    sudo ln -sf /usr/bin/microsoft-edge /usr/bin/edge
fi
if [ ! -e /usr/bin/vmsudo ];then 
    sudo ln -sf $home_dir/script/vmsudo.sh /usr/bin/vmsudo
fi
if [ ! -e /usr/bin/dnmcli ];then 
    sudo ln -sf $home_dir/script/dnmcli /usr/bin/dnmcli
fi
if [ ! -e /usr/bin/duf ];then 
    sudo ln -sf $home_dir/.config/duf /usr/bin/duf
fi
if [ ! -e /usr/bin/dust ];then 
    sudo ln -sf $home_dir/.config/dust /usr/bin/dust
fi
if [ ! -e /usr/bin/lock ];then
    sudo ln -sf /home/momo/script/lock-screen.sh /usr/bin/lock
fi

# 完成;
figlet 'finished'

$SHELL
