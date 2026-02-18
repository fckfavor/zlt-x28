#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP_MODULE="/tmp/module.sh"
BASE_URL="https://github.com/fckfavor/zlt-x28/raw/main/modules"

show_banner() {
    echo -e "${BLUE}============================${NC}"
    echo "       ZLT X28 TOOL"
    echo -e "${BLUE}============================${NC}"
    echo "         FF.Dev"
    echo -e "${BLUE}============================${NC}"
}

run_module() {
    MODULE_URL="$1"
    MODULE_NAME="$2"

    echo -e "${YELLOW}▶ $MODULE_NAME başlatılıyor...${NC}"
    wget -q "$MODULE_URL" -O "$TMP_MODULE" 2>/dev/null

    if [ -f "$TMP_MODULE" ] && [ -s "$TMP_MODULE" ]; then
        chmod +x "$TMP_MODULE"
        sh "$TMP_MODULE"
        rm -f "$TMP_MODULE"
    else
        echo -e "${RED}▶ Dosya indirilemedi!${NC}"
        rm -f "$TMP_MODULE"
        return 1
    fi
}

while true; do
    clear
    show_banner
    echo "1) Binary Kurulumu"
    echo "2) LuCI Kurulumu"
    echo "0) Çıkış"
    echo -e "${BLUE}============================${NC}"
    printf "Seçiminiz: "
    read choice

    case "$choice" in
        1)
            run_module "$BASE_URL/install-binaries.sh" "Binary Kurulumu"
            ;;
        2)
            run_module "$BASE_URL/luci-install.sh" "LuCI Kurulumu"
            ;;
        0)
            echo -e "${GREEN}✔ Çıkış yapılıyor.${NC}"
            echo -e "${BLUE}============================${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Geçersiz seçim!${NC}"
            ;;
    esac

    echo ""
    echo -e "${YELLOW}Devam etmek için Enter'a basın...${NC}"
    read dummy
done
