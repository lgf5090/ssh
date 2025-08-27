#!/bin/bash

# setup.sh - SSH密钥批量解密和安装脚本
echo "=== SSH密钥批量安装工具 ==="
echo "仓库: https://github.com/lgf5090/ssh.git"

# 设置变量
SSH_DIR="$HOME/.ssh"
TEMP_DIR="/tmp/ssh-setup-$$"
RAW_BASE_URL="https://raw.githubusercontent.com/lgf5090/ssh/main"

# 检查依赖
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo "❌ 错误：openssl 未安装。"
        echo "请先安装openssl："
        echo "Ubuntu/Debian: sudo apt-get install openssl"
        echo "CentOS/RHEL: sudo yum install openssl"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        echo "❌ 错误：curl 未安装。"
        echo "请先安装curl"
        exit 1
    fi
}

# 获取密码
get_password() {
    if [ -t 0 ]; then
        # 标准输入是终端，直接读取
        read -sp "请输入解密密码: " password
        echo
    else
        # 标准输入被管道占用，从/dev/tty读取
        echo "检测到通过管道执行，请在终端中输入密码："
        read -sp "请输入解密密码: " password < /dev/tty
        echo
    fi
}

# 主函数
main() {
    check_dependencies
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    echo "当前工作目录: $(pwd)"
    echo "开始下载SSH配置文件..."
    
    # 获取加密文件列表
    declare -a ENCRYPTED_FILES=()
    POSSIBLE_ENCRYPTED_PATTERNS=(
        "id_ed25519.encrypted"
        "id_rsa.encrypted" 
        "id_ecdsa.encrypted"
        "id_ed25519.pub.encrypted"
        "id_rsa.pub.encrypted"
        "id_ecdsa.pub.encrypted"
        "config.encrypted"
    )
    
    echo "扫描和下载加密文件..."
    for encrypted_pattern in "${POSSIBLE_ENCRYPTED_PATTERNS[@]}"; do
        echo "尝试下载 $encrypted_pattern..."
        if curl -f -L -s "$RAW_BASE_URL/$encrypted_pattern" -o "$encrypted_pattern" 2>/dev/null; then
            echo "✅ 下载 $encrypted_pattern 成功"
            ENCRYPTED_FILES+=("$encrypted_pattern")
        else
            echo "⚠️  $encrypted_pattern 不存在，跳过"
        fi
    done
    
    if [ ${#ENCRYPTED_FILES[@]} -eq 0 ]; then
        echo "❌ 没有找到任何加密的SSH配置文件！"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    echo ""
    echo "📋 发现的加密文件："
    printf '  %s\n' "${ENCRYPTED_FILES[@]}"
    echo ""
    
    # 创建SSH目录
    mkdir -p "$SSH_DIR"
    
    # 获取密码
    get_password
    
    # 解密文件
    success_count=0
    for encrypted_file in "${ENCRYPTED_FILES[@]}"; do
        original_name="${encrypted_file%.encrypted}"
        echo "🔓 解密 $encrypted_file → $original_name"
        
        # 尝试不同的openssl参数
        if openssl aes-256-cbc -d -pbkdf2 -salt -in "$encrypted_file" -out "$SSH_DIR/$original_name" -pass pass:"$password" 2>/dev/null || \
           openssl aes-256-cbc -d -salt -in "$encrypted_file" -out "$SSH_DIR/$original_name" -pass pass:"$password" 2>/dev/null; then
            echo "✅ $original_name 解密成功"
            
            # 设置权限
            if [[ "$original_name" == *.pub ]]; then
                chmod 644 "$SSH_DIR/$original_name"
            elif [[ "$original_name" == "config" ]]; then
                chmod 600 "$SSH_DIR/$original_name"
            else
                chmod 600 "$SSH_DIR/$original_name"
            fi
            
            ((success_count++))
        else
            echo "❌ $original_name 解密失败！"
            echo "请检查密码是否正确"
            rm -f "$SSH_DIR/$original_name"
        fi
    done
    
    # 清理和显示结果
    chmod 700 "$SSH_DIR"
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo "✅ 安装完成！"
    echo "📁 SSH目录: $SSH_DIR/"
    echo "🔐 解密成功的文件: $success_count 个"
    echo ""
    
    # 显示目录内容
    echo "=== SSH目录内容 ==="
    ls -la "$SSH_DIR/"
    echo ""
}

# 执行主函数
main "$@"
