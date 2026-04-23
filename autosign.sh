#!/bin/bash

# 设置错误处理
set -e

# 临时文件管理
TMP_FILE="/tmp/autosign.$$.tmp"
COOKIE_JAR="/tmp/cookies.$$.txt"
cleanup() {
    [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
    [ -f "$COOKIE_JAR" ] && rm -f "$COOKIE_JAR"
}
trap cleanup EXIT

# 配置部分 (请务必修改这里！)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
DELAY_TIME=3
USER_NAME="您的用户名"          # 请替换为您的用户名
PASSWORD="您的密码"            # 请替换为您的密码
QUESTION_ID="0"                # 安全提问ID，0通常表示无提问
ANSWER=""                      # 安全提问答案
SPACE_UID="7"                  # 访问空间UID，可按需修改

BASE_URL="https://www.mydigit.cn"
PORTAL="$BASE_URL/"
SIGN_PAGE="$BASE_URL/k_misign-sign.html"
LOGIN_PAGE="$BASE_URL/member.php?mod=logging&action=login&handlekey=login"

# 改进的get_formhash函数 - 从登录页面提取formhash
get_formhash() {
    local tmp_file="$1"
    if [ ! -f "$tmp_file" ]; then
        echo "错误：在get_formhash()中未找到临时文件 $tmp_file" >&2
        return 1
    fi
    
    # 方法1: 使用grep和sed提取标准格式的formhash
    FORM_HASH=$(grep -o 'name="formhash" value="[^"]*"' "$tmp_file" | sed 's/.*value="$[^"]*$".*/\1/' | head -n 1)
    
    # 方法2: 如果方法1失败，尝试更宽松的匹配
    if [ -z "$FORM_HASH" ]; then
        FORM_HASH=$(grep -o 'formhash=[a-fA-F0-9]*' "$tmp_file" | sed 's/formhash=//' | head -n 1)
    fi

    if [ -z "$FORM_HASH" ]; then
        echo "警告：在 $tmp_file 中未找到formhash" >&2
        echo "调试：正在检查文件内容..." >&2
        # 可选：输出文件前几行用于调试
        # head -n 50 "$tmp_file"
        return 1
    fi
    
    echo "找到formhash: $FORM_HASH"
    return 0
}

# 主执行流程
main() {
    echo "开始执行自动签到脚本..."
    echo "目标网站: $BASE_URL"
    echo "----------------------------------------"
    
    # 1. 初始化Cookie文件
    echo "[1/7] 初始化会话..."
    curl -A "$USER_AGENT" -s -c "$COOKIE_JAR" -o /dev/null "$PORTAL"
    sleep $DELAY_TIME
    
    # 2. 获取lastact时间（从Cookie中）
    LASTACT_TIME=$(grep -o '_lastact=[0-9]*' "$COOKIE_JAR" | head -n 1 | cut -d= -f2)
    if [ -n "$LASTACT_TIME" ]; then
        echo "获取到lastact时间: $LASTACT_TIME"
    else
        echo "未找到lastact时间，使用默认值"
        LASTACT_TIME=$(date +%s)
    fi
    
    # 3. 访问sendmail链接（部分Discuz!论坛需要）
    echo "[2/7] 访问sendmail链接..."
    curl -A "$USER_AGENT" -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null "$BASE_URL/home.php?mod=spacecp&ac=pm&op=checknewpm&rand=$LASTACT_TIME"
    sleep $DELAY_TIME
    
    # 4. 获取登录页面，提取formhash
    echo "[3/7] 获取登录页面..."
    curl -A "$USER_AGENT" -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$TMP_FILE" "$LOGIN_PAGE"
    
    # 从登录页面提取formhash
    if ! get_formhash "$TMP_FILE"; then
        echo "错误：无法从登录页面获取formhash，请检查网络或网站结构是否已更改。"
        exit 1
    fi
    
    # 提取loginhash（如果需要）
    LOGIN_HASH=$(grep -o 'name="loginhash" value="[^"]*"' "$TMP_FILE" | sed 's/.*value="$[^"]*$".*/\1/' | head -n 1)
    if [ -n "$LOGIN_HASH" ]; then
        echo "找到loginhash: $LOGIN_HASH"
    fi
    
    # 5. 执行登录
    echo "[4/7] 提交登录表单..."
    LOGIN_RESPONSE=$(curl -A "$USER_AGENT" -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "formhash=$FORM_HASH&referer=$BASE_URL/&loginfield=username&username=$USER_NAME&password=$PASSWORD&questionid=$QUESTION_ID&answer=$ANSWER" \
        -X POST "$BASE_URL/member.php?mod=logging&action=login&loginsubmit=yes&handlekey=login&loginhash=$LOGIN_HASH&inajax=1")
    
    # 检查登录是否成功
    if echo "$LOGIN_RESPONSE" | grep -q "succeedlocation"; then
        echo "登录成功！"
    else
        echo "登录失败！响应内容："
        echo "$LOGIN_RESPONSE"
        exit 1
    fi
    sleep $DELAY_TIME
    
    # 6. 获取签到页面，提取签到用的formhash
    echo "[5/7] 获取签到页面..."
    curl -A "$USER_AGENT" -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$TMP_FILE" "$SIGN_PAGE"
    
    # 重新提取formhash（签到页面的formhash可能不同）
    if ! get_formhash "$TMP_FILE"; then
        echo "警告：无法从签到页面获取formhash，尝试使用登录时的formhash。"
        # 如果不成功，可以尝试使用之前获取的FORM_HASH
    fi
    
    # 7. 执行签到
    echo "[6/7] 执行签到..."
    SIGN_RESPONSE=$(curl -A "$USER_AGENT" -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "formhash=$FORM_HASH&signsubmit=yes&handlekey=signin&inajax=1" \
        -X POST "$SIGN_PAGE")
    
    # 检查签到结果
    if echo "$SIGN_RESPONSE" | grep -q "签到成功"; then
        echo "签到成功！"
    elif echo "$SIGN_RESPONSE" | grep -q "今天已经签到"; then
        echo "今天已经签到过了。"
    else
        echo "签到可能失败，响应内容："
        echo "$SIGN_RESPONSE"
    fi
    sleep $DELAY_TIME
    
    # 8. 可选：访问个人空间
    if [ -n "$SPACE_UID" ]; then
        echo "[7/7] 访问个人空间 (UID: $SPACE_UID)..."
        curl -A "$USER_AGENT" -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null "$BASE_URL/home.php?mod=space&uid=$SPACE_UID&do=profile"
    fi
    
    echo "----------------------------------------"
    echo "脚本执行完毕！"
}

# 运行主函数
main
