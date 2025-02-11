#!/bin/bash -e
set -x

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

  git config --global user.email "haomingzidougeixle@gmail.com"	
  git config --global user.name "momo"

  sudo rm -rf ~/script
  git clone --recurse-submodules https://$github_repo/mogeku/script.git ~/script
  cd ~/script
  git remote set-url --push origin git@github.com:mogeku/script.git
  cd -

  sudo mv ~/.config ~/.config.tmp
  git clone --recurse-submodules https://$github_repo/mogeku/.config.git ~/.config
  sudo cp --update=none -a ~/.config.tmp/. ~/.config
  sudo rm -rf ~/.config.tmp
  sudo rm -rf ~/.bashrc && ln -sf ~/.config/.bashrc ~/.bashrc
  sudo rm -rf ~/.zshrc && ln -sf ~/.config/.zshrc ~/.zshrc
  cd ~/.config
  git remote set-url --push origin git@github.com:mogeku/.config.git
  cd -
}

# APT 软件更新、默认软件安装
function app_update_init() {
  echo
  echo "---------- APT 软件更新、默认软件安装 ----------"
  echo
  # 安装一个终端打印标题的软件;
  sudo apt install -y figlet
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

  # 安装gcc, g++, make, clang
  figlet 'c/c++'
  sudo apt install -y gcc g++ gdb clang make

  # 安装一些工具；
  figlet 'tools'
  sudo apt install -y neofetch 			# 系统信息打印
  sudo apt install -y tree
  sudo apt install -y curl
  sudo apt install -y ripgrep			# grep升级
  # sudo apt install -y feh			# 图片查看工具
  sudo apt install -y tldr			# 命令用法查询工具
  # sudo apt install -y openssl-server
  sudo apt install -y xsel xclip
  sudo apt install -y bat			# cat升级

  sudo apt install -y eza			# ls升级
  # sudo ln -sf $HOME/.config/script/exa/bin/exa /usr/local/bin/exa
  # sudo cp $HOME/.config/script/exa/completions/exa.fish /usr/share/fish/vendor_completions.d/
  # sudo cp $HOME/.config/script/exa/man/* /usr/share/man/man1/

  sudo apt install -y duf			# 磁盘空间查看工具
  # if [ ! -e /usr/bin/duf ];then 
  #     sudo ln -sf $home_dir/.config/duf /usr/bin/duf
  # fi
  
  #sudo dpkg -i $script_dir/bat_0.22.1_amd64.deb
  #sudo dpkg -i $script_dir/hyperfine_1.15.0_amd64.deb
  
  tldr tldr
  
  sudo apt install -y apt-file
  sudo apt-file update
  
  # httpie
  figlet 'httpie'
  sudo apt install -y httpie
  
  # shell_check
  figlet 'shellcheck'
  sudo apt install -y shellcheck
  
  # bottom top 升级
  figlet 'btm'
  curl -LO https://github.com/ClementTsang/bottom/releases/download/0.10.2/bottom_0.10.2-1_amd64.deb
  sudo dpkg -i bottom_0.10.2-1_amd64.deb
  rm -rf bottom_0.10.2-1_amd64.deb
  
  # fd find升级
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
  
  
  # 安装node.js
  figlet 'node.js'
  # NodeSource 添加NodeSource源, 安装最新版本的nodejs
  #curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
  sudo apt install -y nodejs
  echo -------- node.js 版本 ----------
  node --version
  echo --------------------------------
  
  # 安装golang
  figlet 'golang'
  sudo apt install -y golang
  echo -------- golang 版本 ----------
  go version
  echo --------------------------------
  
  # 安装python
  #figlet 'python2'
  #sudo apt install -y python2 python2-dev
  #echo python2 version:
  #python2 --version
  figlet 'python3'
  sudo apt install -y gsettings-desktop-schemas python3 python3-dev python3-pip
  echo -------- python3 版本 ----------
  python3 --version
  echo --------------------------------
  
  sudo rm -rf /usr/bin/python
  sudo ln -sf /usr/bin/python3 /usr/bin/python

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
  git clone https://$github_repo/wting/autojump.git ~/tmp1111
  cd ~/tmp1111 && ./install.py
  cd ~ && rm -rf ~/tmp1111

  # dust 目录空间占用查看
  if [ ! -e /usr/bin/dust ];then 
      sudo ln -sf $home_dir/.config/dust /usr/bin/dust
  fi

  # ssh密钥免登陆脚本添加
  if [ ! -e /usr/bin/addssh ];then 
      sudo ln -sf ~/script/addssh.sh /usr/bin/addssh
  fi

  neofetch
  read -rp "按回车键继续"
}

# 安装配置nvim
function install_nvim() {
  echo
  echo "---------- 安装配置 nvim ----------"
  echo
  while true; do
    read -rp "安装配置 nvim ？(Y/n): " input
    case $input in
    [yY])
      # 安装 nvim
      figlet 'nvim'
      sudo apt-add-repository -y ppa:neovim-ppa/stable
      sudo apt update
      sudo apt install -y neovim ccls
      sudo rm -rf ~/script
      git clone --recurse-submodules https://$github_repo/mogeku/nvim ~/.config/nvim
      # 新开一个终端开始安装 vimplus 编辑器;
      gnome-terminal -- bash -c 'nvim;exec bash'
      sudo npm i -g bash-language-server;
      break
      ;;

    [nN]) break ;;
    *) echo "错误选项：$REPLY" ;;
    esac
  done
}

# 安装nerd font
function install_nerd_font() {
  echo
  echo "---------- 安装nerd font ----------"
  echo
  while true; do
    read -rp "安装 nerd font ？(Y/n): " input
    case $input in
    [yY])
      # 安装nerd font
      figlet 'NerdFont'
      mkdir -p ~/.local/share/fonts
      cp ~/.config/fonts/JetBrains\ Mono\ Bold\ Nerd\ Font\ Complete\ Mono.ttf ~/.local/share/fonts/
      
      sudo chmod 744 ~/.local/share/fonts/JetBrains\ Mono\ Bold\ Nerd\ Font\ Complete\ Mono.ttf
      
      fc-cache -vf
      break
      ;;

    [nN]) break ;;
    *) echo "错误选项：$REPLY" ;;
    esac
  done
}

# 安装edge
function install_edge() {
  echo
  echo "---------- 安装edge ----------"
  echo
  while true; do
    read -rp "安装 edge ？(Y/n): " input
    case $input in
    [yY])
      # 安装edge
      figlet 'edge'
      curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
      sudo install -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/
      sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge-dev.list'
      sudo rm microsoft.gpg
      sudo apt update
      sudo apt install microsoft-edge-dev
      if [ ! -e /usr/bin/edge ];then 
          sudo ln -sf /usr/bin/microsoft-edge /usr/bin/edge
      fi
      break
      ;;

    [nN]) break ;;
    *) echo "错误选项：$REPLY" ;;
    esac
  done
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
#github_proxy_set
#pull_git_config
app_update_init
exit

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
  # 完成;
  figlet 'finished'
  zsh # 进入新终端
else
  echo "linux 系统不是 Ubuntu"
fi

# 安装 ranger;
# figlet 'ranger'
# sudo apt install -y ranger     	    # ranger 的主程序
# sudo apt install -y caca-utils 	    # img2txt 图片
# sudo apt install -y highlight  	    # 代码高亮
# sudo apt install -y w3m        	    # html页面预览
# # sudo apt install -y pdftotext 	    # pdf预览
# sudo apt install -y mediainfo  	    # 多媒体文件预览
# sudo apt install -y catdoc     	    # doc预览
# sudo apt install -y docx2txt  	 	# docx预览
# sudo apt install -y xlsx2csv   	    # xlsx预览
# sudo apt install -y fzf             # 模糊查找
# sudo apt install -y exiftool        # 图片信息查看
# sudo apt install -y atool           # 压缩文件
# sudo apt install -y rar             # 压缩文件
# 
# sudo pip3 install ueberzug          # 图片预览
# 
# ranger --copy-config=all
# 
# mkdir -p ~/.local/share/Trash/files
