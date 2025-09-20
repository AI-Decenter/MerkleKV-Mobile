# iOS Release Guide for MerkleKV Mobile

This guide provides comprehensive instructions for building and distributing iOS releases of the MerkleKV Mobile application.

## 🚀 Quick Start

### Automated GitHub Release
1. Go to the GitHub repository
2. Navigate to Actions tab
3. Select "iOS Release Build" workflow
4. Click "Run workflow"
5. Enter version, build number, and release notes
6. Download the IPA from the created release

### Manual Local Build
```bash
# Navigate to project root
cd MerkleKV-Mobile

# Run the build script with default settings
./scripts/build_ios_release.sh

# Or customize the build
./scripts/build_ios_release.sh -v 1.2.0 -b 42 -e production
```

## 📋 Prerequisites

### System Requirements
- **macOS** (required for iOS builds)
- **Xcode 15.0+** with iOS SDK
- **Flutter 3.16.0+**
- **CocoaPods** for dependency management
- **Git** for version control

### Setup Verification
```bash
# Check Flutter installation
flutter doctor

# Verify Xcode installation
xcodebuild -version

# Check CocoaPods
pod --version
```

## 🔧 Build Options

### GitHub Actions (Recommended)
The automated workflow provides:
- ✅ **Consistent environment** with proper tool versions
- ✅ **Automated release creation** with downloadable assets
- ✅ **Build artifacts** stored for 90 days
- ✅ **Release notes** and build information
- ✅ **Version management** with semantic versioning

### Manual Build Script
The local script offers:
- ✅ **Quick local builds** for testing
- ✅ **Customizable parameters** (version, build number, environment)
- ✅ **Detailed build information** generation
- ✅ **Clean build process** with dependency management

## 📱 Distribution Methods

### 1. App Store Distribution
```bash
# Build for App Store submission
./scripts/build_ios_release.sh -e production -v 1.0.0

# Upload via Xcode or Application Loader
# 1. Open Xcode
# 2. Window > Organizer
# 3. Upload to App Store Connect
```

### 2. Enterprise Distribution
```bash
# Build for enterprise distribution
./scripts/build_ios_release.sh -e enterprise -v 1.0.0

# Configure enterprise provisioning profile
# Distribute via MDM or direct download
```

### 3. Ad Hoc Distribution
```bash
# Build for testing on registered devices
./scripts/build_ios_release.sh -e staging -v 1.0.0-beta

# Install on test devices via Xcode or iTunes
```

### 4. Development Installation
```bash
# Install via Xcode Device Manager
xcrun devicectl device install app --device DEVICE_ID path/to/app.ipa

# Or drag and drop to device in Xcode Organizer
```

## ⚙️ Configuration Options

### Build Script Parameters
| Parameter | Short | Description | Default | Example |
|-----------|-------|-------------|---------|---------|
| `--version` | `-v` | Release version | `1.0.0` | `-v 2.1.0` |
| `--build` | `-b` | Build number | `1` | `-b 42` |
| `--environment` | `-e` | Build environment | `production` | `-e staging` |
| `--bundle-id` | `-i` | Bundle identifier | `com.merkle_kv.flutter_demo` | `-i com.myapp.demo` |
| `--app-name` | `-n` | App display name | `MerkleKV Mobile` | `-n "My App"` |

### Environment Configurations
- **`production`**: Optimized for App Store release
- **`staging`**: For internal testing with debug features
- **`enterprise`**: For enterprise distribution
- **`development`**: For development and testing

## 📦 Output Files

### Generated Assets
1. **IPA File**: `releases/MerkleKV-Mobile-vX.X.X-XXX.ipa`
   - Complete iOS app package
   - Ready for installation or distribution
   - Optimized for target environment

2. **Build Information**: `releases/build-info-vX.X.X-XXX.txt`
   - Detailed build metadata
   - Installation instructions
   - Technical specifications
   - Version and dependency information

### File Structure
```
releases/
├── MerkleKV-Mobile-v1.0.0-1.ipa
├── build-info-v1.0.0-1.txt
└── checksums.txt (if generated)
```

## 🔍 Verification Steps

### 1. Build Verification
```bash
# Check IPA structure
unzip -l releases/MerkleKV-Mobile-v1.0.0-1.ipa

# Verify app bundle
codesign -dv releases/MerkleKV-Mobile-v1.0.0-1.ipa
```

### 2. Installation Testing
```bash
# Install on simulator (for testing only)
xcrun simctl install booted releases/MerkleKV-Mobile-v1.0.0-1.ipa

# Install on device
xcrun devicectl device install app --device DEVICE_ID releases/MerkleKV-Mobile-v1.0.0-1.ipa
```

### 3. Functionality Testing
- ✅ **App launches** without crashes
- ✅ **Core features** work as expected
- ✅ **Network connectivity** functions properly
- ✅ **iOS lifecycle** handling works correctly
- ✅ **Performance** meets requirements

## 🚨 Troubleshooting

### Common Issues

#### Build Failures
```bash
# Clean everything and rebuild
flutter clean
rm -rf ios/Pods ios/.symlinks ios/Podfile.lock
flutter pub get
cd ios && pod install
```

#### Signing Issues
```bash
# Use automatic signing for development
# Or configure proper provisioning profiles
# Check Apple Developer account status
```

#### Dependency Conflicts
```bash
# Update Flutter and dependencies
flutter upgrade
flutter pub upgrade
cd ios && pod repo update && pod install
```

### Error Resolution
1. **Check Flutter doctor**: `flutter doctor -v`
2. **Verify Xcode setup**: `xcodebuild -checkFirstLaunchStatus`
3. **Update dependencies**: `flutter pub deps`
4. **Check iOS configuration**: Review `ios/Runner.xcodeproj`

## 📋 Quality Assurance

### Pre-Release Checklist
- [ ] **All E2E tests pass** (15/15 scenarios)
- [ ] **iOS lifecycle scenarios validated**
- [ ] **Network connectivity tested**
- [ ] **Performance benchmarks met**
- [ ] **Memory usage optimized**
- [ ] **Battery consumption acceptable**
- [ ] **App Store guidelines compliance**
- [ ] **Accessibility features working**

### Testing Matrix
| Device Type | iOS Version | Test Status |
|-------------|-------------|-------------|
| iPhone 15 Pro | iOS 17.0 | ✅ Tested |
| iPhone 14 | iOS 16.0 | ✅ Tested |
| iPhone 13 | iOS 15.0 | ✅ Tested |
| iPad Pro | iOS 17.0 | ✅ Tested |
| iPad Air | iOS 16.0 | ✅ Tested |

## 🔗 Resources

### Documentation
- [Flutter iOS Deployment](https://docs.flutter.dev/deployment/ios)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [App Store Connect Guide](https://developer.apple.com/app-store-connect/)
- [iOS App Distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)

### Tools
- [Xcode](https://developer.apple.com/xcode/) - iOS development environment
- [App Store Connect](https://appstoreconnect.apple.com/) - App distribution
- [TestFlight](https://developer.apple.com/testflight/) - Beta testing
- [CocoaPods](https://cocoapods.org/) - Dependency management

### Support
- **GitHub Issues**: Report bugs and request features
- **GitHub Discussions**: Community support and questions
- **Documentation**: In-repository guides and README files
- **CI/CD Logs**: Check GitHub Actions for build details

---

## 📝 Release Notes Template

```markdown
# MerkleKV Mobile v1.0.0

## 🚀 New Features
- Complete MerkleKV functionality implementation
- iOS lifecycle management with background execution
- Real-time network synchronization
- Comprehensive E2E testing framework

## 🔧 Improvements
- Optimized performance for iOS devices
- Enhanced memory management
- Improved battery efficiency
- Better error handling and recovery

## 🐛 Bug Fixes
- Fixed network connectivity edge cases
- Resolved iOS background execution issues
- Improved app lifecycle state management

## 📱 Technical Details
- **iOS Compatibility**: 12.0+
- **Architecture**: arm64
- **Bundle Size**: ~XX MB
- **Tested Scenarios**: 15/15 passed

## 📋 Installation
Download the IPA file and install via Xcode, iTunes, or enterprise distribution.
```

---

**Happy building! 🎉**

For questions or issues, please open a GitHub issue or check the repository documentation.