#!/bin/sh

# =============================
# BINARY INSTALLER v3.0 - ZIP EDITION
# OpenWrt / BusyBox Optimized
# =============================

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

DATA_DIR="/data/.binaries"
TEMP_DIR="/tmp/zlt-install"
GITHUB_ZIP="https://github.com/fckfavor/zlt-x28/archive/refs/heads/main.zip"
BINARY_PATH="zlt-x28-main/binaries"

# ---------- Print Functions ----------
print_green() { echo -e "${GREEN}$1${NC}"; }
print_red() { echo -e "${RED}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_blue() { echo -e "${BLUE}$1${NC}"; }

# ---------- Progress Bar for wget ----------
download_with_progress() {
    URL="$1"
    OUTPUT="$2"
    
    print_blue "Downloading: $(basename "$OUTPUT")"
    
    # BusyBox wget with progress dots
    wget -O "$OUTPUT" "$URL" 2>&1 | while read line; do
        if echo "$line" | grep -q '%'; then
            PERCENT=$(echo "$line" | grep -o '[0-9]\+%' | head -1)
            if [ -n "$PERCENT" ]; then
                bars=$(( ${PERCENT%\%} / 2 ))
                printf "\r${BLUE}[%-50s${NC}] %s" "$(printf '#%.0s' $(seq 1 $bars 2>/dev/null || echo 0))" "$PERCENT"
            fi
        fi
    done
    
    if [ $? -eq 0 ] && [ -f "$OUTPUT" ]; then
        printf "\r${GREEN}[##################################################] 100%%${NC}\n"
        return 0
    else
        printf "\r${RED}[##################################################] FAILED${NC}\n"
        return 1
    fi
}

# ---------- Root Check ----------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_red "Error: Root privileges required!"
        exit 1
    fi
}

# ---------- Create Directories ----------
create_dirs() {
    print_yellow "Creating directories..."
    mkdir -p "$DATA_DIR"
    mkdir -p "$TEMP_DIR"
    print_green "✓ Directory: $DATA_DIR"
    print_green "✓ Temp: $TEMP_DIR"
}

# ---------- Download ZIP ----------
download_zip() {
    ZIP_FILE="$TEMP_DIR/repo.zip"
    
    print_blue "Downloading complete repository as ZIP..."
    print_yellow "URL: $GITHUB_ZIP"
    
    if command -v wget >/dev/null 2>&1; then
        download_with_progress "$GITHUB_ZIP" "$ZIP_FILE"
    else
        curl -L "$GITHUB_ZIP" -o "$ZIP_FILE" --progress-bar
    fi
    
    if [ ! -f "$ZIP_FILE" ] || [ ! -s "$ZIP_FILE" ]; then
        print_red "Download failed!"
        return 1
    fi
    
    SIZE=$(ls -l "$ZIP_FILE" | awk '{print $5}')
    print_green "✓ ZIP downloaded: $SIZE bytes"
    return 0
}

# ---------- Extract ZIP ----------
extract_zip() {
    ZIP_FILE="$TEMP_DIR/repo.zip"
    
    print_blue "Extracting ZIP..."
    
    # Check if unzip exists
    if ! command -v unzip >/dev/null 2>&1; then
        print_yellow "unzip not found, trying to extract with tar/ar..."
        
        # Try to list contents
        cd "$TEMP_DIR"
        
        # Alternative extraction for BusyBox
        if command -v tar >/dev/null 2>&1; then
            print_yellow "Using tar to extract..."
            tar -xf "$ZIP_FILE" 2>/dev/null
        else
            # Fallback: use unzip from busybox
            busybox unzip "$ZIP_FILE" -d "$TEMP_DIR" 2>/dev/null
        fi
    else
        unzip -q "$ZIP_FILE" -d "$TEMP_DIR"
    fi
    
    # Check if extraction worked
    if [ -d "$TEMP_DIR/zlt-x28-main" ]; then
        print_green "✓ Extraction complete!"
        return 0
    else
        print_red "Extraction failed! Looking for extracted files..."
        find "$TEMP_DIR" -type d | head -5
        return 1
    fi
}

# ---------- List Available Binaries ----------
list_binaries() {
    BINARY_SOURCE="$TEMP_DIR/$BINARY_PATH"
    
    if [ ! -d "$BINARY_SOURCE" ]; then
        print_red "Binary directory not found: $BINARY_SOURCE"
        return 1
    fi
    
    # Get all files in binaries directory
    BINARIES=$(ls -1 "$BINARY_SOURCE" 2>/dev/null | grep -v '^$')
    
    if [ -z "$BINARIES" ]; then
        print_red "No binaries found in ZIP!"
        return 1
    fi
    
    COUNT=$(echo "$BINARIES" | wc -l)
    print_green "✓ Found $COUNT binaries in ZIP:"
    echo "$BINARIES" | while read bin; do
        SIZE=$(ls -l "$BINARY_SOURCE/$bin" 2>/dev/null | awk '{print $5}')
        echo "   - $bin ($SIZE bytes)"
    done
    
    return 0
}

# ---------- Check if Binary Exists ----------
binary_exists() {
    BIN_NAME="$1"
    
    if [ -f "$DATA_DIR/$BIN_NAME" ] && [ -x "$DATA_DIR/$BIN_NAME" ]; then
        return 0
    fi
    return 1
}

# ---------- Install Binary from ZIP ----------
install_binary() {
    BINARY_NAME="$1"
    SOURCE="$TEMP_DIR/$BINARY_PATH/$BINARY_NAME"
    DEST="$DATA_DIR/$BINARY_NAME"
    
    if [ ! -f "$SOURCE" ]; then
        print_red "Source not found: $SOURCE"
        return 1
    fi
    
    # Check if already installed
    if binary_exists "$BINARY_NAME"; then
        LOCAL_SIZE=$(ls -l "$DEST" 2>/dev/null | awk '{print $5}')
        SOURCE_SIZE=$(ls -l "$SOURCE" | awk '{print $5}')
        
        print_yellow "✓ $BINARY_NAME already installed"
        print_yellow "  Current: $LOCAL_SIZE bytes"
        print_yellow "  New: $SOURCE_SIZE bytes"
        
        printf "Overwrite? [y/N]: "
        read answer
        case "$answer" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi
    
    print_blue "Installing: $BINARY_NAME"
    
    # Copy binary
    cp "$SOURCE" "$DEST"
    chmod +x "$DEST"
    
    # Create symlink
    if [ -L "/usr/bin/$BINARY_NAME" ]; then
        rm -f "/usr/bin/$BINARY_NAME"
    fi
    ln -sf "$DEST" "/usr/bin/$BINARY_NAME" 2>/dev/null
    
    SIZE=$(ls -l "$DEST" | awk '{print $5}')
    print_green "✓ $BINARY_NAME installed ($SIZE bytes)"
}

# ---------- Install All Binaries ----------
install_all_binaries() {
    SOURCE_DIR="$TEMP_DIR/$BINARY_PATH"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        print_red "Source directory not found!"
        return 1
    fi
    
    for bin in $BINARIES; do
        echo ""
        install_binary "$bin"
    done
}

# ---------- Special Handling for BusyBox ----------
handle_busybox() {
    if binary_exists "busybox"; then
        print_yellow "✓ BusyBox already installed"
        printf "Reinstall? [y/N]: "
        read answer
        case "$answer" in
            [Yy]*) ;;
            *) return 0 ;;
        esac
    fi
    
    # Backup original busybox
    BUSYBOX_PATH=$(which busybox 2>/dev/null)
    if [ -n "$BUSYBOX_PATH" ] && [ -f "$BUSYBOX_PATH" ] && [ ! -L "$BUSYBOX_PATH" ]; then
        print_yellow "Backing up original: $BUSYBOX_PATH → ${BUSYBOX_PATH}.backup"
        mv "$BUSYBOX_PATH" "${BUSYBOX_PATH}.backup"
    fi
    
    install_binary "busybox"
    
    print_green "✓ BusyBox ready!"
    "$DATA_DIR/busybox" --help | head -2
}

# ---------- Cleanup ----------
cleanup() {
    print_yellow "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    print_green "✓ Cleanup complete!"
}

# ---------- Show Menu ----------
show_menu() {
    clear
    echo "============================================"
    echo "  BINARY INSTALLER v3.0 - ZIP EDITION"
    echo "         OpenWrt / BusyBox"
    echo "============================================"
    
    i=1
    INSTALLED_COUNT=0
    TOTAL_COUNT=0
    
    for f in $BINARIES; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if binary_exists "$f"; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            STATUS="${GREEN}[✓]${NC}"
        else
            STATUS="${RED}[ ]${NC}"
        fi
        printf "  %2d) %-15s %b\n" "$i" "$f" "$STATUS"
        i=$((i+1))
    done
    
    echo "--------------------------------------------"
    printf "  %2d) %-15s\n" "$i" "Install ALL"
    i=$((i+1))
    printf "  %2d) %-15s\n" "$i" "Clean & Exit"
    echo "  0) Exit"
    echo "============================================"
    printf "Installed: ${GREEN}$INSTALLED_COUNT${NC}/$TOTAL_COUNT\n"
    printf "Source: ZIP (local)\n"
    echo "============================================"
    printf "Your choice [0-$i]: "
    read choice

    case "$choice" in
        0) 
            cleanup
            print_green "Goodbye!"
            exit 0 
            ;;
        $((TOTAL_COUNT+1))) 
            install_all_binaries 
            ;;
        $((TOTAL_COUNT+2))) 
            cleanup
            exit 0
            ;;
        *)
            if [ "$choice" -ge 1 ] && [ "$choice" -le "$TOTAL_COUNT" ]; then
                j=1
                for f in $BINARIES; do
                    if [ "$j" -eq "$choice" ]; then
                        if [ "$f" = "busybox" ]; then
                            handle_busybox
                        else
                            install_binary "$f"
                        fi
                        break
                    fi
                    j=$((j+1))
                done
            else
                print_red "Invalid choice!"
            fi
            ;;
    esac
}

# ---------- Main ----------
main() {
    check_root
    create_dirs
    
    print_blue "Step 1/3: Downloading ZIP..."
    download_zip || exit 1
    
    print_blue "Step 2/3: Extracting ZIP..."
    extract_zip || exit 1
    
    print_blue "Step 3/3: Listing binaries..."
    list_binaries || exit 1
    
    echo ""
    print_green "✓ Repository loaded successfully!"
    print_yellow "You can now install binaries from local ZIP"
    echo ""
    
    while true; do
        show_menu
        echo ""
        print_yellow "Press Enter to continue..."
        read dummy
    done
}

# Start
main
