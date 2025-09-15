#!/bin/bash

# Enhanced Android Emulator Setup Script
# Provides reliable Android emulator setup for CI/CD and local development

set -e

# Configuration variables
DEFAULT_API_LEVEL=33
DEFAULT_TARGET="google_apis"
DEFAULT_ARCH="x86_64"
DEFAULT_DEVICE="pixel_5"
DEFAULT_RAM=3072
DEFAULT_DISK=4096

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Enhanced Android Emulator Setup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -a, --api-level LEVEL     Android API level (default: $DEFAULT_API_LEVEL)
    -t, --target TARGET       System image target (default: $DEFAULT_TARGET)
    -r, --arch ARCH          CPU architecture (default: $DEFAULT_ARCH)
    -d, --device DEVICE      Device profile (default: $DEFAULT_DEVICE)
    -m, --memory RAM         RAM size in MB (default: $DEFAULT_RAM)
    -s, --disk-size SIZE     Disk size in MB (default: $DEFAULT_DISK)
    -n, --name NAME          AVD name (auto-generated if not provided)
    -f, --force              Force recreation of existing AVD
    -c, --ci-mode            Optimize for CI/CD environment
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message

EXAMPLES:
    # Create default emulator
    $0

    # Create emulator with specific API level
    $0 --api-level 29

    # Create emulator optimized for CI
    $0 --ci-mode --api-level 33

    # Create custom emulator configuration
    $0 --api-level 28 --target default --memory 4096 --device pixel_6

SUPPORTED DEVICES:
    pixel, pixel_xl, pixel_2, pixel_2_xl, pixel_3, pixel_3_xl,
    pixel_4, pixel_4_xl, pixel_5, pixel_6, pixel_6_pro, pixel_7

SUPPORTED TARGETS:
    default, google_apis, google_apis_playstore
EOF
}

# Parse command line arguments
parse_arguments() {
    API_LEVEL=$DEFAULT_API_LEVEL
    TARGET=$DEFAULT_TARGET
    ARCH=$DEFAULT_ARCH
    DEVICE=$DEFAULT_DEVICE
    RAM=$DEFAULT_RAM
    DISK=$DEFAULT_DISK
    AVD_NAME=""
    FORCE=false
    CI_MODE=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--api-level)
                API_LEVEL="$2"
                shift 2
                ;;
            -t|--target)
                TARGET="$2"
                shift 2
                ;;
            -r|--arch)
                ARCH="$2"
                shift 2
                ;;
            -d|--device)
                DEVICE="$2"
                shift 2
                ;;
            -m|--memory)
                RAM="$2"
                shift 2
                ;;
            -s|--disk-size)
                DISK="$2"
                shift 2
                ;;
            -n|--name)
                AVD_NAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -c|--ci-mode)
                CI_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Auto-generate AVD name if not provided
    if [[ -z "$AVD_NAME" ]]; then
        AVD_NAME="test_avd_${API_LEVEL}_${TARGET}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Android SDK is installed
    if [[ -z "$ANDROID_HOME" ]]; then
        log_error "ANDROID_HOME environment variable not set"
        log_info "Please install Android SDK and set ANDROID_HOME"
        exit 1
    fi

    # Check if sdkmanager exists
    SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
    if [[ ! -f "$SDKMANAGER" ]]; then
        # Try alternative path
        SDKMANAGER="$ANDROID_HOME/tools/bin/sdkmanager"
        if [[ ! -f "$SDKMANAGER" ]]; then
            log_error "sdkmanager not found in $ANDROID_HOME"
            log_info "Please ensure Android SDK command-line tools are installed"
            exit 1
        fi
    fi

    # Check if avdmanager exists
    AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
    if [[ ! -f "$AVDMANAGER" ]]; then
        AVDMANAGER="$ANDROID_HOME/tools/bin/avdmanager"
        if [[ ! -f "$AVDMANAGER" ]]; then
            log_error "avdmanager not found in $ANDROID_HOME"
            exit 1
        fi
    fi

    # Check if emulator exists
    EMULATOR="$ANDROID_HOME/emulator/emulator"
    if [[ ! -f "$EMULATOR" ]]; then
        log_error "Android emulator not found in $ANDROID_HOME/emulator"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Install required SDK components
install_sdk_components() {
    log_info "Installing required SDK components..."

    # Accept licenses
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

    # System image package name
    SYSTEM_IMAGE="system-images;android-${API_LEVEL};${TARGET};${ARCH}"
    
    # List of required packages
    PACKAGES=(
        "$SYSTEM_IMAGE"
        "platforms;android-${API_LEVEL}"
        "build-tools;34.0.0"
        "emulator"
        "platform-tools"
    )

    # Install packages
    for package in "${PACKAGES[@]}"; do
        log_info "Installing $package..."
        if [[ "$VERBOSE" == "true" ]]; then
            "$SDKMANAGER" "$package"
        else
            "$SDKMANAGER" "$package" >/dev/null 2>&1
        fi
    done

    log_success "SDK components installed successfully"
}

# Create AVD
create_avd() {
    log_info "Creating AVD: $AVD_NAME"

    # Check if AVD already exists
    if "$AVDMANAGER" list avd | grep -q "Name: $AVD_NAME"; then
        if [[ "$FORCE" == "true" ]]; then
            log_warning "AVD $AVD_NAME already exists, removing..."
            "$AVDMANAGER" delete avd -n "$AVD_NAME"
        else
            log_warning "AVD $AVD_NAME already exists. Use --force to recreate."
            return 0
        fi
    fi

    # System image package
    SYSTEM_IMAGE="system-images;android-${API_LEVEL};${TARGET};${ARCH}"

    # Create AVD
    log_info "Creating AVD with configuration:"
    log_info "  Name: $AVD_NAME"
    log_info "  API Level: $API_LEVEL"
    log_info "  Target: $TARGET"
    log_info "  Architecture: $ARCH"
    log_info "  Device: $DEVICE"
    log_info "  RAM: ${RAM}MB"
    log_info "  Disk: ${DISK}MB"

    if [[ "$VERBOSE" == "true" ]]; then
        echo no | "$AVDMANAGER" create avd \
            --force \
            --name "$AVD_NAME" \
            --abi "$TARGET/$ARCH" \
            --package "$SYSTEM_IMAGE" \
            --device "$DEVICE"
    else
        echo no | "$AVDMANAGER" create avd \
            --force \
            --name "$AVD_NAME" \
            --abi "$TARGET/$ARCH" \
            --package "$SYSTEM_IMAGE" \
            --device "$DEVICE" >/dev/null 2>&1
    fi

    log_success "AVD created successfully"
}

# Configure AVD for optimal performance
configure_avd() {
    log_info "Configuring AVD for optimal performance..."

    AVD_CONFIG_PATH="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"

    if [[ ! -f "$AVD_CONFIG_PATH" ]]; then
        log_error "AVD config file not found: $AVD_CONFIG_PATH"
        exit 1
    fi

    # Base configuration
    cat >> "$AVD_CONFIG_PATH" << EOF

# Enhanced configuration for testing
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.ramSize=$RAM
disk.dataPartition.size=${DISK}M
hw.keyboard=yes
hw.cpu.ncore=2
hw.lcd.density=420
showDeviceFrame=no
EOF

    # CI-specific optimizations
    if [[ "$CI_MODE" == "true" ]]; then
        cat >> "$AVD_CONFIG_PATH" << EOF

# CI optimizations
hw.audioInput=no
hw.audioOutput=no
hw.camera.back=none
hw.camera.front=none
hw.gps=no
hw.sensors.orientation=no
hw.sensors.proximity=no
hw.dPad=no
hw.trackBall=no
hw.bluetooth=no
hw.wifi=yes
vm.heapSize=256
EOF
    fi

    log_success "AVD configuration completed"
}

# Test AVD
test_avd() {
    log_info "Testing AVD: $AVD_NAME"

    # Start emulator in background
    log_info "Starting emulator..."
    "$EMULATOR" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &
    EMULATOR_PID=$!

    # Wait for emulator to start
    log_info "Waiting for emulator to start..."
    adb wait-for-device

    # Wait for boot completion
    log_info "Waiting for boot completion..."
    while true; do
        boot_completed=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
        if [[ "$boot_completed" == "1" ]]; then
            break
        fi
        sleep 2
    done

    # Verify emulator is working
    log_info "Verifying emulator functionality..."
    ANDROID_VERSION=$(adb shell getprop ro.build.version.release | tr -d '\r\n')
    API_LEVEL_ACTUAL=$(adb shell getprop ro.build.version.sdk | tr -d '\r\n')

    log_success "Emulator is running successfully"
    log_info "  Android Version: $ANDROID_VERSION"
    log_info "  API Level: $API_LEVEL_ACTUAL"

    # Stop emulator
    log_info "Stopping emulator..."
    adb emu kill
    wait $EMULATOR_PID 2>/dev/null || true

    log_success "AVD test completed successfully"
}

# List available AVDs
list_avds() {
    log_info "Available AVDs:"
    "$AVDMANAGER" list avd
}

# Main function
main() {
    echo "🤖 Enhanced Android Emulator Setup Script"
    echo "=========================================="

    parse_arguments "$@"
    check_prerequisites
    install_sdk_components
    create_avd
    configure_avd

    if [[ "$CI_MODE" != "true" ]]; then
        test_avd
    fi

    log_success "Android emulator setup completed successfully!"
    log_info "AVD Name: $AVD_NAME"
    log_info "To start the emulator manually:"
    log_info "  $EMULATOR -avd $AVD_NAME"
    
    echo ""
    log_info "Available AVDs:"
    list_avds
}

# Run main function
main "$@"