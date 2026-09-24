# TestFlight distribution

The project uses automatic signing for developer team `MMP2R7X6FN` and bundle ID `com.aivxx.togetherbanking.mmp2r7x6fn`. Release builds use the production CloudKit container. The app includes an opaque 1024×1024 icon, its UserDefaults required-reason privacy manifest, and an exempt-encryption declaration for its use of Apple platform encryption.

## Create the App Store Connect record once

In [App Store Connect → Apps](https://appstoreconnect.apple.com/apps), create an iOS app with the registered bundle ID above. Suggested name: **Together Banking**; primary language: **English (U.S.)**; SKU: `together-banking-ios`. The display name must be available. This app record is separate from the identifier registered in the developer portal.

## Archive and upload

Run from the repository root. The archive directory must be outside source control.

```sh
xcodebuild -project Together.xcodeproj -scheme Together \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/together-testflight/Together.xcarchive \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive \
  -archivePath /private/tmp/together-testflight/Together.xcarchive \
  -exportOptionsPlist Distribution/ExportOptions.plist \
  -exportPath /private/tmp/together-testflight/upload \
  -allowProvisioningUpdates
```

`ExportOptions.plist` uploads to App Store Connect, uses production CloudKit, and lets Xcode manage the uploaded build number. Uploading a build does not submit the app for public App Store release.

## Install with TestFlight

After Apple processes the upload, open the app’s **TestFlight** tab in App Store Connect. Create an internal testing group, add the processed build, and add your own App Store Connect user as a tester. Install Apple’s TestFlight app on your iPhone and accept the test invitation. See Apple’s [internal tester instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

For family members, use external testing unless they appropriately have access as App Store Connect users. External testing can require beta review and additional test information; see Apple’s [external tester instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers). Share privately with the intended tester rather than enabling a public invitation link.

All participating phones must use production builds and their own iCloud accounts. Start a production household and send a new household invitation; the development database and invitations do not transfer to production. Verify upload, category edits, and family synchronization in both directions before importing financial records.

The CloudKit production schema must be deployed before the TestFlight build can sync. Verify live production sync and invitations between separate Apple Accounts before distributing banking records.
