# yuusha/rsync-docker

- [说明](#说明)
- [原始镜像](#原始镜像)
- [新增点](#新增点)
- [镜像使用方式](#镜像使用方式)
  - [原始镜像的使用方式](#原始镜像的使用方式)
  - [新镜像的使用方式](#新镜像的使用方式)
- [示例](#示例)
  - [目标主机端（备份文件存放的主机）](#目标主机端备份文件存放的主机)
  - [源主机端（待备份文件所在的主机）](#源主机端待备份文件所在的主机)
- [补充](#补充)
  - [TZ 设置无效问题](#tz-设置无效问题)
  - [docker-compose.yaml 中环境变量是否加引号](#docker-composeyaml-中环境变量是否加引号)
  - [容器停止时间过长问题](#容器停止时间过长问题)
  - [rsync 常用参数及作用](#rsync-常用参数及作用)

## 说明

通过 docker 容器方式，使用 rsync 在多机器之间进行数据定期备份，并可选地发送同步结果邮件通知。

## 原始镜像

本仓库 fork 自 [ogivuk/rsync](https://github.com/ogivuk/rsync-docker) ，原始镜像基本满足需求，但是：

1. 没有构建 armv7 架构的镜像
2. 缺少邮件程序，同步后无法发送邮件通知

所以本仓库新增了一些功能，并使用 `Github Actions` 实现自动化打包和发布镜像。

## 新增点

1. 新增构建 armv7 架构的镜像
2. 补充安装了 `msmtp` 邮件发送程序
3. 容器中打包进一个默认的 `/sync_and_email.sh` 脚本，实现开箱即用的 `rsync` 同步并发送邮件通知

## 镜像使用方式

新镜像是在原始镜像的基础上新增了邮件通知功能，并未修改原始镜像的使用方式。所以要先熟悉原始镜像的使用方式。

### 原始镜像的使用方式

原始镜像 [ogivuk/rsync](https://github.com/ogivuk/rsync-docker) 的基本用法可以参考原仓库的 README (本仓库中已改名为 [README_forked.md](./README_forked.md))。

### 新镜像的使用方式

新镜像安装了 `msmtp`，可以自行调用它来发送邮件。

新镜像还新增了 `/sync_and_email.sh` 脚本，实现开箱即用的同步并发送邮件功能。该脚本的详细说明如下：

1. 如果想要进行 rsync 同步，必须要传入以下环境变量：

   - `RSYNC_OPTIONS`: rsync 的 options 字符串，例如 `-avz --delete`
   - `SYNC_SRC`: 待同步目录的位置，注意是容器中的路径
   - `SYNC_DEST`: 同步到的目标位置

   同时还需要确保容器中 `/rsync/logs` 目录存在，该目录用于存放 rsync 同步结果日志文件

2. 如果想要发送邮件通知，还需要传入以下环境变量：

   - `MAILTO`: 邮件通知收件人的邮箱
   - `HOSTNAME`: 用于邮件标题中显示当前备份的主机名
   - （可选）`MAIL_ONLY_FAILED`: 是否只在 rsync 同步失败时发送邮件通知，指定为 `true` 时只在同步失败时发送邮件通知
   - （可选）`MAILFROM`: 指定发件人，通常不需要传，因为邮件服务器会验证发件人是合法的，邮件中的发件人应该与配置文件中的发件人一致

   同时还需要确保容器中 `/rsync/msmtprc` 文件存在，该文件用于存放 msmtp 邮件配置信息

## 示例

`rsync` 镜像在 `源主机端（待备份文件所在的主机）` 和 `目标主机端（备份文件存放的主机）` 都需要运行。数据定期同步的思路是：

- 在 `目标主机端（备份文件存放的主机）` 以服务 (`daemon`) 方式运行 `rsync`，然后在 `源主机端（待备份文件所在的主机）` 利用 `cron` 定时任务周期性地运行 `rsync` 命令，将文件同步到 `目标主机端（备份文件存放的主机）` 。

以下步骤使用 `docker-compose` 先配置 `目标主机端（备份文件存放的主机）` ，然后再配置 `源主机端（待备份文件所在的主机）`。

### 目标主机端（备份文件存放的主机）

在 `目标主机端（备份文件存放的主机）` 以服务 (`daemon`) 方式运行 `rsync` 。

创建目录存放 `rsyncd` 相关文件：

```sh
RSYNCD_ROOT=$HOME/scripts/rsyncd
mkdir -p $RSYNCD_ROOT

# 创建 rsync 相关配置、日志、密码的存放目录
DATA_DIR=$RSYNCD_ROOT/rsync
mkdir -p $DATA_DIR/{logs,secrets}
```

创建 `rsyncd.conf` 配置文件：

```sh
cat > $DATA_DIR/rsyncd.conf <<EOF
uid = root
gid = root
use chroot = no
max connections = 10
timeout = 900
ignore nonreadable = yes
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsyncd.lock
# dont compress = *.gz *.tgz *.zip *.z *.Z *.rpm *.deb *.bz2 # 这个配置暂时无用

# 定义备份信息，这里以备份 opizero3 为例
[bak_opizero3]
comment = backup opizero3
path = /bak_opizero3
ignore errors = yes
# hosts allow = 10.10.10.*
auth users = bak_opizero3_user
secrets file = /rsync/secrets/bak_opizero3.secrets
log file = /rsync/logs/bak_opizero3.log
list = true
read only = no
EOF
```

> 其中：
>
> 1. `path` 为存放备份数据的路径（注意是容器中的路径，后续要使用 `-v` 映射到宿主机的路径）
> 2. `secrets file` 为密码文件的路径（注意是容器中的路径，后续要使用 `-v` 映射到宿主机的路径）
> 3. `log file` 为日志文件的路径（注意是容器中的路径，后续要使用 `-v` 映射到宿主机的路径）

创建 `bak_opizero3.secrets` 密码文件：

```sh
cat > $DATA_DIR/secrets/bak_opizero3.secrets <<EOF
bak_opizero3_user:bak_opizero3_pwd
EOF

chmod 600 $DATA_DIR/secrets/bak_opizero3.secrets
```

创建 `docker-compose.yaml` 文件：

```sh
cat > $RSYNCD_ROOT/docker-compose.yaml <<'EOF'
services:
  rsyncd:
    image: yuusha/rsync-docker:1.0
    container_name: rsyncd
    init: true # 加上该项，否则容器无法处理 SIGTERM 信号，要等待 10 s 才能停止
    restart: unless-stopped
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - $PWD/rsync:/rsync
      - /path_to_save_backup:/bak_opizero3 # /path_to_save_backup 为宿主机上存放备份数据的路径
    ports:
      - 873:873
    command: ['--daemon', '--no-detach', '--config=/rsync/rsyncd.conf']
EOF
```

然后运行 `docker-compose.yaml` 脚本：

```sh
cd $RSYNCD_ROOT
docker-compose up -d
```

### 源主机端（待备份文件所在的主机）

在 `源主机端（待备份文件所在的主机）` 通过 `cron` 定时任务实现周期性地以命令方式运行 `rsync`，向目标主机端同步最新数据，并且可选在同步完成后发送邮件通知。

创建目录存放 `rsync-cron` 相关文件：

```sh
RSYNC_CRON_ROOT=$HOME/scripts/rsync-cron
mkdir -p $RSYNC_CRON_ROOT

# 创建 cron 脚本、mail 邮件等配置文件的存放目录
DATA_DIR=$RSYNC_CRON_ROOT/rsync
mkdir -p $DATA_DIR

# 创建日志文件存放目录
mkdir -p $DATA_DIR/logs
```

创建定时任务 `crontab.txt`:

> 自行调整其中的内容，容器默认自带一个同步并发送邮件通知的脚本（路径为 `/sync_and_email.sh`），也可以自己写脚本挂载到容器中后在定时任务中调用。

```sh
cat > $DATA_DIR/crontab.txt <<EOF
# 每天凌晨 3 点执行同步任务并发送邮件通知，使用 flock 文件锁实现串行化执行，避免同时存在多个任务
0 3 * * * flock -xn /tmp/sync_and_email.lock -c '/sync_and_email.sh'
EOF
```

创建 `rsync` 连接使用的密码文件 `rsync-client.passwd`:

> 注意自行调整其中的内容。

```sh
cat > $DATA_DIR/rsync-client.passwd <<EOF
bak_opizero3_pwd
EOF

chmod 600 $DATA_DIR/rsync-client.passwd
```

创建邮件通知配置文件 `msmtprc`：

> 注意自行调整其中的内容。
>
> **特别注意该文件中要单独一行写 `#` 注释，不要把 `#` 注释写在值后面，否则会被认为是值的一部分。**

```sh
cat > $DATA_DIR/msmtprc <<EOF
account default
auth on
tls on
tls_starttls off
tls_certcheck off
syslog off
# 日志保存路径
logfile /rsync/logs/msmtp.log

host smtp.qq.com
port 465
# 发送者的邮箱
from example@qq.com
# 和 from 一致
user example@qq.com
# 授权码，非登录密码
password password
EOF

chmod 600 $DATA_DIR/msmtprc
```

创建 `docker-compose.yaml` 文件：

```sh
cat > $RSYNC_CRON_ROOT/docker-compose.yaml <<'EOF'
services:
  rsync-cron:
    image: yuusha/rsync-docker:1.0
    container_name: rsync-cron
    init: true # 加上该项，否则容器无法处理 SIGTERM 信号，要等待 10 s 才能停止
    restart: unless-stopped
    network_mode: host # 由于在容器中运行，最好指定 host 模式，这样可以访问到宿主机所在内网的机器
    environment:
      - TZ=Asia/Shanghai
      - RSYNC_CRONTAB=crontab.txt
      - RSYNC_OPTIONS=-avz --delete --password-file=/rsync/rsync-client.passwd --port=30873 # password-file 指定密码文件的路径，port 指定连接端口号（默认 873），内网穿透时可能需要指定
      - SYNC_SRC=/bak_src/ # 注意尾斜杠加不加有区别
      - SYNC_DEST=bak_opizero3_user@<rsync-server>::bak_opizero3
      - MAILTO=example@qq.com
      - MAIL_ONLY_FAILED=true # 为 true 时仅在同步失败后发送邮件，不指定或为其他值则每次同步后都发送邮件通知
      - HOSTNAME=opizero3 # 邮件标题中显示的备份主机名称
    volumes:
      - $PWD/rsync:/rsync
      - /path_to_backup:/bak_src/path_to_backup # /path_to_backup 为待备份的数据，挂载到 /bak_src 目录下的某个目录，可以指定挂载多个待备份数据到 /bak_src 目录下
EOF
```

然后运行 `docker-compose.yaml` 脚本：

```sh
cd $RSYNC_CRON_ROOT
docker-compose up -d
```

## 补充

### TZ 设置无效问题

`TZ` 环境变量在使用 `docker-compose.yaml` 文件时必须写成 `'TZ=Asia/Shanghai'` 这样，前后加上引号，或者完全不加引号，不能在 `Asia/Shanghai` 前后加引号，否则无法设置时区。

> `TZ` 环境变量传入容器后的具体值，可以通过进入容器后执行 `env` 查看，正确值应该输出为 `TZ=Asia/Shanghai`，而不是 `TZ='Asia/Shanghai'`，TZ 设置无效的问题可能就是因为加了引号。

### docker-compose.yaml 中环境变量是否加引号

同上面 `TZ 设置无效问题` 一样，环境变量传入时要么不加引号，要么在整个环境变量的 `key=value` 前后加引号，不要写成 `key='value'` 这样单独给 `value` 部分加引号，否则传入的环境变量将会是一个带引号的值。

### 容器停止时间过长问题

容器停止时间过长，大概 10 秒，是等待 SIGKILL 信号强制杀死的，而不是 SIGTERM 信号优雅停止。

问题原因是 `Dockerfile` 中 `ENTRYPOINT` 指定执行 `./rsync.sh`，但是该脚本没有处理 `SIGTERM` 信号，无法优雅停止，所以只能等待 10s 后 docker 发送 `SIGKILL` 信号强制终止。

解决方案是在 `docker run` 时添加 `--init` 参数，或者 `docker-compose.yaml` 中指定 `init: true` 即可。

> 详细解释见 `tini` 库的这篇文章 [What is advantage of Tini?](https://github.com/krallin/tini/issues/8)。

### rsync 常用参数及作用

rsync 常用参数：

- `-a`
- `-z`
- `-v`
- `--delete`

rsync 参数及作用参考 [rysnc manpage](https://download.samba.org/pub/rsync/rsync.1#OPTION_SUMMARY)
