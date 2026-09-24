# Together Banking App

**A shared view of your finances, without connecting your bank accounts.**

Together is a native iPhone app for you and your family to track expenses, organize bank statements, and understand credit card debt. Upload a statement, review the suggested transactions and categories, and keep your household’s information in one place.

The interface offers **Dark charcoal, Mint, and Lavender** themes. Each family member can choose their own theme on their phone.

## What you can do

| Section | What it’s for |
| --- | --- |
| **Overview** | See monthly spending, spending categories, total card balances, recent activity, and charges worth reviewing. |
| **Activity** | Search transactions, filter recurring or unusual charges, change categories, correct details, and mark a charge reviewed. |
| **Cards** | Track each card’s statement balance, credit limit, utilization, minimum payment, and due date. |
| **Statements** | Upload PDF, CSV, or text statements and view the saved originals. Scanned PDFs use on-device text recognition. |
| **Household** | Manage family members, enable app locking, and sync your shared information. |
| **Settings** | Tap the upper-right gear on any main tab to change your color theme. |

No bank credentials, automatic bank connections, analytics service, or external document-reading service are used. Parsing and category suggestions happen on your iPhone.

## Run the app

You need a Mac with Xcode and an iOS simulator, or an iPhone running **iOS 18 or later**. Use an Xcode version with a compatible iOS SDK and simulator runtime.

1. Open `Together.xcodeproj` from this repository.
2. Select the **Together** scheme.
3. Choose an iPhone simulator as the run destination. If you need an iPhone 15, add one through Xcode’s device manager using an installed compatible iOS runtime.
4. Click **Run** or press **⌘R**. In Xcode 27, the simulator screen appears in [Device Hub](https://developer.apple.com/documentation/xcode/device-hub).

CloudKit is controlled by the `CLOUDKIT_ENABLED` build setting; use `NO` for a local-only build. Installing on physical phones requires app signing; sharing also requires the CloudKit setup below. No third-party packages are needed.

## Use Together

### 1. Add your household information

Together starts with an empty household. Add your cards and import your statements to populate Overview and Activity. Existing saved records remain available when you update the app.

If you will join a family member’s household, accept their invitation before importing your own documents. Existing local records merge into the household you join.

### 2. Add your credit cards

Open **Cards → Add a credit card** and enter:

- A recognizable nickname, such as “Travel card.”
- The last four digits only.
- The balance and credit limit from your statement.
- The minimum payment and payment due date.

Tap **Save**. Tap a saved card whenever you need to update these details. The app does not need a full card number, security code, or bank password.

Card balances are statement snapshots. Importing purchases does not automatically add them to the card’s balance. An import for a saved card can suggest a replacement statement balance; you must check it during review. Limits, minimum payments, and due dates are maintained in the card details screen.

### 3. Upload and review a statement

1. Tap **Upload a statement** on Overview or Statements.
2. Enter the account nickname or select a saved card. Use the same nickname for later statements from that account.
3. Set the statement year. This fills in dates that omit a year.
4. Choose a PDF, CSV, or text document from Files.
5. Review the extracted merchants, dates, amounts, and categories. Edit mistakes and swipe to remove unwanted rows.
6. Use **Reverse all amount signs** if your export uses negative values for spending. Together expects positive expenses and negative payments, refunds, and income.
7. For a saved card, check any suggested statement balance before allowing it to replace your saved balance.
8. Turn on **I checked these against my statement**, then tap **Import**.

The original document is saved under Statements. If cloud sharing is enabled, that original is included in the shared household too.

Try the included [example statement](Samples/example-statement.csv) first. Its CSV format is:

```csv
Date,Description,Amount
2026-09-04,"Whole Foods, Market",86.42
2026-09-05,Netflix,15.49
2026-09-06,Payment received,-200.00
```

CSV columns must be **Date, Description, Amount**, in that order. A header is optional. Supported full dates include `YYYY-MM-DD` and `MM/DD/YYYY`. Quote descriptions containing commas.

**Import limits:** Files can be up to 15 MB; PDF reading covers the first 50 pages. PDF recognition expects a numeric date, description, and trailing decimal amount on a transaction line. Complex columns, multiline descriptions, and some scanned layouts may require corrections or a CSV export. Review reports skipped lines, which can include both headings and missed transactions. Compare the results with the complete statement, especially around New Year or when a PDF contains more than 50 pages.

### 4. Review your spending

Use **Activity** to search merchants or categories. Select **Recurring** for charges with similar amounts at weekly, monthly, or yearly intervals. Select **To review** for unusually large charges.

Tap a transaction to edit it or mark it reviewed. Recurring and unusual-charge labels are suggestions based on imported history; they do not establish that a charge is fraudulent or guarantee that every subscription is detected.

Matching transactions already saved for the same account are skipped during import. Avoid importing the same statement independently on both phones: concurrent imports can create duplicates with different internal IDs.

### 5. Choose a theme and enable app locking

Tap the upper-right **Settings gear** and choose **Dark charcoal**, **Mint**, or **Lavender**. The palette changes immediately and the choice is remembered on that phone.

Open **Household → Enable Face ID / passcode lock** to require device authentication. With locking enabled, Together shows its lock screen when it leaves the foreground. Enable locking separately on each phone and use an iPhone passcode.

## Connect iCloud and share with your family

Together uses **Apple CloudKit**. The owner’s household is stored in their private database, and invited family members access it through CloudKit’s shared database. The app does not put household records in a public database or require a separate server.

The person configuring the app needs an **Apple Developer Program membership** that supports CloudKit. Each family member needs their own Apple Account signed into iCloud and the correctly signed app; they do not need to purchase a developer membership. Apple’s [CloudKit sharing sample](https://github.com/apple/sample-cloudkit-sharing) describes the developer prerequisites and sharing model.

### Step 1: Configure signing and a CloudKit container

Configure signing and CloudKit once for the app. Everyone joining a household must use the same app and container. If using a different developer account, choose your own bundle and container identifiers:

1. In **Xcode → Settings → Accounts**, add your developer Apple Account.
2. Open the project, select the **Together target**, then **Signing & Capabilities**.
3. Select your developer **Team**, enable automatic signing, and set a unique bundle identifier, for example `com.yourname.togetherbanking`.
4. Add the **iCloud** capability and enable **CloudKit**.
5. Create or select a container belonging to your team, for example `iCloud.com.yourname.togetherbanking`.

Follow Apple’s [iCloud configuration guide](https://developer.apple.com/documentation/xcode/configuring-icloud-services) if Xcode reports a capability or provisioning problem.

### Step 2: Point Together at that container

Use exactly the same container identifier in both places:

| File | Change |
| --- | --- |
| `Together/Store.swift` | Replace `iCloud.com.aivxx.togetherbanking.mmp2r7x6fn` in `CKContainer(identifier:)`. |
| `Together/Cloud.entitlements` | Replace `iCloud.com.aivxx.togetherbanking.mmp2r7x6fn` in `com.apple.developer.icloud-container-identifiers`. |

Then set these values in the **Together target → Build Settings**:

| Setting | Value |
| --- | --- |
| **Code Signing Entitlements** (`CODE_SIGN_ENTITLEMENTS`) | `Together/Cloud.entitlements` |
| User-defined **`CLOUDKIT_ENABLED`** | `YES` |

Apply them to each configuration you install, including Debug for development and Release for distribution. Xcode may create another entitlements file when adding the capability; keep the capability configuration and the file used for signing consistent.

`Together/Info.plist` already maps `CloudKitEnabled` to `$(CLOUDKIT_ENABLED)` and declares `CKSharingSupported`. This checkout sets `CLOUDKIT_ENABLED = YES`. `CLOUDKIT_ENVIRONMENT` selects Development for Debug and Production for Release, and the entitlements file uses that value. Changing the enabled flag alone is insufficient without matching signed entitlements and a registered container.

CloudKit setup and container inspection are covered in Apple’s [Enabling CloudKit guide](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app).

### Step 3: Install the same configured app on both phones

1. Sign each iPhone into its owner’s Apple Account and enable iCloud access for Together if that setting is presented.
2. Install the same configured app on both phones through Xcode, or use TestFlight after completing Step 6.
3. Keep both installations on the same CloudKit environment. Development and production have separate data.
4. Enable Together’s app lock on each phone.

Start with non-sensitive sample records while verifying sharing. The simulator alone does not verify physical-device authentication or two-account sharing.

### Step 4: Invite family members

Apple Family Sharing and Together household sharing are separate. Together cannot automatically read your Apple Family roster or grant it access. Invite each family member explicitly through Apple’s private CloudKit sharing screen. Family members use their own Apple Accounts; you do not need to share a password.

**On the household owner’s phone:**

1. Open **Household → Family members**.
2. Tap **Add family member**.
3. In Apple’s sharing screen, choose the family member using the email or phone number associated with their Apple Account, then send the private invitation. Repeat for additional family members.
4. Return to **Family members** to see actual household participants and their **Invited** or **Joined** state. Apple may withhold a participant’s name; use **Manage invitations & access** for Apple’s full sharing controls.
5. Use **Household → Sync household** to share the latest saved information.

**On each invited family member’s phone:**

1. Install Together and sign into iCloud with their own Apple Account.
2. Open and accept the private invitation before importing statements.
3. Unlock Together if necessary and choose **Household → Sync household**.
4. Verify that the shared records appear. Members can open **Family members → Manage my access** to view their participation through Apple’s sharing controls.

Invited members can view and edit **all household transactions, card details, and original documents**. Membership in your Apple Family group alone neither grants nor revokes this access. Use the app’s sharing controls to manage it. See Apple’s [CloudKit sharing documentation](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users).

### Step 5: Check sharing in both directions

Change a test transaction’s category on a family member’s phone and sync it. Sync the owner’s phone and confirm the change appears. Repeat in the other direction before adding real statements.

Changes save locally first. To send and receive updates, use **Household → Sync household** or pull to refresh **Activity**. The app also requests a sync when it becomes active while unlocked. There is no continuous background or real-time sync; after editing, manually sync both phones when you need an immediate shared view.

Independent records merge by ID. For edits to the same transaction or card, the newer modification timestamp wins. Server change tags reject overlapping uploads; retry sync after a conflict. Avoid editing the same item simultaneously.

### Step 6: Prepare for TestFlight, if you use it

After testing with development builds, open [CloudKit Console](https://icloud.developer.apple.com/) and select your team and container. Confirm the development schema includes:

| Record type | App fields |
| --- | --- |
| `Household` | `title` — String |
| `HouseholdItem` | `kind` — String; `payload` — Asset |

A successful sync with sample data creates the app’s record types in development. Deploy the tested schema to production before distributing the app through TestFlight. Schema deployment does not copy your development household records; create or import the production household and send a new invitation from the production build. See Apple’s [schema deployment guide](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).

Install the production build on both phones. Do not mix one development installation with one TestFlight installation when verifying a shared household.

### Manage access

The owner can return to **Household → Family members → Manage invitations & access** to manage participants through Apple’s sharing screen. Removing access or stopping sharing does not erase records or documents already downloaded to another phone. This version does not automatically purge previously downloaded local data after access is revoked.

## Privacy and security boundaries

- **On-device reading:** Statement text extraction, OCR, and categorization run locally. There is no remote AI document-processing service.
- **Protected local files:** Saved household data and temporary upload files use iOS complete file protection. Physical-device passcodes and the app lock are important parts of the protection.
- **Private cloud access:** With CloudKit enabled, syncing uploads data to iCloud even before a family member is invited. Private invitations grant the invited participant access to the household; the app does not use CloudKit’s public database.
- **Account security:** Keep both Apple Accounts protected with two-factor authentication and invite only the intended family members.
- **Encryption scope:** Together relies on iOS and CloudKit protections. It does not implement or claim its own end-to-end encryption scheme. App locking does not add a separate encryption layer to shared cloud records.
- **Original statements:** The original documents can contain full account numbers, addresses, or other sensitive details even though card entry asks only for the last four digits. Consider that before importing and sharing them.
- **Repository hygiene:** Keep real statements, account data, signing credentials, and exported app data out of GitHub. The included sample CSV contains fictional transactions. The `.gitignore` excludes build outputs and Xcode user state, not arbitrary financial documents you manually add.

This is an initial implementation, not a security-audited financial service. It currently supports one household, USD display, and foreground syncing. It does not include automatic bank connections, currency conversion, payment reminders, synchronized record deletion, an account-switching workflow, or an in-app export/recovery workflow. Keep original statements outside the app.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| “iCloud sharing needs Apple developer setup” | The installed build must have `CLOUDKIT_ENABLED = YES`, matching container identifiers, and valid CloudKit signing entitlements. Rebuild and reinstall after configuration changes. |
| “Sign in to iCloud” | Check the Apple Account and iCloud availability on that phone. |
| Container, permission, or provisioning error | Confirm that the container belongs to the selected developer team and is enabled for the app’s identifier and signing profile. |
| Invitation opens but data is missing | Check that both phones use the same app container and CloudKit environment, the intended Apple Account accepted the invite, and both have synced while unlocked. |
| “Sync needs attention” | Read the displayed error, check connectivity and iCloud availability, and retry. After a simultaneous-edit conflict, sync again. |
| Works from Xcode but fails in TestFlight | Verify the production schema was deployed and both phones run production builds. |
| No transactions found | Try the example CSV. For your statement, use an unlocked PDF or export CSV with the supported column order. |
| Duplicate purchases | Use consistent account nicknames and have only one family member import each statement. Concurrent imports are not deduplicated across devices. |

## Build and validation

Run commands from this repository’s root.

Simulator build:

```sh
xcodebuild -project Together.xcodeproj -scheme Together \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /private/tmp/together-build \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
```

Core regression checks on macOS:

```sh
swiftc Together/Models.swift Together/StatementParser.swift Tests/main.swift \
  -module-cache-path /private/tmp/together-swift-cache \
  -o /private/tmp/together-tests
/private/tmp/together-tests
```

A developer-only CloudKit integration check is available in Debug builds. Launch with `--verify-cloudkit` after signing into iCloud. It ensures the private zone and root exist, creates a synthetic `HouseholdItem`, verifies its uploaded asset, and removes the test item. The outcome is saved as `Library/Application Support/cloudkit-setup-result.txt` inside the app’s sandbox. The check does not use your household records and is excluded from Release builds. A successful run verifies basic CloudKit access and creates the development schema; it does not verify a family invitation.

The core checks cover CSV parsing, categorization, PDF-style transaction lines, amount signs, invalid inputs, recurring and unusual charges, statement-balance extraction, and serialization. Test live CloudKit invitations with separate Apple Accounts and Face ID on physical devices as well.

## Repository layout

```text
Together.xcodeproj/   Xcode project and shared scheme
Together/            SwiftUI screens, data model, parsing, storage, and CloudKit
Samples/             Fictional example statement
Tests/               Core regression checks
Screenshots/         App preview image
README.md            Usage and setup guide
```
