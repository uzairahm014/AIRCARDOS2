# Build the IPA from Windows — step by step

You need: this zip, a GitHub account, and a browser. **No Mac required.**

Total time: ~15 minutes, most of it waiting for the build.

---

## What you are doing

```
your Windows PC  →  GitHub  →  Codemagic (rents a Mac)  →  AirCard-iOS.ipa
                                                                   ↓
                                                          you sideload it
```

An IPA cannot be made on Windows because Apple only ships its compiler and
iOS SDK for macOS. So we borrow a Mac for a few minutes.

---

## Step 1 — Unzip

Right-click `AirCard-iOS-ipa-source.zip` → **Extract All**.

You'll get a folder called `AirCard-iOS` containing another `AirCard-iOS`
folder. Open the **inner** one — it must contain `codemagic.yaml`.

## Step 2 — Create the GitHub repo

1. Go to [github.com/new](https://github.com/new)
2. Repository name: `AirCard-iOS`
3. Visibility: **Private** (recommended — it contains your binary)
4. Tick **"Add a README file"**
5. Click **Create repository**

## Step 3 — Upload the files

On the repo page: **uploading files** → drag the *inner* `AirCard-iOS` folder in.

Or, if you have Git installed:

```bash
cd AirCard-iOS
git init
git add .
git commit -m "AirCard iOS source"
git branch -M main
git remote add origin https://github.com/YOURNAME/AirCard-iOS.git
git push -u origin main
```

> **Note:** `AirliftFFI.xcframework` is ~127 MB of static libraries. GitHub
> allows files up to 100 MB, and this folder is *under* that, so it should
> upload. If Git complains, see "If the upload fails" at the bottom.

## Step 4 — Start the cloud build

1. Go to [codemagic.io](https://codemagic.io) → **Sign up**
2. Choose **Sign in with GitHub**
3. Authorise Codemagic to see your repos
4. Click **Add new application** → select `AirCard-iOS`
5. Codemagic detects `codemagic.yaml` automatically — nothing to configure
6. Click **Start new build**

The first build takes ~10–15 minutes. Xcode is preinstalled; it installs
`xcodegen` and runs `xcodebuild`.

## Step 5 — Download the IPA

When the build finishes (green tick):

1. Open the build
2. Go to the **Artifacts** tab
3. Download `AirCard-iOS.ipa`

## Step 6 — Put it on your iPhone

That's the part you said you'd handle. Use **Sideloadly** or **AltStore** —
both run on Windows.

```
Codemagic → AirCard-iOS.ipa → Sideloadly (Windows) → your iPhone
```

Free Apple ID = 7-day expiry, re-install weekly. That's Apple's rule, not a
limit in the app.

---

## Expected first-build problems

**None of this Swift has ever been compiled.** The build will likely fail with
ordinary compile errors. That is the single most likely outcome, and it is not
a sign of a broken package.

If the log shows a red X:

1. Open the build → **Raw log**
2. Find the first `error:` line
3. Paste it back to me and I'll fix it

The build is then just a git push away from succeeding. That's the workflow:
fail → paste error → I fix → push → build again.

## If the upload fails

`AirliftFFI.xcframework` is the likely culprit (127 MB). Options:

1. **Use Git LFS** — free, and Codemagic pulls LFS automatically.
2. **Build the Rust core in the cloud instead** — uncomment the
   `AirliftFFI.xcframework/` line in `.gitignore`, then add this step to
   `codemagic.yaml` before the build:

   ```yaml
   - name: build rust core
     script: ./build-ios.sh Release
   ```

   This needs `rustup` with the iOS targets on Codemagic's image, which is
   why it is the fallback rather than the default.

## Which Xcode version

`codemagic.yaml` pins **Xcode 16.2**. If Codemagic has retired it, change
`xcode_version` and the `xcode-select` path to whatever they list — those are
the two places it appears.