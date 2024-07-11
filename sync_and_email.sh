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

echo -e "[$DATE] start syncing...\n" | tee -a $LOG_FILE

# 执行 rsync 同步命令，并将结果保存到日志文件
rsync $RSYNC_OPTIONS "$SYNC_SRC" "$SYNC_DEST" >> $LOG_FILE 2>&1

RSYNC_EXIT_CODE=$?

# 检查 rsync 的退出码，如果是 24 则忽略错误
# https://unix.stackexchange.com/questions/86879/suppress-rsync-warning-some-files-vanished-before-they-could-be-transferred
if [ $RSYNC_EXIT_CODE -eq 24 ]; then
    RSYNC_EXIT_CODE=0
fi

DONE_DATE=$(date +"%Y-%m-%d_%H-%M")

# 打印同步结果，判断同步成功时是否需要发送邮件通知
if [ $RSYNC_EXIT_CODE -eq 0 ]; then
    echo -e "\n[$DONE_DATE] sync successfully\n" | tee -a $LOG_FILE
    SYNC_RESULT="OK"

    if [ "$MAIL_ONLY_FAILED" = "true" ]; then
        echo "MAIL_ONLY_FAILED is true, skip sending mail notification."
        exit 0
    fi
else
    echo -e "\n[$DONE_DATE] sync failed\n" | tee -a $LOG_FILE
    SYNC_RESULT="FAILED"
fi

####################
# (optional) send mail
####################

# 判断是否存在 msmtprc 配置文件和 MAILTO 环境变量，如果没有则跳过发送邮件通知
if [ ! -f "/rsync/msmtprc" ] || [ "$MAILTO" == "" ]; then
    echo "'/rsync/msmtprc' file not exist or 'MAILTO' not set, skip mail notification."
    exit 0
else
    echo "sending mail notification..."
fi

# 设置收件人和发件人
FROM="$MAILFROM"
TO="$MAILTO"

# 设置邮件主题
SUBJECT="[$HOSTNAME] Rsync $SYNC_RESULT - $DATE"

# 读取 rsync 结果日志文件的内容
LINE_COUNT=$(wc -l < "$LOG_FILE")
if [ "$LINE_COUNT" -gt 50 ]; then
    HEAD=$(head -n 10 "$LOG_FILE")
    TAIL=$(tail -n 40 "$LOG_FILE")
    BODY="$HEAD\n\n\n......\n\n\n$TAIL"
else
    BODY=$(cat "$LOG_FILE")
fi

# 构建邮件正文字符串
MAIL_CONTENT="To: $TO\nSubject: $SUBJECT\n\n$BODY"

# 如果存在 MAILFROM 环境变量，则在邮件正文前添加发件人信息
if [ "$MAILFROM" != "" ]; then
    MAIL_CONTENT="From: $MAILFROM\n$MAIL_CONTENT"
fi

# 发送邮件
echo -e "$MAIL_CONTENT" | msmtp --file=/rsync/msmtprc $TO

MSMTP_EXIT_CODE=$?

# 记录 msmtp 命令的执行结果
if [ $MSMTP_EXIT_CODE -eq 0 ]; then
    echo "mail sent successfully"
else
    echo "failed to send mail"
fi