#!/bin/bash

# generate-ssh-key.sh - SSH密钥生成、加密和管理工具
VERSION="2.1"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
SSH_DIR="$HOME/.ssh"
CURRENT_DIR=$(pwd)

# 支持的加密算法
declare -A ENCRYPTION_TYPES=(
    ["1"]="ed25519"
    ["2"]="rsa"
    ["3"]="ecdsa"
    ["4"]="dsa"
)

# 显示使用帮助
show_help() {
    echo -e "${BLUE}=== SSH密钥生成和管理工具 v${VERSION} ===${NC}"
    echo ""
    echo "用法:"
    echo "  $0 -n    生成新的SSH密钥对并加密"
    echo "  $0 -s    扫描并加密当前目录下的未加密文件"
    echo "  $0 -h    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -n                    # 生成新密钥"
    echo "  $0 -s                    # 扫描加密现有文件"
    echo ""
}

# 检查依赖
check_dependencies() {
    local missing=()
    
    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    fi
    
    if ! command -v ssh-keygen &> /dev/null; then
        missing+=("ssh-keygen")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ 缺少必需的依赖：${missing[*]}${NC}"
        echo "请先安装缺少的工具"
        exit 1
    fi
}

# 选择加密类型
select_encryption_type() {
    echo -e "${CYAN}请选择SSH密钥加密类型：${NC}"
    echo "1) ed25519 (推荐 - 快速、安全、密钥短)"
    echo "2) rsa (兼容性好 - 4096位)"
    echo "3) ecdsa (椭圆曲线 - 256位)"
    echo "4) dsa (已弃用 - 不推荐)"
    echo ""
    
    while true; do
        read -p "请输入选择 [1-4]: " choice
        
        if [[ -n "${ENCRYPTION_TYPES[$choice]}" ]]; then
            echo "${ENCRYPTION_TYPES[$choice]}"
            return 0
        else
            echo -e "${RED}无效选择，请输入 1-4${NC}"
        fi
    done
}

# 生成SSH密钥
generate_ssh_key() {
    local key_type="$1"
    local key_name="$2"
    local key_path="$SSH_DIR/$key_name"
    
    echo -e "${YELLOW}正在生成 $key_type SSH密钥...${NC}"
    
    # 根据密钥类型设置参数
    case $key_type in
        "ed25519")
            ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$(whoami)@$(hostname)-$(date +%Y%m%d)"
            ;;
        "rsa")
            ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "$(whoami)@$(hostname)-$(date +%Y%m%d)"
            ;;
        "ecdsa")
            ssh-keygen -t ecdsa -b 256 -f "$key_path" -N "" -C "$(whoami)@$(hostname)-$(date +%Y%m%d)"
            ;;
        "dsa")
            echo -e "${YELLOW}⚠️  警告：DSA密钥已被认为不安全，不建议使用${NC}"
            read -p "确定要生成DSA密钥吗？(y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                return 1
            fi
            ssh-keygen -t dsa -b 1024 -f "$key_path" -N "" -C "$(whoami)@$(hostname)-$(date +%Y%m%d)"
            ;;
        *)
            echo -e "${RED}❌ 不支持的密钥类型: $key_type${NC}"
            return 1
            ;;
    esac
    
    return $?
}

# 加密文件 - 修复版本
encrypt_file() {
    local source_file="$1"
    local encrypted_file="$2"
    local password="$3"
    
    if [ ! -f "$source_file" ]; then
        echo -e "${RED}❌ 源文件不存在: $source_file${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🔐 加密文件: $(basename "$source_file")${NC}"
    
    # 使用兼容性更好的参数，明确指定不使用pbkdf2
    if openssl aes-256-cbc -salt -md md5 -in "$source_file" -out "$encrypted_file" -pass pass:"$password" 2>/dev/null; then
        echo -e "${GREEN}✅ 加密成功: $(basename "$encrypted_file")${NC}"
        chmod 600 "$encrypted_file"
        
        # 验证加密文件
        echo -e "${CYAN}🔍 验证加密文件...${NC}"
        if openssl aes-256-cbc -d -salt -md md5 -in "$encrypted_file" -pass pass:"$password" -out /dev/null 2>/dev/null; then
            echo -e "${GREEN}✅ 加密文件验证成功${NC}"
            return 0
        else
            echo -e "${RED}❌ 加密文件验证失败，删除损坏的加密文件${NC}"
            rm -f "$encrypted_file"
            return 1
        fi
    else
        echo -e "${RED}❌ 加密失败: $(basename "$source_file")${NC}"
        return 1
    fi
}

# 安全读取密码
read_password() {
    local prompt="$1"
    local password
    
    while true; do
        read -sp "$prompt" password
        echo
        
        if [ ${#password} -lt 6 ]; then
            echo -e "${RED}密码长度至少6位，请重新输入${NC}"
            continue
        fi
        
        read -sp "请再次确认密码: " confirm_password
        echo
        
        if [ "$password" = "$confirm_password" ]; then
            echo "$password"
            return 0
        else
            echo -e "${RED}❌ 密码不一致，请重新输入${NC}"
        fi
    done
}

# 新建密钥对
new_key_pair() {
    echo -e "${BLUE}=== 生成新的SSH密钥对 ===${NC}"
    echo ""
    
    # 选择加密类型
    key_type=$(select_encryption_type)
    
    # 输入文件名
    default_name="id_$key_type"
    read -p "请输入密钥文件名 [默认: $default_name]: " custom_name
    key_name=${custom_name:-$default_name}
    
    # 检查文件是否已存在
    if [ -f "$SSH_DIR/$key_name" ] || [ -f "$SSH_DIR/$key_name.pub" ]; then
        echo -e "${YELLOW}⚠️  发现已存在的密钥: $key_name${NC}"
        read -p "是否覆盖？(y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo "操作已取消。"
            return 1
        fi
        rm -f "$SSH_DIR/$key_name" "$SSH_DIR/$key_name.pub"
    fi
    
    # 生成SSH密钥
    if ! generate_ssh_key "$key_type" "$key_name"; then
        echo -e "${RED}❌ SSH密钥生成失败！${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ SSH密钥生成成功！${NC}"
    
    # 获取加密密码
    password=$(read_password "请设置加密密码: ")
    
    # 加密私钥
    encrypted_private="$CURRENT_DIR/${key_name}.encrypted"
    if encrypt_file "$SSH_DIR/$key_name" "$encrypted_private" "$password"; then
        # 复制公钥到当前目录
        cp "$SSH_DIR/$key_name.pub" "$CURRENT_DIR/"
        chmod 644 "$CURRENT_DIR/$key_name.pub"
        
        echo ""
        echo -e "${GREEN}=== 密钥生成完成 ===${NC}"
        echo -e "📁 SSH目录: ${BLUE}$SSH_DIR/${NC}"
        echo -e "🔐 加密私钥: ${PURPLE}$encrypted_private${NC}"
        echo -e "🔓 公钥文件: ${CYAN}$CURRENT_DIR/$key_name.pub${NC}"
        echo ""
        echo -e "${YELLOW}💡 请妥善保管加密密码${NC}"
        echo -e "${CYAN}💡 加密使用兼容模式，可使用setup.sh正常解密${NC}"
        
        return 0
    else
        # 清理失败的文件
        rm -f "$SSH_DIR/$key_name" "$SSH_DIR/$key_name.pub"
        return 1
    fi
}

# 扫描并加密现有文件
scan_and_encrypt() {
    echo -e "${BLUE}=== 扫描并加密现有文件 ===${NC}"
    echo ""
    
    # 查找需要加密的文件
    declare -a files_to_encrypt=()
    
    # 扫描当前目录下的文件
    for file in "$CURRENT_DIR"/*; do
        [ ! -f "$file" ] && continue
        
        filename=$(basename "$file")
        
        # 跳过已经加密的文件、脚本文件、README等
        # 注意：.pub文件需要加密，所以不跳过
        if [[ "$filename" =~ \.(encrypted|md|sh|txt|git.*)$ ]] || \
           [[ "$filename" =~ ^(README|LICENSE|\..*)$ ]] || \
           [ ! -r "$file" ]; then
            continue
        fi
        
        # 检查是否已有对应的加密文件
        if [ ! -f "$CURRENT_DIR/${filename}.encrypted" ]; then
            files_to_encrypt+=("$filename")
        fi
    done
    
    if [ ${#files_to_encrypt[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ 没有发现需要加密的文件${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}发现 ${#files_to_encrypt[@]} 个需要加密的文件：${NC}"
    printf '  %s\n' "${files_to_encrypt[@]}"
    echo ""
    
    read -p "是否继续加密这些文件？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "操作已取消。"
        return 1
    fi
    
    # 获取加密密码
    password=$(read_password "请输入加密密码: ")
    
    # 加密文件
    success_count=0
    for filename in "${files_to_encrypt[@]}"; do
        source_file="$CURRENT_DIR/$filename"
        encrypted_file="$CURRENT_DIR/${filename}.encrypted"
        
        if encrypt_file "$source_file" "$encrypted_file" "$password"; then
            # 加密成功，删除原文件
            rm -f "$source_file"
            echo -e "  ${GREEN}删除原文件: $filename${NC}"
            ((success_count++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}=== 加密完成 ===${NC}"
    echo -e "✅ 成功加密 ${success_count}/${#files_to_encrypt[@]} 个文件"
    echo -e "${CYAN}💡 使用兼容模式加密，可使用setup.sh正常解密${NC}"
    
    if [ $success_count -eq ${#files_to_encrypt[@]} ]; then
        echo -e "${YELLOW}💡 所有原始文件已被安全删除${NC}"
    fi
    
    return 0
}

# 主函数
main() {
    check_dependencies
    
    case "$1" in
        -n|--new)
            new_key_pair
            ;;
        -s|--scan)
            scan_and_encrypt
            ;;
        -h|--help|"")
            show_help
            ;;
        *)
            echo -e "${RED}❌ 未知参数: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
