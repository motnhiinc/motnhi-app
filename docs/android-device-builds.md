# Android builds delivered through Telegram

The `Android Device Build` GitHub Action builds a signed APK, creates a GitHub
prerelease, and sends a download link to your Telegram chat. No Firebase or Google
Play account is needed. GitHub Actions usage is subject to your account's included
minutes and billing settings; Telegram bot notifications have no service fee.

It runs on pushes to `main` that change Flutter source, assets, Android files,
dependencies, or the workflow itself. You can also run it manually from GitHub's
**Actions → Android Device Build → Run workflow**. Documentation-only pushes do
not trigger builds.

## 1. Create and back up an Android signing key

If you already have a release keystore for this app, reuse it instead. Otherwise,
run this on a trusted computer with Java installed (outside the repository):

```bash
keytool -genkeypair -v -keystore "$HOME/motnhi-release.jks" \
  -storetype JKS -alias motnhi -keyalg RSA -keysize 2048 -validity 10000
```

Keep the keystore and passwords in a secure backup. **Never commit them.** Future
updates must use the same key. A device with an older debug-signed build will
need that app uninstalled before installing this release-signed build, which
deletes its local data.

In the repository's **Settings → Secrets and variables → Actions**, create these
repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of your keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `motnhi`, or your existing key's alias |
| `ANDROID_KEY_PASSWORD` | Key password (possibly the same as the keystore password) |
| `TELEGRAM_BOT_TOKEN` | Bot token from the next step |
| `TELEGRAM_CHAT_ID` | Your private chat ID from the next step |

On macOS, copy the encoded keystore directly to the clipboard:

```bash
base64 -i "$HOME/motnhi-release.jks" | pbcopy
```

Paste it into `ANDROID_KEYSTORE_BASE64`. Treat that encoded value as a secret too.
Local Android builds still fall back to debug signing unless the
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD` environment variables are supplied.

## 2. Create your Telegram bot

1. Open the official **@BotFather** in Telegram and send `/newbot`.
2. Follow the prompts and save its token as `TELEGRAM_BOT_TOKEN`.
3. Open a private chat with your new bot and send `/start`.
4. On your trusted computer, call Telegram's `getUpdates` endpoint to find your
   chat ID. This prompts for the token without putting it in shell history:

   ```bash
   read -r -s TELEGRAM_BOT_TOKEN
   curl --silent --show-error "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
   unset TELEGRAM_BOT_TOKEN
   ```

5. In the JSON response, find your message's `message.chat.id`. Save that number
   as `TELEGRAM_CHAT_ID`. If the result is empty, send another message to the bot
   and repeat the request. Do not share the token or paste the response publicly.

The workflow sends a **link**, not the APK itself, so Telegram file-size limits
do not matter. For a private GitHub repository, sign in to GitHub on your phone
with an account that can access it. The bot does not make private builds public.

## 3. Run and install

1. Push the workflow and signing configuration to GitHub.
2. Add all six secrets, then manually run **Android Device Build** once.
3. When Telegram notifies you, open the release link in your Android browser.
4. Under **Assets**, download `motnhi-android.apk` and open it.
5. Allow **Install unknown apps** for that browser when Android asks, then install.

Later qualifying pushes to `main` repeat this automatically. You still tap to
install each update; this does not silently install apps. Delivery starts only
after the GitHub runner finishes building (normally several minutes, not instant).

Build numbers start at `10001` and increase with this workflow's run number.
Rerunning a run reuses its build number, but publishes a separate prerelease.
Do not switch back to the existing **Internal Android Release** workflow for
device updates: it still uses debug signing and the version in `pubspec.yaml`.
Changing workflow numbering or migrating to Play requires preserving increasing
version codes and the signing identity. Each run keeps a prerelease/APK; delete
obsolete releases periodically if needed to manage storage and clutter.

If a build fails, inspect its GitHub Actions logs. If only the Telegram step
fails, the APK is still available in GitHub Releases and the run summary. A build
failure does not send a success notification.
