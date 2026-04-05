#!/bin/bash

# 设置错误处理
set -e

# 临时文件管理
TMP_FILE="/tmp/autosign.$$.tmp"
cleanup() {
    [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
}
trap cleanup EXIT

# UA
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36"
#延迟
DELAY_TIME=5
#用户名
USER_NAME=""
#密码
PASSWORD=""
#验证问题
QUESTION_ID="0"
#验证答案
ANSWER=""
#访问空间
SPACE_UID="7"

BASE_URL="https://www.mydigit.cn"
PORTAL="$BASE_URL/"
SIGN_PAGE="$BASE_URL/k_misign-sign.html"
LOGIN_PAGE="$BASE_URL/member.php?mod=logging&action=login&handlekey=login"

# 改进的curl命令 - 使用完整URL让curl自动处理Host头部
CURL_COMMON='curl -A "$USER_AGENT" -s -D -'

# 改进的get_formhash函数
get_formhash() {
    local tmp_file="$1"
    if [ ! -f "$tmp_file" ]; then
        echo "Error: Temporary file $tmp_file not found in get_formhash()" >&2
        return 1
    fi
    
    FORM_HASH=$(grep formhash "$tmp_file" | grep -v jQuery | grep input \
               | awk -F 'value=' '!(arr[$0]++){print substr($2,2,8)}' 2>/dev/null)
    
    if [ -z "$FORM_HASH" ]; then
        echo "Warning: formhash not found in $tmp_file" >&2
        return 1
    fi
    
    echo "Found formhash: $FORM_HASH"
}

# 改进的add_cookie函数
add_cookie() {
    local response="$1"
    local new_cookie
    
    new_cookie=$(awk '(tolower($1)=="set-cookie:"){n=split($0,arr," *; *")
              for(i=2;i<=n;i++){if(tolower(arr[i])=="max-age=0"){flag=1}}
              if(flag){split($2,arr,"=");print arr[1]"=,;"}
              else{print $2};flag=0}' <<< "$response")
    
    if [ -n "$new_cookie" ]; then
        COOKIE="$new_cookie $COOKIE"
        # trim cookie
        COOKIE=$(sed 's/ /\n/g' <<< "$COOKIE" | awk -F '=' '!arr[$1]++' | grep -v '=]*=,;$' | tr '\n' ' ')
        echo "Updated cookies"
    fi
}

# 主执行流程
main() {
    echo "Starting autosign script..."
    
    # 1. 请求首页
    echo "Requesting homepage..."
    add_cookie "$($CURL_COMMON -o /dev/null "$PORTAL")"
    
    # 2. 获取lastact时间
    LASTACT_TIME=$(sed -n '/_lastact/{s/=]*=//;s/[-9].*;$//p}' <<< "$COOKIE")
    echo "Lastact time: $LASTACT_TIME"
    
    # 3. 发送邮件请求
    echo "Sending mail request..."
    add_cookie "$($CURL_COMMON -b "$COOKIE" -e "$PORTAL" -o /dev/null \
               "$BASE_URL/home.php?mod=misc&ac=sendmail&rand=$LASTACT_TIME")"
    
    # 4. 请求登录页面
    echo "Requesting login page..."
    touch "$TMP_FILE" || { echo "Failed to create $TMP_FILE"; exit 1; }
    
    add_cookie "$($CURL_COMMON -b "$COOKIE" -e "$PORTAL" -o "$TMP_FILE" \
               "${LOGIN_PAGE}&infloat=yes&inajax=1&ajaxtarget=fwin_content_login")"
    
    # 5. 获取loginhash和formhash
    if [ ! -f "$TMP_FILE" ]; then
        echo "Error: $TMP_FILE not created!" >&2
        exit 1
    fi
    
    LOGIN_HASH=$(awk -F 'loginhash=' '$2{print substr($2,1,5)}' "$TMP_FILE")
    echo "Login hash: $LOGIN_HASH"
    
    get_formhash "$TMP_FILE"
    rm -f "$TMP_FILE"
    
    # 6. 登录
    echo "Logging in..."
    add_cookie "$($CURL_COMMON -b "$COOKIE" -e "$PORTAL" -X POST -o /dev/null \
               -d "formhash=$FORM_HASH&referer=$PORTAL&username=$USER_NAME&password=$PASSWORD&questionid=$QUESTION_ID&answer=$ANSWER" \
               "${LOGIN_PAGE}&loginsubmit=yes&loginhash=$LOGIN_HASH&inajax=1")"
    
    sleep "$DELAY_TIME"
    
    # 7. 请求签到页面
    echo "Requesting sign page..."
    touch "$TMP_FILE" || { echo "Failed to create $TMP_FILE"; exit 1; }
    
    add_cookie "$($CURL_COMMON -b "$COOKIE" -e "$PORTAL" -o "$TMP_FILE" \
               "$SIGN_PAGE")"
    
    # 8. 获取formhash
    get_formhash "$TMP_FILE"
    rm -f "$TMP_FILE"
    
    # 9. 执行签到
    echo "Performing sign..."
    add_cookie "$($CURL_COMMON -b "$COOKIE" -e "$SIGN_PAGE" -o /dev/null \
               "$BASE_URL/plugin.php?id=k_misign:sign&operation=qiandao&formhash=$FORM_HASH&format=empty")"
    
    sleep "$DELAY_TIME"
    
    # 10. 可选：访问个人空间
    if [ -n "$SPACE_UID" ]; then
        echo "Visiting space UID: $SPACE_UID"
        $CURL_COMMON -b "$COOKIE" -e "$SIGN_PAGE" -o /dev/null \
          "$BASE_URL/home.php?mod=space&uid=$SPACE_UID&do=profile" >/dev/null 2>&1
    fi
    
    echo "Script completed successfully!"
}

# 执行主函数
main

