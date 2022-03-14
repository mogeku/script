# 配置变量
cur_dir=$(pwd)

# 更换阿里源;
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo rm -rvf /etc/apt/sources.list
sudo touch /etc/apt/sources.list
sudo chmod 777 /etc/apt/sources.list
sudo echo "
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-security main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-proposed main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-proposed main restricted universe multiverse
" >> /etc/apt/sources.list

sudo apt update

# 设置sudo的超时为10分钟
sudo sed -i 's/env_reset$/env_reset,timestamp_timeout=10/' /etc/sudoers

# 拷贝ssh key
cp -r .ssh ~/.ssh
chmod 700 ~/.ssh/id_rsa


# 安装一些工具；
figlet 'tools'
sudo apt install -y tree
sudo apt install -y curl
sudo apt install -y tldr
sudo apt install -y ripgrep

# 安装exa
sudo ln -s ~/.config/script/exa/bin/exa /usr/local/bin/exa
sudo cp ~/.config/script/exa/completions/exa.fish /usr/share/fish/vendor_completions.d/
sudo cp ~/.config/script/exa/man/* /usr/share/man/man1/

# 安装 fd
sudo apt install -y fd-find
sudo ln -s $(which fdfind) /usr/local/bin/fd

# 安装一个终端打印标题的软件;
figlet "figlet"
sudo apt install -y figlet

# 对系统的中文路径做一个软链接;
figlet ".config"
# 拉取.config目录
rm -rf ~/.config
git clone --recurse-submodules git@github.com:mogeku/.config.git ~/.config
rm ~/.bashrc && ln -s ~/.config/.bashrc ~/.bashrc

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
sudo apt install -y python3 python3-dev python3-pip
echo python3 version:
python3 --version

sudo rm -rf /usr/bin/python
sudo ln -s /usr/bin/python3 /usr/bin/python

# 安装 nvim
figlet 'nvim'
sudo apt-add-repository -y ppa:neovim-ppa/stable
sudo apt update
sudo apt install -y neovim
git clone git@github.com:mogeku/nvim.git ~/.config/nvim
nvim
sudo npm i -g bash-language-server
# 新开一个终端开始安装 vimplus 编辑器;
# gnome-terminal --window -e 'bash -c "sudo bash /home/jerome/desktop/_bash/vim_install.sh;exec bash"'

# 安装nerd font
figlet 'NerdFont'
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts && curl -fLo "JetBrains Mono Bold Nerd Font Complete Mono.ttf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/Ligatures/Bold/complete/JetBrains%20Mono%20Bold%20Nerd%20Font%20Complete%20Mono.ttf

安装 ranger;
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

ranger --copy-config=all

mkdir -p ~/.local/share/Trash/files

# # 安装 i3；
# figlet 'i3'
# sudo apt install -y i3

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
git clone https://github.com/wting/autojump.git ~/tmp
cd ~/tmp && ./install.py
cd ~ && rm -rf ~/tmp

# fish
figlet 'fish'
sudo apt-add-repository -y ppa:fish-shell/release-3
sudo apt update
sudo apt install -y fish
chsh -s /usr/bin/fish

# 配置git
git config --global user.email "1209816754@qq.com"
git config --global user.name "momo"

# 完成;
figlet 'finished'

$SHELL
