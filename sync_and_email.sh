#!/bin/sh

####################
# rsync
####################

# 设置同步结果日志的保存位置
DATE=$(date +"%Y-%m-%d_%H-%M")

# 生成 rsync 同步日志文件名
LOG_DIR="/rsync/logs"
if [ ! -d "$LOG_DIR" ]; then
    echo "[ERR] $LOG_DIR does not exist, abort syncing."
    exit 0
fi
LOG_FILE="$LOG_DIR/rsync_result_$DATE.log"

# 执行 rsync 同步命令，并将结果保存到日志文件
rsync $RSYNC_OPTIONS "$SYNC_SRC" "$SYNC_DEST" > $LOG_FILE 2>&1

RSYNC_EXIT_CODE=$?

# 打印同步结果，判断同步成功时是否需要发送邮件通知
if [ $RSYNC_EXIT_CODE -eq 0 ]; then
    echo "[$DATE] sync success"
    SYNC_RESULT="OK"
    if [ "$MAIL_ONLY_FAILED" = "true" ]; then
        echo "[$DATE] MAIL_ONLY_FAILED is true, skip sending mail notification."
        exit 0
    fi
else
    echo "[$DATE] sync failed"
    SYNC_RESULT="FAILED"
fi

####################
# (optional) send mail
####################

# 判断是否存在 msmtprc 配置文件和 MAILTO 环境变量，如果没有则跳过发送邮件通知
if [ ! -f "/rsync/msmtprc" ] || [ "$MAILTO" == "" ]; then
    echo "[$DATE] '/rsync/msmtprc' file not exist or 'MAILTO' not set, skip mail notification."
    exit 0
else
    echo "[$DATE] sending mail notification..."
fi

# 设置收件人和发件人
FROM="$MAILFROM"
TO="$MAILTO"

# 设置邮件主题
SUBJECT="[$HOSTNAME] Rsync $SYNC_RESULT - $DATE"

# 读取 rsync 结果日志文件的内容
BODY=$(cat "$LOG_FILE")

# 构建邮件正文字符串
MAIL_CONTENT="To: $TO\nSubject: $SUBJECT\n\n$BODY"

# 如果存在 MAILFROM 环境变量，则在邮件正文前添加发件人信息
if [ "$MAILFROM" != "" ]; then
    MAIL_CONTENT="From: $MAILFROM\n$MAIL_CONTENT"
fi

# 发送邮件
echo -e "$MAIL_CONTENT" | msmtp --file=/rsync/msmtprc $TO

echo "[$DATE] mail sent successfully"
