#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP_MODULE="/tmp/module.sh"

echo -e "${BLUE}============================${NC}"
echo "      ZLT X28 TOOL"
echo -e "${BLUE}============================${NC}"
echo "1) Binary Kurulumu"
echo "2) LuCI Install"
echo "0) Çıkış"
printf "Seçiminiz: "
read choice

case "$choice" in
    1)
        echo -e "${YELLOW}▶ Binary kurulumu başlatılıyor...${NC}"
        wget -q https://github.com/fckfavor/zlt-x28/raw/main/modules/install-binaries.sh -O "$TMP_MODULE"
        if [ -f "$TMP_MODULE" ]; then
            chmod +x "$TMP_MODULE"
            sh "$TMP_MODULE"
        else
            echo -e "${RED}▶ Dosya indirilemedi!${NC}"
            exit 1
        fi
        ;;
    2)
        echo -e "${YELLOW}▶ LuCI kurulumu başlatılıyor...${NC}"
        wget -q https://github.com/fckfavor/zlt-x28/raw/main/modules/luci-install.sh -O "$TMP_MODULE"
        if [ -f "$TMP_MODULE" ]; then
            chmod +x "$TMP_MODULE"
            sh "$TMP_MODULE"
        else
            echo -e "${RED}▶ Dosya indirilemedi!${NC}"
            exit 1
        fi
        ;;
    0)
        echo "Çıkış yapılıyor."
        exit 0
        ;;
    *)
        echo -e "${RED}Geçersiz seçim!${NC}"
        exit 1
        ;;
esac

# Temp dosyasını temizle
rm -f "$TMP_MODULE"

# İmza
echo ""
echo -e "${GREEN}✔ İşlem tamamlandı!${NC}"
echo -e "${BLUE}============================${NC}"
echo "         FF.Dev"
echo -e "${BLUE}============================${NC}"
