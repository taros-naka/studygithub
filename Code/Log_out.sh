#!/bin/bash
#　ファイル名: Log_out.sh
#　Ubuntu 24.04 LTS
#  input:log_out.sh "message" "category" "subject" "body"
#　outputLOG:[timestamp] - [category] -"message"
#　メール送信：空メール不可、件名と本文なければ送信しない
# category: [INFO|WARN|ERRR|DEBU|CRIT|ALRT|SUCC|----]

#　root権限で実行することを確認
[[ $EUID -eq 0 ]] || { echo "root で実行してください"; exit 1; }

# ログ出力用ファイルのパス
LOG_FILE="/var/log/application.log"

MESSAGE="$1"   # メッセージを第1引数に変更
CATEGORY=$2  # カテゴリーを第2引数に変更

# メール通知先
MAIL_TO="test@test.com"
MAIL_FROM="test2@test.com"
MAIL_SUBJECT="$3"
MAIL_BODY="$4"


# #############################################################################
# メインメソッド
# #############################################################################

#　メール送信
#　$3及び$4が空の場合はスキップ
if [ -z "$MAIL_SUBJECT" ] && [ -z "$MAIL_BODY" ]; then

#　$3及び$4が空ではない場合、メール送信する
elif [ -n "$MAIL_SUBJECT" ] && [ -n "$MAIL_BODY" ]; then
    send_mail "$MAIL_SUBJECT" "$MAIL_BODY"

#　$3または$4が空の場合、エラーメッセージを送信
elif [ -z "$MAIL_SUBJECT" ] || [ -z "$MAIL_BODY" ]; then
    send_mail "メッセージエラー: 件名または本文が空です。" "Subject: $MAIL_SUBJECT, Body: $MAIL_BODY"

fi

#　ログメッセージを生成してファイルに書き込む
#　$2が空の場合、ログメッセージを生成しない
if [ -z "$CATEGORY" ]; then
    echo "CATEGORYが空です。処理をスキップします。" >&2
    exit 1
fi
log_message "$MESSAGE" "$CATEGORY"

# #############################################################################
# ログメッセージを生成してファイルに書き込む関数
# #############################################################################
# in:log_message_option "message" "category" 
# out:"[timestamp]" - "[category]" - "message"
log_message() {
    # 引数からメッセージとカテゴリーを取得
    local MESSAGE=$1
    local CATEGORY=$2
    local TIMESTAMP=$(date +"[%Y-%m-%d_%H:%M:%S]")
    echo "$TIMESTAMP - $CATEGORY - $MESSAGE" >> $LOG_FILE

}

# #############################################################################
# メール送信関数
# #############################################################################
# in:send_mail "subject" "body"
# out:メール送信
send_mail() {
    local SUBJECT=$1
    local BODY=$2
    # メール送信コマンドを実行
    (
        echo "Subject: $SUBJECT"
        echo "From: $MAIL_FROM"
        echo "To: $MAIL_TO"
        echo ""
        echo "$BODY"
    ) | sendmail -t
}
