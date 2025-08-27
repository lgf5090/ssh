#!/bin/bash

# generate-ssh-key.sh
# SSH密钥生成和加密脚本

# set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -n, --new      生成新的SSH密钥对并加密 (默认)"
    echo "  -s, --scan     扫描并加密现有的未加密文件"
    echo "  -h, --help     显示此帮助信息"
    echo ""
    echo "说明:"
    echo "  默认模式(-n): 生成ed25519 SSH密钥对，并使用密码加密"
    echo "  扫描模式(-s): 扫描当前目录中的未加密文件并加密，保留加密文件，删除原文件"
    echo "  脚本文件(.sh)和文档文件(.md, .txt, .doc)不会被加密"
}

# 获取用户密码
get_password() {
    echo -n "请输入加密密码: "
    read -s password
    echo
    echo -n "请确认密码: "
    read -s password_confirm
    echo
    
    if [ "$password" != "$password_confirm" ]; then
        echo -e "${RED}错误: 密码不匹配${NC}"
        exit 1
    fi
    
    if [ -z "$password" ]; then
        echo -e "${RED}错误: 密码不能为空${NC}"
        exit 1
    fi
}

# 加密文件
encrypt_file() {
    local file="$1"
    local encrypted_file="${file}.encrypted"
    
    if [ -f "$encrypted_file" ]; then
        echo -e "${YELLOW}警告: $encrypted_file 已存在，跳过${NC}"
        return 0
    fi
    
    echo "正在加密 $file -> $encrypted_file"
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "$file" -out "$encrypted_file" -pass pass:"$password"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 成功加密: $encrypted_file${NC}"
        return 0
    else
        echo -e "${RED}✗ 加密失败: $file${NC}"
        return 1
    fi
}

# 检查文件是否应该被跳过
should_skip_file() {
    local file="$1"
    local basename=$(basename "$file")
    
    # 跳过脚本文件
    if [[ "$basename" == *.sh ]]; then
        return 0
    fi
    
    # 跳过文档文件
    if [[ "$basename" == *.md ]] || [[ "$basename" == *.txt ]] || [[ "$basename" == *.doc ]] || [[ "$basename" == *.docx ]]; then
        return 0
    fi
    
    # 跳过已加密文件
    if [[ "$basename" == *.encrypted ]]; then
        return 0
    fi
    
    # 跳过隐藏文件和目录
    if [[ "$basename" == .* ]]; then
        return 0
    fi
    
    return 1
}

# 生成新的SSH密钥对
generate_new_keys() {
    echo -e "${GREEN}=== 生成新的SSH密钥对 ===${NC}"
    
    # 获取密码
    get_password
    
    # 生成密钥对
    local key_name="id_ed25519"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 如果已存在密钥文件，使用时间戳避免冲突
    if [ -f "$key_name" ] || [ -f "${key_name}.pub" ]; then
        key_name="${key_name}_${timestamp}"
    fi
    
    echo "正在生成 ed25519 密钥对: $key_name"
    ssh-keygen -t ed25519 -f "$key_name" -N "" -C "generated_$(date +%Y%m%d_%H%M%S)"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: SSH密钥生成失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ SSH密钥对生成成功${NC}"
    
    # 加密私钥
    if encrypt_file "$key_name"; then
        # rm "$key_name"
        # echo -e "${GREEN}✓ 原始私钥已删除${NC}"
        echo -e "${GREEN}✓ 成功：私钥加密成功!!!${NC}"
    else
        echo -e "${RED}错误: 私钥加密失败${NC}"
        exit 1
    fi
    
    # 加密公钥
    if encrypt_file "${key_name}.pub"; then
        # rm "${key_name}.pub"
        # echo -e "${GREEN}✓ 原始公钥已删除${NC}"
        echo -e "${GREEN}✓ 成功：公钥加密成功!!!${NC}"
    else
        echo -e "${RED}错误: 公钥加密失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== 密钥生成和加密完成 ===${NC}"
    echo "生成的加密文件:"
    echo "  - ${key_name}.encrypted (私钥)"
    echo "  - ${key_name}.pub.encrypted (公钥)"
}

# 扫描并加密现有文件
scan_and_encrypt() {
    echo -e "${GREEN}=== 扫描并加密现有文件 ===${NC}"
    
    # 获取密码
    get_password
    
    local files_found=false
    local encrypted_count=0
    
    # 扫描当前目录中的文件
    for file in *; do
        # 跳过目录
        if [ -d "$file" ]; then
            continue
        fi
        
        # 检查是否应该跳过此文件
        if should_skip_file "$file"; then
            continue
        fi
        
        files_found=true
        echo "发现未加密文件: $file"
        
        # 加密文件
        if encrypt_file "$file"; then
            rm "$file"
            echo -e "${GREEN}✓ 原始文件已删除: $file${NC}"
            ((encrypted_count++))
        else
            echo -e "${RED}✗ 处理失败: $file${NC}"
        fi
        echo ""
    done
    
    if [ "$files_found" = false ]; then
        echo -e "${YELLOW}没有发现需要加密的文件${NC}"
    else
        echo -e "${GREEN}=== 扫描加密完成 ===${NC}"
        echo "共处理了 $encrypted_count 个文件"
    fi
}

# 检查依赖
check_dependencies() {
    if ! command -v ssh-keygen &> /dev/null; then
        echo -e "${RED}错误: 未找到 ssh-keygen 命令${NC}"
        exit 1
    fi
    
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}错误: 未找到 openssl 命令${NC}"
        exit 1
    fi
}

# 主函数
main() {
    local mode="new"  # 默认模式
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--new)
                mode="new"
                shift
                ;;
            -s|--scan)
                mode="scan"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查依赖
    check_dependencies
    
    # 根据模式执行相应操作
    case $mode in
        "new")
            generate_new_keys
            ;;
        "scan")
            scan_and_encrypt
            ;;
        *)
            echo -e "${RED}错误: 未知模式 $mode${NC}"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
