#!/bin/sh

# =============================
# ZLT X28 LuCI Installer & Auto Start
# =============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DATA_DIR="/data/.binaries"
UHTTPD_BIN="$DATA_DIR/uhttpd"
BIN_AUTO="$DATA_DIR/luci-start"

echo -e "${BLUE}"
echo "┌─────────────────────────────┐"
echo "│      LuCI Installer         │"
echo "│        ZLT X28 OpenWrt      │"
echo "└─────────────────────────────┘"
echo -e "${NC}"

# ---------- Gizli dizin ----------
if [ ! -d "$DATA_DIR" ]; then
    echo "Gizli binary dizini oluşturuluyor: $DATA_DIR"
    mkdir -p "$DATA_DIR"
fi

# ---------- uhttpd Kurulum ----------
install_uhttpd() {
    if [ ! -f "$UHTTPD_BIN" ]; then
        echo -n "📥 uhttpd indiriliyor... "
        wget -q https://github.com/fckfavor/zlt-x28/raw/main/binaries/uhttpd -O "$UHTTPD_BIN"
        if [ $? -eq 0 ]; then
            chmod +x "$UHTTPD_BIN"
            ln -sf "$UHTTPD_BIN" /usr/sbin/uhttpd
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗ Hata!${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✓ uhttpd zaten kurulu${NC}"
    fi
}

# ---------- LuCI Kurulum ----------
install_luci() {
    echo -n "📦 LuCI indiriliyor ve kuruluyor... "
    wget -q https://github.com/fckfavor/zlt-x28/raw/main/luci/x28-luci.tgz -O /tmp/luci_fixed.tgz
    if [ $? -eq 0 ]; then
        tar xzf /tmp/luci_fixed.tgz -C /tmp
        [ -d "/tmp/www/luci-static" ] && cp -r /tmp/www/luci-static /www/
        [ -d "/tmp/usr/lib/lua/luci" ] && cp -r /tmp/usr/lib/lua/luci /usr/lib/lua/
        [ -d "/tmp/usr/share/luci" ] && cp -r /tmp/usr/share/luci /usr/share/
        rm -f /tmp/luci_fixed.tgz
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Hata!${NC}"
        return 1
    fi
}

# ---------- Auto Start Bin Dosyası ----------
create_auto_bin() {
    echo -n "📝 Auto-start bin dosyası oluşturuluyor... "
    cat > "$BIN_AUTO" << EOF
#!/bin/sh
case "\$1" in
    start)
        $UHTTPD_BIN -p 0.0.0.0:4153 -h /www &
        ;;
    stop)
        killall uhttpd 2>/dev/null
        ;;
    restart)
        killall uhttpd 2>/dev/null
        sleep 1
        $UHTTPD_BIN -p 0.0.0.0:4153 -h /www &
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        ;;
esac
EOF
    chmod +x "$BIN_AUTO"
    echo -e "${GREEN}✓${NC}"
}

# ---------- Init Script ----------
create_init() {
    echo -n "⚙️ Init script oluşturuluyor... "
    cat > /etc/init.d/luci-fixer << EOF
#!/bin/sh /etc/rc.common
START=95
STOP=10

start() {
    $BIN_AUTO start
}

stop() {
    $BIN_AUTO stop
}
EOF
    chmod +x /etc/init.d/luci-fixer
    /etc/init.d/luci-fixer enable
    echo -e "${GREEN}✓${NC}"
}

# ---------- Başlat ----------
install_uhttpd
install_luci
create_auto_bin
create_init

# ---------- İlk Servis Başlat ----------
$BIN_AUTO start

echo ""
echo -e "${GREEN}🎉 Kurulum tamamlandı!${NC}"
echo "LuCI erişimi: http://$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1'):4153"
echo "Init script ile her reboot sonrası uhttpd otomatik çalışacak."
