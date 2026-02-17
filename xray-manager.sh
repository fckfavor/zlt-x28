#!/bin/sh
#=============================================
# Xray Manager v1.1.0 - Tam Yönetim Scripti
# ZLT X28 - OpenWrt 19.07
# Mevcut Xray Kullanır (v25.12.2+ uyumlu)
# Geliştirici: FF.Dev ⚡
#=============================================

VERSION="1.1.0"

#============== RENK TANIMLARI ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

#============== DEĞİŞKENLER ==============
XRAY_BIN="/usr/bin/xray"
XRAY_CONFIG="/etc/xray/config.json"
XRAY_CONFIG_DIR="/etc/xray"
XRAY_LOG_DIR="/var/log/xray"
XRAY_INIT="/etc/init.d/xray"
XRAY_UCI_CONFIG="/etc/config/xray"

TUN_INTERFACE="xr0"
TUN_ADDRESS="172.19.0.1/30"
TUN_FWMARK="1"
TUN_TABLE="100"

#============== FONKSİYONLAR ==============
print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}  $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }

#============== GEREKSİNİM KONTROLÜ ==============
check_requirements() {
    print_header "Gereksinimler Kontrol Ediliyor"
    
    local missing=""
    local packages=""
    
    if [ ! -f "$XRAY_BIN" ]; then
        print_error "Xray binary bulunamadı: $XRAY_BIN"
        print_info "Lütfen önce Xray kurun: https://github.com/XTLS/Xray-core"
        return 1
    else
        print_success "Xray mevcut: $($XRAY_BIN version | head -n1)"
    fi
    
    command -v wget >/dev/null 2>&1 || { missing="${missing}wget "; packages="${packages}wget "; }
    command -v unzip >/dev/null 2>&1 || { missing="${missing}unzip "; packages="${packages}unzip "; }
    command -v jq >/dev/null 2>&1 || { missing="${missing}jq "; packages="${packages}jq "; }
    
    if [ -n "$missing" ]; then
        print_error "Eksik paketler: $missing"
        echo ""
        echo -e "${YELLOW}Yüklemek için:${NC} opkg update && opkg install $packages"
        return 1
    fi
    
    print_success "Tüm gereksinimler mevcut"
    return 0
}

#============== URL DECODE ==============
url_decode() {
    local encoded="$1"
    printf '%b' "${encoded//%/\\x}"
}

#============== BASE64 DECODE ==============
base64_decode() {
    local encoded="$1"
    local padding=$((4 - ${#encoded} % 4))
    [ $padding -ne 4 ] && encoded="${encoded}$(printf '=%.0s' $(seq 1 $padding))"
    echo "$encoded" | base64 -d 2>/dev/null
}

#============== TUN AYARLARI ==============
setup_tun() {
    local subnets="$1"
    
    print_info "TUN arayüzü hazırlanıyor..."
    
    ip tuntap add dev $TUN_INTERFACE mode tun 2>/dev/null
    ip addr add $TUN_ADDRESS dev $TUN_INTERFACE 2>/dev/null
    ip link set $TUN_INTERFACE up 2>/dev/null

    ip rule add fwmark $TUN_FWMARK table $TUN_TABLE 2>/dev/null
    ip route add default dev $TUN_INTERFACE table $TUN_TABLE 2>/dev/null

    iptables -t mangle -N XRAY_TUN 2>/dev/null
    iptables -t mangle -F XRAY_TUN
    iptables -t mangle -A XRAY_TUN -i $TUN_INTERFACE -j RETURN
    iptables -t mangle -A XRAY_TUN -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A XRAY_TUN -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A XRAY_TUN -d 255.255.255.255/32 -j RETURN

    if [ -n "$subnets" ]; then
        echo "$subnets" | tr ' ' '\n' | while read subnet; do
            [ -n "$subnet" ] && iptables -t mangle -A XRAY_TUN -d "$subnet" -j RETURN
        done
    fi

    iptables -t mangle -A XRAY_TUN -j MARK --set-mark $TUN_FWMARK
    iptables -t mangle -C PREROUTING -j XRAY_TUN 2>/dev/null || iptables -t mangle -A PREROUTING -j XRAY_TUN
    iptables -t mangle -C OUTPUT -j XRAY_TUN 2>/dev/null || iptables -t mangle -A OUTPUT -j XRAY_TUN
    
    print_success "TUN arayüzü hazır"
}

cleanup_tun() {
    print_info "TUN arayüzü temizleniyor..."
    
    iptables -t mangle -D PREROUTING -j XRAY_TUN 2>/dev/null
    iptables -t mangle -D OUTPUT -j XRAY_TUN 2>/dev/null
    iptables -t mangle -F XRAY_TUN 2>/dev/null
    iptables -t mangle -X XRAY_TUN 2>/dev/null

    ip rule del fwmark $TUN_FWMARK table $TUN_TABLE 2>/dev/null
    ip route del default dev $TUN_INTERFACE table $TUN_TABLE 2>/dev/null

    ip link set $TUN_INTERFACE down 2>/dev/null
    ip link delete $TUN_INTERFACE 2>/dev/null
    
    print_success "TUN arayüzü temizlendi"
}

#============== VLESS CONFIG IMPORT ==============
import_vless_config() {
    local url="$1"
    
    print_header "VLESS Config İçe Aktarılıyor"
    
    local encoded="${url#vless://}"
    local user_info="${encoded%@*}"
    local server_info="${encoded#*@}"
    
    [ -z "$user_info" ] || [ -z "$server_info" ] && { print_error "Geçersiz VLESS URL!"; return 1; }
    
    local uuid="${user_info%#*}"
    local params_str="${user_info#*#}"
    local server="${server_info%/*}"
    local server_host="${server%:*}"
    local server_port="${server#*:}"
    local path_params="${server_info#*/}"
    
    [ -z "$uuid" ] || [ -z "$server_host" ] || [ -z "$server_port" ] && { print_error "Eksik VLESS bilgileri!"; return 1; }
    
    local type="tcp"
    local security="none"
    local path=""
    local host=""
    local sni=""
    local serviceName=""
    local flow=""
    local encryption="none"
    
    if echo "$path_params" | grep -q "?"; then
        local query_str="${path_params#*?}"
        
        type=$(echo "$query_str" | grep -oE 'type=[^&]+' | cut -d= -f2 || echo "tcp")
        security=$(echo "$query_str" | grep -oE 'security=[^&]+' | cut -d= -f2 || echo "none")
        path=$(echo "$query_str" | grep -oE 'path=[^&]+' | cut -d= -f2 | sed 's/%2F/\//g' || echo "")
        host=$(echo "$query_str" | grep -oE 'host=[^&]+' | cut -d= -f2 || echo "")
        sni=$(echo "$query_str" | grep -oE 'sni=[^&]+' | cut -d= -f2 || echo "")
        serviceName=$(echo "$query_str" | grep -oE 'serviceName=[^&]+' | cut -d= -f2 || echo "")
        flow=$(echo "$query_str" | grep -oE 'flow=[^&]+' | cut -d= -f2 || echo "")
        encryption=$(echo "$query_str" | grep -oE 'encryption=[^&]+' | cut -d= -f2 || echo "none")
    fi
    
    [ -n "$params_str" ] && {
        type=$(echo "$params_str" | grep -oE 'type=[^&]+' | cut -d= -f2 || echo "$type")
        security=$(echo "$params_str" | grep -oE 'security=[^&]+' | cut -d= -f2 || echo "$security")
        path=$(echo "$params_str" | grep -oE 'path=[^&]+' | cut -d= -f2 | sed 's/%2F/\//g' || echo "$path")
        host=$(echo "$params_str" | grep -oE 'host=[^&]+' | cut -d= -f2 || echo "$host")
        sni=$(echo "$params_str" | grep -oE 'sni=[^&]+' | cut -d= -f2 || echo "$sni")
        serviceName=$(echo "$params_str" | grep -oE 'serviceName=[^&]+' | cut -d= -f2 || echo "$serviceName")
        flow=$(echo "$params_str" | grep -oE 'flow=[^&]+' | cut -d= -f2 || echo "$flow")
        encryption=$(echo "$params_str" | grep -oE 'encryption=[^&]+' | cut -d= -f2 || echo "$encryption")
    }
    
    type=$(url_decode "$type")
    security=$(url_decode "$security")
    path=$(url_decode "$path")
    host=$(url_decode "$host")
    sni=$(url_decode "$sni")
    serviceName=$(url_decode "$serviceName")
    flow=$(url_decode "$flow")
    encryption=$(url_decode "$encryption")
    
    print_success "VLESS bilgileri alındı"
    echo -e "  Sunucu: ${CYAN}$server_host:$server_port${NC}"
    echo -e "  UUID: ${CYAN}$uuid${NC}"
    echo -e "  Type: ${CYAN}$type${NC}, Security: ${CYAN}$security${NC}"
    
    cat > $XRAY_CONFIG << EOF
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 1081,
      "protocol": "http",
      "settings": {}
    },
    {
      "tag": "tun-in",
      "protocol": "tun",
      "settings": {
        "address": ["172.19.0.2/30"],
        "mtu": 1500,
        "stack": "system"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$server_host",
            "port": $server_port,
            "users": [
              {
                "id": "$uuid",
                "encryption": "$encryption",
                "flow": "$flow"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "$type",
        "security": "$security",
EOF

    if [ "$security" = "tls" ] || [ "$security" = "reality" ]; then
        cat >> $XRAY_CONFIG << EOF
        "tlsSettings": {
          "serverName": "$sni"
        },
EOF
    fi

    if [ "$type" = "tcp" ]; then
        cat >> $XRAY_CONFIG << EOF
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
EOF
    elif [ "$type" = "ws" ]; then
        cat >> $XRAY_CONFIG << EOF
        "wsSettings": {
          $(if [ -n "$path" ]; then echo "\"path\": \"$path\""; fi)
          $(if [ -n "$path" ] && [ -n "$host" ]; then echo ","; fi)
          $(if [ -n "$host" ]; then echo "\"headers\": { \"Host\": \"$host\" }"; fi)
        }
EOF
    elif [ "$type" = "grpc" ]; then
        cat >> $XRAY_CONFIG << EOF
        "grpcSettings": {
          "serviceName": "$serviceName"
        }
EOF
    elif [ "$type" = "kcp" ]; then
        cat >> $XRAY_CONFIG << EOF
        "kcpSettings": {
          "mtu": 1350,
          "tti": 20,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 1,
          "writeBufferSize": 1,
          "header": {
            "type": "none"
          }
        }
EOF
    else
        cat >> $XRAY_CONFIG << EOF
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
EOF
    fi

    cat >> $XRAY_CONFIG << EOF
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["tun-in"],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

    print_success "VLESS config oluşturuldu"
    return 0
}

#============== VMESS CONFIG IMPORT ==============
import_vmess_config() {
    local url="$1"
    
    print_header "VMess Config İçe Aktarılıyor"
    
    local encoded="${url#vmess://}"
    local decoded=$(base64_decode "$encoded")
    
    [ -z "$decoded" ] && { print_error "VMess link decode edilemedi!"; return 1; }
    
    local config=$(echo "$decoded" | jq -r '.' 2>/dev/null)
    [ $? -ne 0 ] && { print_error "Geçersiz VMess JSON!"; return 1; }
    
    local ps=$(echo "$config" | jq -r '.ps // "VMess Connection"')
    local add=$(echo "$config" | jq -r '.add')
    local port=$(echo "$config" | jq -r '.port')
    local id=$(echo "$config" | jq -r '.id')
    local aid=$(echo "$config" | jq -r '.aid // "0"')
    local net=$(echo "$config" | jq -r '.net // "tcp"')
    local type=$(echo "$config" | jq -r '.type // "none"')
    local host=$(echo "$config" | jq -r '.host // ""')
    local path=$(echo "$config" | jq -r '.path // ""')
    local tls=$(echo "$config" | jq -r '.tls // "none"')
    local sni=$(echo "$config" | jq -r '.sni // ""')
    
    print_success "VMess bilgileri alındı"
    echo -e "  Açıklama: ${CYAN}$ps${NC}"
    echo -e "  Sunucu: ${CYAN}$add:$port${NC}"
    echo -e "  Protocol: ${CYAN}$net${NC}, TLS: ${CYAN}$tls${NC}"
    
    cat > $XRAY_CONFIG << EOF
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 1081,
      "protocol": "http",
      "settings": {}
    },
    {
      "tag": "tun-in",
      "protocol": "tun",
      "settings": {
        "address": ["172.19.0.2/30"],
        "mtu": 1500,
        "stack": "system"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "$add",
            "port": $port,
            "users": [
              {
                "id": "$id",
                "alterId": $aid,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "$net",
        "security": "$tls",
EOF

    if [ "$tls" = "tls" ]; then
        cat >> $XRAY_CONFIG << EOF
        "tlsSettings": {
          "serverName": "$sni"
        },
EOF
    fi

    if [ "$net" = "tcp" ]; then
        cat >> $XRAY_CONFIG << EOF
        "tcpSettings": {
          "header": {
            "type": "$type"
            $(if [ "$type" = "http" ] && [ -n "$host" ]; then
                echo ', "request": { "headers": { "Host": ["'$host'"] } }'
            fi)
          }
        }
EOF
    elif [ "$net" = "ws" ]; then
        cat >> $XRAY_CONFIG << EOF
        "wsSettings": {
          $(if [ -n "$path" ]; then echo "\"path\": \"$path\""; fi)
          $(if [ -n "$path" ] && [ -n "$host" ]; then echo ","; fi)
          $(if [ -n "$host" ]; then echo "\"headers\": { \"Host\": \"$host\" }"; fi)
        }
EOF
    elif [ "$net" = "h2" ]; then
        cat >> $XRAY_CONFIG << EOF
        "httpSettings": {
          $(if [ -n "$path" ]; then echo "\"path\": \"$path\""; fi)
          $(if [ -n "$path" ] && [ -n "$host" ]; then echo ","; fi)
          $(if [ -n "$host" ]; then echo "\"host\": [\"$host\"]"; fi)
        }
EOF
    elif [ "$net" = "grpc" ]; then
        cat >> $XRAY_CONFIG << EOF
        "grpcSettings": {
          "serviceName": "$path"
        }
EOF
    else
        cat >> $XRAY_CONFIG << EOF
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
EOF
    fi

    cat >> $XRAY_CONFIG << EOF
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["tun-in"],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

    print_success "VMess config oluşturuldu: $ps"
    return 0
}

#============== CONFIG URL'DEN YÜKLE ==============
import_config_from_url() {
    local url="$1"
    
    print_header "Config İçe Aktarma"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq kurulu değil! opkg install jq"
        return 1
    fi
    
    case "$url" in
        vmess://*) import_vmess_config "$url" ;;
        vless://*) import_vless_config "$url" ;;
        *) print_error "Desteklenmeyen link formatı! (vmess:// veya vless://)"; return 1 ;;
    esac
    
    if [ $? -eq 0 ]; then
        print_success "Config oluşturuldu!"
        echo ""
        print_info "Config test ediliyor..."
        
        if $XRAY_BIN test -config $XRAY_CONFIG >/dev/null 2>&1; then
            print_success "Config testi başarılı!"
            if [ -f $XRAY_INIT ]; then
                $XRAY_INIT restart
            fi
            sleep 2
            show_status
        else
            print_error "Config testi başarısız!"
            $XRAY_BIN test -config $XRAY_CONFIG
        fi
    fi
}

#============== KURULUM (SADECE LUCI) ==============
install_xray() {
    print_header "Xray LuCI Kurulumu Başlıyor"
    
    if [ ! -f "$XRAY_BIN" ]; then
        print_error "Xray binary bulunamadı: $XRAY_BIN"
        print_info "Lütfen önce Xray kurun: https://github.com/XTLS/Xray-core"
        exit 1
    fi
    
    check_requirements || exit 1
    
    print_success "Xray mevcut: $($XRAY_BIN version | head -n1)"
    
    mkdir -p $XRAY_CONFIG_DIR
    mkdir -p $XRAY_LOG_DIR
    touch $XRAY_LOG_DIR/access.log $XRAY_LOG_DIR/error.log
    
    cat > $XRAY_UCI_CONFIG << 'EOF'
config xray 'config'
	option enabled '0'
	option config_file '/etc/xray/config.json'
	option log_level 'warning'
	option tun_enabled '0'
	option tun_subnets ''
EOF
    print_success "UCI config oluşturuldu"
    
    cat > $XRAY_INIT << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PROG=/usr/bin/xray
CONF=/etc/xray/config.json
TUN_INTERFACE="xr0"
TUN_ADDRESS="172.19.0.1/30"
TUN_FWMARK="1"
TUN_TABLE="100"

setup_tun() {
	local subnets="$1"
    
	ip tuntap add dev $TUN_INTERFACE mode tun 2>/dev/null
	ip addr add $TUN_ADDRESS dev $TUN_INTERFACE 2>/dev/null
	ip link set $TUN_INTERFACE up 2>/dev/null

	ip rule add fwmark $TUN_FWMARK table $TUN_TABLE 2>/dev/null
	ip route add default dev $TUN_INTERFACE table $TUN_TABLE 2>/dev/null

	iptables -t mangle -N XRAY_TUN 2>/dev/null
	iptables -t mangle -F XRAY_TUN
	iptables -t mangle -A XRAY_TUN -i $TUN_INTERFACE -j RETURN
	iptables -t mangle -A XRAY_TUN -d 127.0.0.0/8 -j RETURN
	iptables -t mangle -A XRAY_TUN -d 224.0.0.0/4 -j RETURN
	iptables -t mangle -A XRAY_TUN -d 255.255.255.255/32 -j RETURN

	if [ -n "$subnets" ]; then
		echo "$subnets" | tr ' ' '\n' | while read subnet; do
			[ -n "$subnet" ] && iptables -t mangle -A XRAY_TUN -d "$subnet" -j RETURN
		done
	fi

	iptables -t mangle -A XRAY_TUN -j MARK --set-mark $TUN_FWMARK
	iptables -t mangle -C PREROUTING -j XRAY_TUN 2>/dev/null || iptables -t mangle -A PREROUTING -j XRAY_TUN
	iptables -t mangle -C OUTPUT -j XRAY_TUN 2>/dev/null || iptables -t mangle -A OUTPUT -j XRAY_TUN
	
	logger -t xray "TUN interface $TUN_INTERFACE ready"
}

cleanup_tun() {
	iptables -t mangle -D PREROUTING -j XRAY_TUN 2>/dev/null
	iptables -t mangle -D OUTPUT -j XRAY_TUN 2>/dev/null
	iptables -t mangle -F XRAY_TUN 2>/dev/null
	iptables -t mangle -X XRAY_TUN 2>/dev/null

	ip rule del fwmark $TUN_FWMARK table $TUN_TABLE 2>/dev/null
	ip route del default dev $TUN_INTERFACE table $TUN_TABLE 2>/dev/null

	ip link set $TUN_INTERFACE down 2>/dev/null
	ip link delete $TUN_INTERFACE 2>/dev/null
	
	logger -t xray "TUN interface cleaned up"
}

start_service() {
	config_load xray
	local enabled tun_enabled tun_subnets
	config_get_bool enabled config enabled 0
	config_get_bool tun_enabled config tun_enabled 0
	config_get tun_subnets config tun_subnets ""
	
	[ "$enabled" -eq 0 ] && return 1
	[ ! -f "$CONF" ] && { logger -t xray "Config not found: $CONF"; return 1; }

	[ "$tun_enabled" -eq 1 ] && setup_tun "$tun_subnets"
	
	procd_open_instance
	procd_set_param command $PROG run -config $CONF
	procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file $CONF
	procd_close_instance
	
	logger -t xray "Xray started"
}

stop_service() {
	killall xray 2>/dev/null
	cleanup_tun
	logger -t xray "Xray stopped"
}

reload_service() {
	stop
	sleep 1
	start
}

service_triggers() {
	procd_add_reload_trigger "xray"
}
EOF
    chmod +x $XRAY_INIT
    print_success "Init script oluşturuldu"
    
    if [ ! -f $XRAY_CONFIG ]; then
        cat > $XRAY_CONFIG << 'EOF'
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 1081,
      "protocol": "http",
      "settings": {}
    },
    {
      "tag": "tun-in",
      "protocol": "tun",
      "settings": {
        "address": ["172.19.0.2/30"],
        "mtu": 1500,
        "stack": "system"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["tun-in"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
        print_success "Varsayılan config oluşturuldu"
    fi
    
    mkdir -p /usr/lib/lua/luci/controller
    cat > /usr/lib/lua/luci/controller/xray.lua << 'EOF'
module("luci.controller.xray", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/xray") then return end

    local page = entry({"admin", "services", "xray"}, firstchild(), _("Xray"), 60)
    page.dependent = false
    
    entry({"admin", "services", "xray", "general"}, cbi("xray/general"), _("General Settings"), 1)
    entry({"admin", "services", "xray", "config"}, cbi("xray/config"), _("Configuration"), 2)
    entry({"admin", "services", "xray", "import"}, cbi("xray/import"), _("Import Config"), 3)
    entry({"admin", "services", "xray", "status"}, call("action_status"))
    entry({"admin", "services", "xray", "logs"}, call("action_logs"))
    entry({"admin", "services", "xray", "parse_url"}, call("action_parse_url"))
end

function action_status()
    local sys = require "luci.sys"
    local util = require "luci.util"
    local status = {}
    
    local pid = util.trim(sys.exec("pidof xray 2>/dev/null"))
    status.running = pid ~= ""
    
    if status.running then
        status.uptime = util.trim(sys.exec("ps -o etime= -p " .. pid .. " 2>/dev/null"))
        local mem = sys.exec("cat /proc/" .. pid .. "/status 2>/dev/null | grep VmRSS"):match("(%d+)")
        status.memory = mem and string.format("%.1f MB", tonumber(mem) / 1024) or "N/A"
    else
        status.uptime = "N/A"
        status.memory = "N/A"
    end
    
    local version = sys.exec("/usr/bin/xray version 2>/dev/null | head -n1")
    status.version = version:match("Xray ([%d%.]+)") or version:match("([%d%.]+)") or "Unknown"
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(status)
end

function action_logs()
    local log_content = nixio.fs.readfile("/var/log/xray/error.log") or "No logs available"
    luci.http.prepare_content("text/plain; charset=utf-8")
    luci.http.write(log_content)
end

function action_parse_url()
    local result = { success = false, message = "" }
    local url = luci.http.formvalue("url")
    
    if not url or url == "" then
        result.message = "URL boş olamaz!"
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
        return
    end
    
    local parse_result = luci.sys.exec("/usr/bin/xray_manager.sh import \"" .. url .. "\" 2>&1")
    
    if parse_result:find("başarıyla") or parse_result:find("success") or parse_result:find("oluşturuldu") then
        result.success = true
        result.message = "Config başarıyla içe aktarıldı!"
    else
        result.message = "İçe aktarma başarısız: " .. parse_result
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end
EOF

    mkdir -p /usr/lib/lua/luci/model/cbi/xray
    
    cat > /usr/lib/lua/luci/model/cbi/xray/general.lua << 'EOF'
local sys = require "luci.sys"

m = Map("xray", translate("Xray"), translate("Xray - FF.Dev Edition ⚡"))

s = m:section(TypedSection, "xray", translate("Service Status"))
s.anonymous = true
o = s:option(DummyValue, "_status", translate("Current Status"))
o.template = "xray/status"

s = m:section(TypedSection, "xray", translate("Service Control"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable Xray Service"))
o.rmempty = false
o.default = "0"

o = s:option(Value, "config_file", translate("Configuration File Path"))
o.default = "/etc/xray/config.json"
o.datatype = "file"

o = s:option(ListValue, "log_level", translate("Log Level"))
o:value("debug", "Debug")
o:value("info", "Info")
o:value("warning", "Warning")
o:value("error", "Error")
o:value("none", "None")
o.default = "warning"

s = m:section(TypedSection, "xray", translate("TUN Settings"))
s.anonymous = true

o = s:option(Flag, "tun_enabled", translate("Route all traffic through TUN"))
o.rmempty = false
o.default = "0"

o = s:option(TextValue, "tun_subnets", translate("Subnets to exclude from TUN"))
o.rows = 4
o.wrap = "off"
o.placeholder = "192.168.1.0/24\n10.0.0.0/8"

s = m:section(TypedSection, "xray", translate("Service Actions"))
s.anonymous = true

btn_start = s:option(Button, "_start", translate("Start"))
btn_start.inputstyle = "apply"
function btn_start.write() sys.call("/etc/init.d/xray start >/dev/null 2>&1 &") end

btn_stop = s:option(Button, "_stop", translate("Stop"))
btn_stop.inputstyle = "reset"
function btn_stop.write() sys.call("/etc/init.d/xray stop >/dev/null 2>&1") end

btn_restart = s:option(Button, "_restart", translate("Restart"))
btn_restart.inputstyle = "reload"
function btn_restart.write() sys.call("/etc/init.d/xray restart >/dev/null 2>&1 &") end

btn_logs = s:option(Button, "_logs", translate("View Logs"))
btn_logs.inputstyle = "edit"
btn_logs.template = "xray/logs_button"

return m
EOF

    cat > /usr/lib/lua/luci/model/cbi/xray/config.lua << 'EOF'
local fs = require "nixio.fs"
local sys = require "luci.sys"

m = Map("xray", translate("Xray Configuration"), translate("Edit Xray JSON configuration file - FF.Dev ⚡"))

s = m:section(TypedSection, "xray", "")
s.anonymous = true

o = s:option(TextValue, "_config")
o.rows = 30
o.wrap = "off"

function o.cfgvalue(self, section)
    return fs.readfile("/etc/xray/config.json") or ""
end

function o.write(self, section, value)
    if value then
        value = value:gsub("\r\n?", "\n")
        local tmpfile = "/tmp/xray_config_test.json"
        fs.writefile(tmpfile, value)
        
        if sys.call("/usr/bin/xray test -c " .. tmpfile .. " >/dev/null 2>&1") == 0 then
            fs.writefile("/etc/xray/config.json", value)
            sys.call("/etc/init.d/xray reload >/dev/null 2>&1 &")
            m.message = translate("✅ Configuration saved and service reloaded.")
        else
            m.message = translate("❌ ERROR: Invalid JSON! Configuration NOT saved.")
        end
        fs.remove(tmpfile)
    end
end

return m
EOF

    cat > /usr/lib/lua/luci/model/cbi/xray/import.lua << 'EOF'
local sys = require "luci.sys"
local http = require "luci.http"

m = Map("xray", translate("Import Xray Configuration"), 
        translate("Import configuration from VMess/VLESS URL - FF.Dev ⚡"))

s = m:section(TypedSection, "xray", translate("URL Import"))
s.anonymous = true

o = s:option(TextValue, "config_url", translate("Configuration URL"))
o.rows = 3
o.wrap = "off"
o.placeholder = "vless://uuid@server:port?type=ws&security=tls&path=/path&host=example.com"

help = s:option(DummyValue, "_help", translate("Supported Formats"))
help.rawhtml = true
help.value = [[
<div style="background:#f9f9f9;padding:10px;border-radius:5px;font-size:12px;border-left:4px solid #00aa00">
<strong>✨ FF.Dev Xray Import ✨</strong><br><br>
<strong>VMess:</strong> vmess://eyJ2IjoiMiIsInBzIjoiIiw...<br>
<strong>VLESS:</strong> vless://uuid@server:port?type=ws&path=/path&security=tls<br>
<br>
<strong>Supported Parameters:</strong><br>
• type: tcp, ws, grpc, kcp<br>
• security: none, tls, reality<br>
• path, host, sni, serviceName, flow, encryption
</div>
]]

btn_import = s:option(Button, "_import", translate("Import Configuration"))
btn_import.inputstyle = "apply"

function btn_import.write(self, section)
    local url = m:formvalue("cbid.xray._import.config_url") or ""
    
    if url == "" then
        m.message = translate("Error: URL cannot be empty!")
        return
    end
    
    local luci_dispatcher = require "luci.dispatcher"
    local import_url = luci_dispatcher.build_url("admin", "services", "xray", "parse_url")
    
    m.message = translate("Importing configuration... Please wait.")
    
    http.write([[<script type="text/javascript">
        var url = ']] .. url .. [[';
        
        fetch(']] .. import_url .. [[', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'url=' + encodeURIComponent(url)
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                alert('✅ ' + data.message);
                window.location.href = ']] .. luci_dispatcher.build_url("admin", "services", "xray", "config") .. [[';
            } else {
                alert('❌ ' + data.message);
            }
        })
        .catch(error => alert('❌ Import error: ' + error));
    </script>]])
end

return m
EOF

    mkdir -p /usr/lib/lua/luci/view/xray
    
    cat > /usr/lib/lua/luci/view/xray/status.htm << 'EOF'
<%+cbi/valueheader%>
<style>
.ffdev-badge {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 10px;
    font-weight: bold;
    margin-left: 5px;
}
</style>
<script type="text/javascript">
    XHR.poll(3, '<%=luci.dispatcher.build_url("admin", "services", "xray", "status")%>', null,
        function(x, status) {
            var tb = document.getElementById('xray_status');
            if (tb && status) {
                var html = status.running 
                    ? '<span style="color:green;font-weight:bold">● Running</span> <span class="ffdev-badge">FF.Dev</span><br/>' +
                      '<small>Version: <b>' + status.version + '</b> | ' +
                      'Uptime: <b>' + status.uptime + '</b> | ' +
                      'Memory: <b>' + status.memory + '</b></small>'
                    : '<span style="color:red;font-weight:bold">● Stopped</span> <span class="ffdev-badge">FF.Dev</span><br/>' +
                      '<small>Version: <b>' + status.version + '</b></small>';
                
                html += '<br><br><a href="<%=luci.dispatcher.build_url("admin", "services", "xray", "import")%>" ' +
                        'class="cbi-button cbi-button-apply" style="font-size:12px">📥 Import Config from URL</a>';
                tb.innerHTML = html;
            }
        }
    );
</script>
<div id="xray_status" style="padding:10px;background:#f9f9f9;border-radius:5px;border-left:4px solid #00aa00">
    <em><%:Checking status...%></em>
</div>
<%+cbi/valuefooter%>
EOF

    cat > /usr/lib/lua/luci/view/xray/logs_button.htm << 'EOF'
<%+cbi/valueheader%>
<input class="cbi-button cbi-button-edit" type="button" value="<%:View Logs%>" 
       onclick="window.open('<%=luci.dispatcher.build_url("admin", "services", "xray", "logs")%>', '_blank', 'width=800,height=600,scrollbars=yes')" />
<div style="font-size:10px;color:#666;margin-top:2px">FF.Dev ⚡</div>
<%+cbi/valuefooter%>
EOF

    mkdir -p /usr/share/rpcd/acl.d
    cat > /usr/share/rpcd/acl.d/luci-app-xray.json << 'EOF'
{
    "luci-app-xray": {
        "description": "Xray Manager - FF.Dev Edition",
        "read": {
            "ubus": {"service": ["list", "signal"]},
            "uci": ["xray"],
            "file": {
                "/etc/xray/config.json": ["read"],
                "/var/log/xray/*.log": ["read"]
            }
        },
        "write": {
            "ubus": {"service": ["signal"]},
            "uci": ["xray"],
            "cgi-io": ["exec"],
            "file": {
                "/etc/xray/config.json": ["write"],
                "/var/log/xray/*.log": ["write"]
            }
        }
    }
}
EOF

    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/* /tmp/luci-sessions/*
    /etc/init.d/rpcd restart 2>/dev/null
    $XRAY_INIT enable 2>/dev/null
    
    print_header "✅ Kurulum Başarıyla Tamamlandı!"
    echo -e "${GREEN}🌐 LuCI:${NC} http://$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"
    echo -e "${GREEN}📁 Menü:${NC} Services → Xray → Import Config"
    echo ""
    echo -e "${YELLOW}⚠ URL'nizi yapıştırın ve Import butonuna basın.${NC}"
    echo -e "${PURPLE}⚡ FF.Dev - Yazılımın Efendisi ⚡${NC}"
    echo ""
}

#============== KALDIRMA ==============
uninstall_xray() {
    print_header "Xray Kaldırılıyor"
    
    print_info "Servis durduruluyor..."
    [ -f $XRAY_INIT ] && $XRAY_INIT stop 2>/dev/null
    [ -f $XRAY_INIT ] && $XRAY_INIT disable 2>/dev/null
    
    print_info "LuCI dosyaları siliniyor..."
    rm -f /usr/lib/lua/luci/controller/xray.lua
    rm -rf /usr/lib/lua/luci/model/cbi/xray
    rm -rf /usr/lib/lua/luci/view/xray
    rm -f /usr/share/rpcd/acl.d/luci-app-xray.json
    rm -f $XRAY_INIT
    rm -f $XRAY_UCI_CONFIG
    rm -rf /tmp/luci-*
    
    /etc/init.d/rpcd restart 2>/dev/null
    
    print_success "Xray LuCI kaldırıldı!"
    echo -e "${PURPLE}⚡ FF.Dev ⚡${NC}"
    echo ""
    print_info "Xray binary (/usr/bin/xray) ve config (/etc/xray) silinmedi."
    print_info "Tamamen kaldırmak için: rm -f /usr/bin/xray && rm -rf /etc/xray"
    echo ""
}

#============== DURUM ==============
show_status() {
    print_header "Xray Durum Bilgisi"
    
    [ ! -f $XRAY_BIN ] && { print_error "Xray kurulu değil!"; return 1; }
    
    local version=$($XRAY_BIN version 2>/dev/null | head -n1)
    local pid=$(pidof xray)
    local enabled=$(uci get xray.config.enabled 2>/dev/null)
    
    echo -e "  Versiyon: ${CYAN}$version${NC}"
    echo -e "  UCI Enabled: ${CYAN}$enabled${NC}"
    echo ""
    
    if [ -n "$pid" ]; then
        print_success "Durum: Çalışıyor (PID: $pid)"
        local uptime=$(ps -o etime= -p $pid 2>/dev/null | awk '{print $1}')
        local mem=$(cat /proc/$pid/status 2>/dev/null | grep VmRSS | awk '{printf "%.1f MB", $2/1024}')
        echo -e "  Uptime: ${CYAN}$uptime${NC}"
        echo -e "  Memory: ${CYAN}$mem${NC}"
    else
        print_error "Durum: Durdurulmuş"
    fi
    
    echo -e "\n  Config: ${CYAN}$XRAY_CONFIG${NC}"
    echo -e "  Logs:   ${CYAN}$XRAY_LOG_DIR/error.log${NC}"
    echo -e "\n${PURPLE}⚡ FF.Dev ⚡${NC}"
}

#============== LOG GÖSTER ==============
show_logs() {
    [ ! -f $XRAY_LOG_DIR/error.log ] && { print_error "Log dosyası bulunamadı!"; return 1; }
    echo ""
    echo -e "${BLUE}━━━━━━ Son 50 Log Satırı ━━━━━${NC}"
    echo ""
    tail -n 50 $XRAY_LOG_DIR/error.log
    echo ""
    echo -e "${PURPLE}⚡ FF.Dev ⚡${NC}"
}

#============== MENÜ ==============
show_menu() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║        🔥 Xray Manager v${VERSION} - FF.Dev ⚡          ║"
    echo "║        ZLT X28 - OpenWrt 19.07                      ║"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║                                                      ║"
    echo "║  1) 📦 LuCI Kurulum (LuCI Install)                  ║"
    echo "║  2) 🗑️  Kaldırma (Uninstall LuCI)                   ║"
    echo "║  3) 📊 Durum (Status)                               ║"
    echo "║  4) ▶️  Başlat (Start)                              ║"
    echo "║  5) ⏹️  Durdur (Stop)                               ║"
    echo "║  6) 🔁 Yeniden Başlat (Restart)                     ║"
    echo "║  7) 📜 Logları Göster (View Logs)                   ║"
    echo "║  8) 🔗 URL'den Yükle (Import from URL)              ║"
    echo "║                                                      ║"
    echo "║  0) 🚪 Çıkış (Exit)                                 ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo -n "👉 Seçiminiz: "
}

#============== ANA PROGRAM ==============
case "$1" in
    install) install_xray; exit 0 ;;
    uninstall) uninstall_xray; exit 0 ;;
    status) show_status; exit 0 ;;
    logs) show_logs; exit 0 ;;
    import) 
        if [ -n "$2" ]; then
            import_config_from_url "$2"
            exit 0
        else
            echo "Kullanım: $0 import <vmess_or_vless_url>"
            exit 1
        fi
        ;;
    start) [ -f $XRAY_INIT ] && $XRAY_INIT start; show_status; exit 0 ;;
    stop) [ -f $XRAY_INIT ] && $XRAY_INIT stop; show_status; exit 0 ;;
    restart) [ -f $XRAY_INIT ] && $XRAY_INIT restart; show_status; exit 0 ;;
    --help|-h)
        echo "Xray Manager v${VERSION} - FF.Dev ⚡"
        echo ""
        echo "Kullanım: $0 [komut]"
        echo ""
        echo "Komutlar:"
        echo "  install          - LuCI arayüzünü kur (Xray binary mevcut olmalı)"
        echo "  uninstall        - LuCI arayüzünü kaldır"
        echo "  status           - Durum göster"
        echo "  logs             - Logları göster"
        echo "  import <url>     - URL'den config içe aktar"
        echo "  start            - Servisi başlat"
        echo "  stop             - Servisi durdur"
        echo "  restart          - Servisi yeniden başlat"
        echo ""
        echo "Parametresiz çalıştırırsanız interaktif menü açılır."
        exit 0
        ;;
esac

# İnteraktif menü
while true; do
    show_menu
    read choice
    
    case $choice in
        1) install_xray; read -p "Devam için ENTER..."; ;;
        2) uninstall_xray; read -p "Devam için ENTER..."; ;;
        3) show_status; read -p "Devam için ENTER..."; ;;
        4) [ -f $XRAY_INIT ] && $XRAY_INIT start; show_status; read -p "Devam için ENTER..."; ;;
        5) [ -f $XRAY_INIT ] && $XRAY_INIT stop; show_status; read -p "Devam için ENTER..."; ;;
        6) [ -f $XRAY_INIT ] && $XRAY_INIT restart; show_status; read -p "Devam için ENTER..."; ;;
        7) show_logs; read -p "Devam için ENTER..."; ;;
        8) 
            echo -n "🔗 VMess/VLESS URL: "
            read config_url
            if [ -n "$config_url" ]; then
                import_config_from_url "$config_url"
            else
                print_error "URL boş olamaz!"
            fi
            read -p "Devam için ENTER..."; 
            ;;
        0) 
            echo ""
            echo -e "${PURPLE}╔══════════════════════════════╗${NC}"
            echo -e "${PURPLE}║     FF.Dev - Görüşmek Üzere  ║${NC}"
            echo -e "${PURPLE}║        ⚡ Hoşçakal ⚡         ║${NC}"
            echo -e "${PURPLE}╚══════════════════════════════╝${NC}"
            echo ""
            exit 0 
            ;;
        *) print_error "Geçersiz seçim!"; sleep 2; ;;
    esac
done
