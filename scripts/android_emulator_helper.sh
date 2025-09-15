#!/bin/bash

# Android Emulator CI Helper Script
# Provides enhanced device management for CI/CD environments

set -e

# Configuration
MAX_BOOT_WAIT=300  # 5 minutes max wait
HEALTH_CHECK_INTERVAL=5
ADB_TIMEOUT=30

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Enhanced device wait function
wait_for_device() {
    log_info "Waiting for Android device to be ready..."
    
    # Basic device detection
    timeout $ADB_TIMEOUT adb wait-for-device || {
        log_error "Device detection timeout after ${ADB_TIMEOUT}s"
        return 1
    }
    
    log_success "Device detected"
    
    # Wait for boot completion with timeout
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $MAX_BOOT_WAIT ]]; then
            log_error "Boot timeout after ${MAX_BOOT_WAIT}s"
            return 1
        fi
        
        local boot_completed=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
        if [[ "$boot_completed" == "1" ]]; then
            log_success "Device boot completed in ${elapsed}s"
            break
        fi
        
        log_info "Boot progress... (${elapsed}s elapsed)"
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    # Additional readiness checks
    check_device_readiness
}

# Comprehensive device readiness check
check_device_readiness() {
    log_info "Performing comprehensive device readiness check..."
    
    # Check package manager
    local pm_ready=false
    for i in {1..10}; do
        if adb shell pm list packages >/dev/null 2>&1; then
            pm_ready=true
            break
        fi
        log_info "Waiting for package manager... (attempt $i/10)"
        sleep 2
    done
    
    if [[ "$pm_ready" != "true" ]]; then
        log_error "Package manager not ready"
        return 1
    fi
    
    # Check launcher readiness
    local launcher_ready=false
    for i in {1..20}; do
        local launcher_count=$(adb shell dumpsys window windows 2>/dev/null | grep -c "mCurrentFocus.*Launcher" || echo "0")
        if [[ "$launcher_count" -gt 0 ]]; then
            launcher_ready=true
            break
        fi
        log_info "Waiting for launcher... (attempt $i/20)"
        sleep 2
    done
    
    if [[ "$launcher_ready" != "true" ]]; then
        log_warning "Launcher not detected, but continuing..."
    fi
    
    # Check activity manager
    if ! adb shell am list-options >/dev/null 2>&1; then
        log_error "Activity manager not responsive"
        return 1
    fi
    
    log_success "Device readiness check passed"
}

# Configure device for testing
configure_device() {
    log_info "Configuring device for testing..."
    
    # Disable animations
    adb shell settings put global window_animation_scale 0.0
    adb shell settings put global transition_animation_scale 0.0
    adb shell settings put global animator_duration_scale 0.0
    
    # Disable screen lock and keyguard
    adb shell settings put secure show_ime_with_hard_keyboard 0
    adb shell settings put system screen_off_timeout 1800000  # 30 minutes
    
    # Wake up and unlock device
    adb shell input keyevent KEYCODE_WAKEUP
    adb shell input keyevent KEYCODE_MENU
    adb shell input swipe 200 500 200 100  # Swipe up to unlock
    
    # Set optimal settings for testing
    adb shell settings put global stay_on_while_plugged_in 3  # Stay awake while charging
    adb shell settings put system accelerometer_rotation 0  # Disable auto-rotate
    
    log_success "Device configuration completed"
}

# Collect device information
collect_device_info() {
    log_info "Collecting device information..."
    
    echo "📱 Device Information:"
    echo "===================="
    
    # Basic device info
    echo "Device ID: $(adb devices | grep -w device | head -1 | cut -f1)"
    echo "Android Version: $(adb shell getprop ro.build.version.release | tr -d '\r\n')"
    echo "API Level: $(adb shell getprop ro.build.version.sdk | tr -d '\r\n')"
    echo "CPU ABI: $(adb shell getprop ro.product.cpu.abi | tr -d '\r\n')"
    echo "Manufacturer: $(adb shell getprop ro.product.manufacturer | tr -d '\r\n')"
    echo "Model: $(adb shell getprop ro.product.model | tr -d '\r\n')"
    
    # Memory information
    echo ""
    echo "💾 Memory Information:"
    adb shell cat /proc/meminfo | head -3
    
    # Storage information
    echo ""
    echo "💽 Storage Information:"
    adb shell df /data | tail -1
    
    # Display information
    echo ""
    echo "🖥️ Display Information:"
    local display_info=$(adb shell dumpsys display | grep -A 3 "Display 0")
    echo "$display_info"
    
    echo ""
}

# Health check function
health_check() {
    log_info "Performing device health check..."
    
    # Check ADB connectivity
    if ! adb shell echo "test" >/dev/null 2>&1; then
        log_error "ADB connectivity failed"
        return 1
    fi
    
    # Check available memory
    local available_mem=$(adb shell cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
    if [[ -n "$available_mem" && "$available_mem" -lt 100000 ]]; then  # Less than 100MB
        log_warning "Low available memory: ${available_mem}KB"
    fi
    
    # Check system load
    local load_avg=$(adb shell cat /proc/loadavg | awk '{print $1}')
    log_info "System load average: $load_avg"
    
    # Check for ANRs or crashes
    local anr_count=$(adb shell dumpsys activity processes | grep -c "NOT RESPONDING" || echo "0")
    if [[ "$anr_count" -gt 0 ]]; then
        log_warning "Detected $anr_count ANR(s)"
    fi
    
    log_success "Device health check completed"
}

# Cleanup function
cleanup_device() {
    log_info "Cleaning up device state..."
    
    # Kill any running test apps
    adb shell am force-stop com.example.flutter_demo 2>/dev/null || true
    
    # Clear logcat buffer
    adb logcat -c 2>/dev/null || true
    
    # Clear temporary files
    adb shell rm -rf /data/local/tmp/test_* 2>/dev/null || true
    
    log_success "Device cleanup completed"
}

# Troubleshooting function
troubleshoot() {
    log_warning "Running troubleshooting diagnostics..."
    
    echo "🔧 Troubleshooting Information:"
    echo "=============================="
    
    # ADB version and status
    echo "ADB Version:"
    adb version
    echo ""
    
    # Device list
    echo "Connected Devices:"
    adb devices -l
    echo ""
    
    # Emulator processes
    echo "Emulator Processes:"
    ps aux | grep emulator || echo "No emulator processes found"
    echo ""
    
    # System properties
    echo "Key System Properties:"
    adb shell getprop | grep -E "(ro.build|sys.boot|init.svc)" | head -10
    echo ""
    
    # Recent logcat entries
    echo "Recent Logcat (last 20 lines):"
    adb logcat -d -v time | tail -20 || echo "Unable to get logcat"
    echo ""
    
    # Memory and storage status
    echo "Memory Status:"
    adb shell dumpsys meminfo | head -10
    echo ""
    
    echo "Storage Status:"
    adb shell df | grep -E "(Filesystem|/data|/system)"
}

# Main command handler
case "${1:-setup}" in
    "wait")
        wait_for_device
        ;;
    "configure")
        configure_device
        ;;
    "info")
        collect_device_info
        ;;
    "health")
        health_check
        ;;
    "cleanup")
        cleanup_device
        ;;
    "troubleshoot")
        troubleshoot
        ;;
    "setup")
        wait_for_device
        configure_device
        collect_device_info
        health_check
        ;;
    *)
        echo "Usage: $0 {wait|configure|info|health|cleanup|troubleshoot|setup}"
        echo ""
        echo "Commands:"
        echo "  wait         - Wait for device to be ready"
        echo "  configure    - Configure device for testing"
        echo "  info         - Collect device information"
        echo "  health       - Perform health check"
        echo "  cleanup      - Clean up device state"
        echo "  troubleshoot - Run troubleshooting diagnostics"
        echo "  setup        - Run complete setup (wait + configure + info + health)"
        exit 1
        ;;
esac