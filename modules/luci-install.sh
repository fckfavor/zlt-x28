#!/bin/sh

# =============================
# ZLT X28 LuCI Installer v2.0
# uhttpd çakışma korumalı
# IP otomatik tespit
# =============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DATA_DIR="/data/.binaries"
UHTTPD_BIN="$DATA_DIR/uhttpd"
BIN_AUTO="$DATA_DIR/luci-start"
GITHUB_BASE="https://github.com/fckfavor/zlt-x28/raw/main"

echo -e "${BLUE}"
echo "┌─────────────────────────────┐"
echo "│      LuCI Installer v2.0   │"
echo "│        ZLT X28 OpenWrt     │"
echo "└─────────────────────────────┘"
echo -e "${NC}"

# ---------- Dizin ----------
mkdir -p "$DATA_DIR"

# ---------- IP Tespit ----------
get_router_ip() {
    IP=""

    # Önce uci dene (interface adları farklı olabilir)
    for iface in lan br-lan network.lan network.loopback; do
        IP=$(uci get ${iface}.ipaddr 2>/dev/null)
        [ -n "$IP" ] && break
    done

    # ip komutu dene
    if [ -z "$IP" ]; then
        IP=$(ip addr show br-lan 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}' | head -1)
    fi

    # ifconfig fallback
    if [ -z "$IP" ]; then
        IP=$(ifconfig br-lan 2>/dev/null | awk '/inet addr:/ {split($2,a,":"); print a[2]}')
    fi

    # Son fallback
    if [ -z "$IP" ]; then
        IP=$(ifconfig 2>/dev/null | awk '/inet addr:/ && !/127.0.0.1/ {split($2,a,":"); print a[2]}' | head -1)
    fi

    echo "${IP:-192.168.1.1}"
}

# ---------- uhttpd Kurulum ----------
install_uhttpd() {
    # install-binaries.sh zaten kurduysa tekrar indirme
    if [ -f "$UHTTPD_BIN" ] && [ -x "$UHTTPD_BIN" ]; then
        echo -e "${GREEN}✓ uhttpd zaten mevcut (binary'den), atlanıyor${NC}"
        return 0
    fi

    echo -n "📥 uhttpd indiriliyor... "
    wget -q "$GITHUB_BASE/binaries/uhttpd" -O "$UHTTPD_BIN" 2>/dev/null

    if [ $? -eq 0 ] && [ -s "$UHTTPD_BIN" ]; then
        chmod +x "$UHTTPD_BIN"
        ln -sf "$UHTTPD_BIN" /usr/sbin/uhttpd 2>/dev/null
        echo -e "${GREEN}✓${NC}"
    else
        rm -f "$UHTTPD_BIN"
        echo -e "${RED}✗ Hata!${NC}"
        return 1
    fi
}

# ---------- LuCI Kurulum ----------
install_luci() {
    echo -n "📦 LuCI indiriliyor... "
    wget -q "$GITHUB_BASE/luci/x28-luci.tgz" -O /tmp/luci_fixed.tgz 2>/dev/null

    if [ $? -ne 0 ] || [ ! -s /tmp/luci_fixed.tgz ]; then
        echo -e "${RED}✗ İndirme hatası!${NC}"
        return 1
    fi

    echo -e "${GREEN}✓${NC}"
    echo -n "📂 LuCI dosyaları kuruluyor... "

    tar xzf /tmp/luci_fixed.tgz -C /tmp 2>/dev/null

    [ -d "/tmp/www/luci-static" ]    && cp -r /tmp/www/luci-static /www/
    [ -d "/tmp/usr/lib/lua/luci" ]   && cp -r /tmp/usr/lib/lua/luci /usr/lib/lua/
    [ -d "/tmp/usr/share/luci" ]     && cp -r /tmp/usr/share/luci /usr/share/

    rm -f /tmp/luci_fixed.tgz
    rm -rf /tmp/www /tmp/usr 2>/dev/null

    echo -e "${GREEN}✓${NC}"
}

# ---------- Auto Start Script ----------
create_auto_bin() {
    echo -n "📝 Auto-start scripti oluşturuluyor... "
    cat > "$BIN_AUTO" << EOF
#!/bin/sh
UHTTPD="$UHTTPD_BIN"
case "\$1" in
    start)
        if ! pgrep -f "uhttpd.*4153" >/dev/null 2>&1; then
            \$UHTTPD -p 0.0.0.0:4153 -h /www &
        fi
        ;;
    stop)
        killall uhttpd 2>/dev/null
        ;;
    restart)
        killall uhttpd 2>/dev/null
        sleep 1
        \$UHTTPD -p 0.0.0.0:4153 -h /www &
        ;;
    status)
        if pgrep -f "uhttpd.*4153" >/dev/null 2>&1; then
            echo "LuCI çalışıyor (port 4153)"
        else
            echo "LuCI çalışmıyor"
        fi
        ;;
    *)
        echo "Kullanım: \$0 {start|stop|restart|status}"
        ;;
esac
EOF
    chmod +x "$BIN_AUTO"
    ln -sf "$BIN_AUTO" /usr/bin/luci-start 2>/dev/null
    echo -e "${GREEN}✓${NC}"
}

# ---------- Init Script ----------
create_init() {
    echo -n "⚙️  Init script oluşturuluyor... "
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

restart() {
    $BIN_AUTO restart
}
EOF
    chmod +x /etc/init.d/luci-fixer
    /etc/init.d/luci-fixer enable 2>/dev/null
    echo -e "${GREEN}✓${NC}"
}

# ---------- Mevcut uhttpd'yi Durdur ----------
stop_existing_uhttpd() {
    if pgrep uhttpd >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Mevcut uhttpd durduruluyor...${NC}"
        killall uhttpd 2>/dev/null
        sleep 1
    fi
}

# ---------- Ana Akış ----------
install_uhttpd || exit 1
install_luci   || exit 1
create_auto_bin
create_init

# Var olan uhttpd'yi durdur, yenisini başlat
stop_existing_uhttpd
"$BIN_AUTO" start

# IP'yi tespit et
ROUTER_IP=$(get_router_ip)

echo ""
echo -e "${GREEN}🎉 Kurulum tamamlandı!${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "LuCI Adresi: ${GREEN}http://$ROUTER_IP:4153${NC}"
echo -e "Servis:      ${GREEN}luci-start {start|stop|restart|status}${NC}"
echo -e "Otomatik:    ${GREEN}Her reboot'ta başlar (init.d)${NC}"
echo -e "${BLUE}================================${NC}"
