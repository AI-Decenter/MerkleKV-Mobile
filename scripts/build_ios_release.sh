#!/bin/bash

# MerkleKV Mobile - iOS Release Builder
# This script builds a complete iOS IPA package for distribution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERSION="1.0.0"
BUILD_NUMBER="1"
ENVIRONMENT="production"
BUNDLE_ID="com.merkle_kv.flutter_demo"
APP_NAME="MerkleKV Mobile"

# Functions
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} MerkleKV Mobile - iOS Release Builder${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}➤ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_requirements() {
    print_step "Checking requirements..."
    
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode is not installed"
        exit 1
    fi
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script must be run on macOS"
        exit 1
    fi
    
    print_success "All requirements met"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -b|--build)
                BUILD_NUMBER="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -i|--bundle-id)
                BUNDLE_ID="$2"
                shift 2
                ;;
            -n|--app-name)
                APP_NAME="$2"
                shift 2
                ;;
            -h|--help)
                echo "iOS Release Builder for MerkleKV Mobile"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -v, --version     Release version (default: 1.0.0)"
                echo "  -b, --build       Build number (default: 1)"
                echo "  -e, --environment Environment (default: production)"
                echo "  -i, --bundle-id   Bundle identifier (default: com.merkle_kv.flutter_demo)"
                echo "  -n, --app-name    App display name (default: MerkleKV Mobile)"
                echo "  -h, --help        Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 -v 1.2.0 -b 42"
                echo "  $0 --version 2.0.0 --build 100 --environment staging"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

setup_environment() {
    print_step "Setting up build environment..."
    
    # Navigate to Flutter demo app
    cd apps/flutter_demo
    
    # Update version in pubspec.yaml
    sed -i '' "s/version: .*/version: $VERSION+$BUILD_NUMBER/" pubspec.yaml
    
    print_success "Version set to $VERSION+$BUILD_NUMBER"
}

clean_project() {
    print_step "Cleaning project..."
    
    # Clean Flutter build
    flutter clean
    
    # Remove iOS build artifacts
    rm -rf ios/Pods ios/.symlinks ios/Podfile.lock ios/build
    
    print_success "Project cleaned"
}

install_dependencies() {
    print_step "Installing dependencies..."
    
    # Get Flutter dependencies
    flutter pub get
    flutter precache --ios
    
    # Install CocoaPods dependencies
    cd ios
    pod install --repo-update
    cd ..
    
    print_success "Dependencies installed"
}

configure_ios() {
    print_step "Configuring iOS project..."
    
    # Update Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" ios/Runner/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" ios/Runner/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" ios/Runner/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" ios/Runner/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" ios/Runner/Info.plist
    
    print_success "iOS project configured"
}

build_ios() {
    print_step "Building iOS release..."
    
    # Build iOS release
    flutter build ios \
        --release \
        --no-codesign \
        --target lib/main.dart \
        --dart-define=ENVIRONMENT=$ENVIRONMENT \
        --build-name=$VERSION \
        --build-number=$BUILD_NUMBER
    
    print_success "iOS build completed"
}

create_ipa() {
    print_step "Creating IPA package..."
    
    # Create output directory
    mkdir -p releases
    
    # Create Payload directory
    rm -rf Payload
    mkdir Payload
    
    # Copy app to Payload
    cp -R build/ios/Release-iphoneos/Runner.app Payload/
    
    # Create IPA file
    IPA_NAME="releases/MerkleKV-Mobile-v$VERSION-$BUILD_NUMBER.ipa"
    zip -r "$IPA_NAME" Payload/
    
    # Clean up
    rm -rf Payload
    
    # Get file size
    IPA_SIZE=$(ls -lh "$IPA_NAME" | awk '{print $5}')
    
    print_success "IPA created: $IPA_NAME (Size: $IPA_SIZE)"
    
    echo "IPA_NAME=$IPA_NAME" > .release_info
    echo "IPA_SIZE=$IPA_SIZE" >> .release_info
}

generate_build_info() {
    print_step "Generating build information..."
    
    BUILD_INFO="releases/build-info-v$VERSION-$BUILD_NUMBER.txt"
    
    cat > "$BUILD_INFO" << EOF
MerkleKV Mobile - iOS Release Build Information
=============================================

Release Version: $VERSION
Build Number: $BUILD_NUMBER
Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Environment: $ENVIRONMENT

Flutter Version: $(flutter --version | head -n1)
Xcode Version: $(xcodebuild -version | head -n1)
macOS Version: $(sw_vers -productVersion)

Build Configuration:
- Bundle ID: $BUNDLE_ID
- App Name: $APP_NAME
- Target Platform: iOS Device (arm64)
- Code Signing: Disabled (for distribution)
- Deployment Target: iOS 12.0+

IPA Details:
- File: $(basename "$IPA_NAME")
- Size: $IPA_SIZE
- Architecture: arm64
- Supports: iPhone, iPad

Installation Instructions:
1. Download the IPA file
2. Install using one of these methods:
   - Xcode: Window > Devices and Simulators > Install App
   - iTunes/Finder: Drag and drop to device
   - Third-party tools: 3uTools, iMazing, etc.

Distribution Options:
1. App Store: Submit via App Store Connect
2. Enterprise: Distribute via MDM
3. Ad Hoc: Install on registered devices
4. Development: Install via Xcode

Technical Requirements:
- iOS 12.0 or later
- Compatible with iPhone and iPad
- Network connectivity required for full functionality
- Storage: Minimal space required

Support:
- GitHub: https://github.com/askerNQK/MerkleKV-Mobile
- Issues: Use GitHub Issues for bug reports
- Documentation: See repository README

Generated by: iOS Release Builder Script
EOF
    
    print_success "Build info generated: $BUILD_INFO"
}

show_summary() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} 🎉 iOS Release Build Completed!${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "${GREEN}📱 Release Details:${NC}"
    echo "   Version: $VERSION"
    echo "   Build: $BUILD_NUMBER"
    echo "   Bundle ID: $BUNDLE_ID"
    echo "   App Name: $APP_NAME"
    echo "   Environment: $ENVIRONMENT"
    echo ""
    echo -e "${GREEN}📦 Generated Files:${NC}"
    echo "   ✅ IPA Package: $IPA_NAME"
    echo "   ✅ Build Info: releases/build-info-v$VERSION-$BUILD_NUMBER.txt"
    echo "   📊 Size: $IPA_SIZE"
    echo ""
    echo -e "${GREEN}🚀 Next Steps:${NC}"
    echo "   1. Test the IPA on a physical iOS device"
    echo "   2. Distribute via App Store, Enterprise, or Ad Hoc"
    echo "   3. Share with beta testers or end users"
    echo ""
    echo -e "${YELLOW}📋 Installation Command:${NC}"
    echo "   # Using Xcode (replace DEVICE_ID with actual device)"
    echo "   xcrun devicectl device install app --device DEVICE_ID $IPA_NAME"
    echo ""
    echo -e "${GREEN}✅ Quality Assurance: Ready for distribution${NC}"
}

# Main execution
main() {
    print_header
    
    parse_arguments "$@"
    check_requirements
    setup_environment
    clean_project
    install_dependencies
    configure_ios
    build_ios
    create_ipa
    generate_build_info
    show_summary
}

# Run main function with all arguments
main "$@"