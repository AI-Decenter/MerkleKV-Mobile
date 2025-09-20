# So sánh kích thước file IPA thực vs simulation

## File IPA Simulation (4KB) - Current
```
MerkleKV-Mobile-v1.0.0-1.ipa (4.3KB)
├── Payload/Runner.app/
│   ├── Info.plist (2KB - XML metadata)
│   ├── Runner (100 bytes - text file thay vì binary)
│   ├── Frameworks/
│   │   ├── Flutter.framework/Flutter (50 bytes - text)
│   │   └── App.framework/App (50 bytes - text)
│   └── flutter_assets/
│       ├── AssetManifest.json (200 bytes)
│       ├── FontManifest.json (150 bytes)
│       └── kernel_blob.bin (50 bytes - text)
```

## File IPA thực sự (40-90MB+) sẽ chứa:
```
MerkleKV-Mobile-v1.0.0-1.ipa (40-90MB+)
├── Payload/Runner.app/
│   ├── Info.plist (2KB)
│   ├── Runner (15-25MB - ARM64 executable binary)
│   ├── Frameworks/
│   │   ├── Flutter.framework/
│   │   │   ├── Flutter (20-30MB - Flutter engine binary)
│   │   │   ├── icudtl.dat (10MB - Unicode data)
│   │   │   └── Info.plist
│   │   ├── App.framework/
│   │   │   ├── App (5-15MB - Compiled Dart code)
│   │   │   └── flutter_assets/ (1-10MB)
│   │   └── Third-party frameworks (ReachabilitySwift, etc.)
│   ├── flutter_assets/
│   │   ├── kernel_blob.bin (1-5MB - Compiled Dart kernel)
│   │   ├── vm_snapshot_data (2-8MB - Dart VM snapshot)
│   │   ├── isolate_snapshot_data (1-3MB - Isolate snapshot)
│   │   ├── packages/ (fonts, cupertino icons, etc.)
│   │   ├── assets/ (images, icons, files - tùy app)
│   │   └── AssetManifest.json
│   ├── Base.lproj/ (storyboards, xibs)
│   ├── Assets.car (app icons, launch screens - 1-5MB)
│   └── embedded.mobileprovision (provisioning profile)
```

## Breakdown kích thước file IPA thực:

### Core Components (bắt buộc):
- **Flutter Engine Binary**: 20-30MB
- **Dart VM Snapshots**: 3-10MB  
- **Compiled App Code**: 5-15MB
- **ICU Data**: 10MB
- **App Executable**: 15-25MB

### Assets & Resources:
- **App Icons & Launch Screens**: 1-5MB
- **Fonts**: 1-3MB (CupertinoIcons, custom fonts)
- **Images/Graphics**: 5-50MB (tùy app)
- **Other Assets**: 1-10MB

### Dependencies:
- **Native iOS Frameworks**: 1-10MB
- **Third-party Libraries**: 1-20MB
- **Pods Dependencies**: 1-15MB

## Tại sao APK Android 90MB?
APK thường lớn hơn IPA vì:
- **Multiple architectures**: arm64-v8a, armeabi-v7a, x86, x86_64
- **Larger asset bundling**: Android bao gồm nhiều density assets
- **Different compression**: APK compression khác với IPA
- **Additional Android resources**: Manifest, resources.arsc, etc.
```