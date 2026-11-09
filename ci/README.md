# GameNexus Project CI

This directory contains the project-local CI entry for GameNexus profile-bundle driven builds.

## Usage

```powershell
.\ci\run.cmd -ProfileBundle "towercar-local-test" -Platform "web-mobile" -Stage all
```

Run `ci\run.cmd` without arguments to enter manual input mode.

`run.cmd` keeps the window open after completion so local users can read the result.
Set `GAMENEXUS_CI_NO_PAUSE=1` when calling it from automation:

```cmd
set GAMENEXUS_CI_NO_PAUSE=1
ci\run.cmd -ProfileBundle "towercar-local-test" -Platform "web-mobile" -Stage all
```

Cocos Creator is resolved only from the versioned environment variable matching `profile.cocosCreatorVersion`. For Cocos Creator `2.4.11`, set:

```cmd
set COCOS_CREATOR_2_4_11=C:\ProgramData\cocos\editors\Creator\2.4.11\CocosCreator.exe
```

The value may point directly to `CocosCreator.exe` or to the directory that contains it.
If the variable is missing or points to a missing file, the build fails and asks the user to configure `COCOS_CREATOR_2_4_11`.

For local setup help, use the standalone search tool. It is not called by the packaging flow:

```cmd
ci\tools\find-cocos-creator.cmd
ci\tools\find-cocos-creator.cmd -AllDrives
ci\tools\find-cocos-creator.cmd -SetUser
```

The tool first checks fast sources: existing versioned environment variables, the Cocos Dashboard default directory, common install paths, and `PATH`. It detects all Cocos Creator versions it can identify and recommends matching variables such as `COCOS_CREATOR_2_4_11`. `-SetUser` writes all detected versioned variables for the current user. `-AllDrives` enables a slower full-drive scan.

`ProfileBundle` can be the name of a channel profile directory under `ci/profiles`; the runner resolves it automatically.
It can also be a full or relative directory path. The directory must contain `profile.json`.
`Platform` selects the current build target from the profile's `platforms` section.
For example:

```text
ci/profiles/towercar-local-test/profile.json
```

Jenkins can call `ci\pull-profile.cmd` before `ci\run.cmd`. The current implementation is a local placeholder: it resolves or copies an existing ProfileBundle and prints `PROFILE_BUNDLE=<absolute path>`. A future implementation can replace the script internals with a remote Profile service download without changing the Jenkins call shape.

```cmd
set GAMENEXUS_CI_NO_PAUSE=1
ci\pull-profile.cmd -ProfileBundle "towercar-local-test" -OutputDir "%WORKSPACE%\profile-bundle\%BUILD_TAG%"
ci\run.cmd -ProfileBundle "%WORKSPACE%\profile-bundle\%BUILD_TAG%" -Platform "web-mobile" -Stage all -BuildId "%BUILD_TAG%"
```

Jenkins should use one parameterized job instead of one job per platform. Pass the selected platform through the `PLATFORM` parameter:

```cmd
set GAMENEXUS_CI_NO_PAUSE=1
ci\pull-profile.cmd -ProfileBundle "%PROFILE_BUNDLE%" -OutputDir "%WORKSPACE%\profile-bundle\%BUILD_TAG%" -Platform "%PLATFORM%"
ci\run.cmd -ProfileBundle "%WORKSPACE%\profile-bundle\%BUILD_TAG%" -Platform "%PLATFORM%" -Stage "%STAGE%" -BuildId "%BUILD_TAG%"
```

Recommended Jenkins parameters:

- `PROFILE_BUNDLE`: channel package id or fallback local profile name.
- `PLATFORM`: `web-mobile`, `wechatgame`, or `bytedance`.
- `STAGE`: usually `all`; also supports `env-prepare`, `before-build`, `build`, `after-build`, `upload`, and `cleanup`.
- `BUILD_ID`: optional custom output id; Jenkins can use `BUILD_TAG` by default.

The runner writes each run to its own subdirectory under `ci/output` by default:

```text
ci/output/20261008-194816-towercar-local-test-web-mobile-all/
```

Each run directory contains:

- `result.json`
- `artifacts.json`
- `run.log`
- `cocos.log`
- `cocos.err.log`
- `environment.json`
- `effective-profile.json`
- `build/` with the platform build output, for example `build/web-mobile/`
- `super-html.log` and `build/super-html/` for `web-mobile` runs that generate single-file HTML packages

The command window shows summarized Cocos Creator progress. Full raw Cocos output is saved to `cocos.log`.

Before build work starts, CI runs `env-prepare`. This stage checks required base commands and automatically prepares installable dependencies for the selected platform:

- Common checks require `node`, `npm`, and the versioned Cocos Creator environment variable such as `COCOS_CREATOR_2_4_11`.
- When `profile.compressImages=true`, it prepares Python image compression packages through pip. `Pillow` is required; `imagequant` and `pyoxipng` are installed when possible and otherwise logged as optional optimization warnings.
- For `web-mobile`, it prepares `super-html` dependencies by running `npm ci` under `ci/common/tools/super-html/vendor` when modules are missing.
- When `profile.uploadEnabled=true`, platform upload dependencies are prepared for the selected platform: WeChat installs `miniprogram-ci` globally through npm, ByteDance installs `tt-minigame-ide-cli` globally through npm, and Web verifies the Python command used by the publisher.

Large runtimes such as Node.js, Python, and Cocos Creator are not installed by CI. Missing runtimes fail early with a clear message. To run only the environment setup:

```cmd
ci\run.cmd -ProfileBundle "towercar-local-test" -Platform "web-mobile" -Stage env-prepare
```

When `profile.compressImages=true`, CI generates `temp/image-compress.manifest.json` before Cocos Creator build through `ci/common/tools/image-compress/generate-manifest.ps1`, then `ci/common/tools/image-compress/compress-build.ps1` compresses images in the platform build output after build. For `web-mobile`, `ci/platforms/web-mobile/tools/super-html/run.ps1` runs after common image compression and generates `super-html` from the compressed `build/web-mobile` directory. The script uses the vendored super-html runtime under `ci/common/tools/super-html/vendor`, so it does not require the Cocos Creator extension directory to exist under `packages`. This step forces the super-html built-in obfuscator off; add obfuscation as a separate CI step when needed.
Before running super-html, CI calls `ci/common/tools/super-html/ensure-deps.ps1`. It checks the required direct dependencies `cheerio`, `clean-css`, `jszip`, `mime-types`, and `uglify-js`; if any are missing, it runs `npm ci` in the vendor directory. These direct dependencies are all used by the vendored super-html build module, while the other `node_modules` folders are transitive dependencies from `package-lock.json`. To prepare them manually:

```cmd
ci\tools\install-super-html-deps.cmd
```

Profile business values are injected after Cocos builds into `channel-config.js` and exposed as `globalThis.__CHANNEL_CONFIG__`. Web output loads this file from `index.html`; WeChat and ByteDance outputs load it from the top of `game.js`. The game code reads values through `RuntimeChannelConfig`, whose defaults are only empty structural fallbacks. Real channel values must be supplied by `profile.json`; the CI runtime injection step validates required fields before writing output. Platform manifest fields under `manifest` are applied to the generated platform project files after build.

`assets/Root/Script/Platforms/RuntimeChannelConfigLocal.ts` provides local fallback values so code can be tested before CI injects a real profile. Injected `channel-config.js` always has priority; the local file is only used when injected config is absent. CI runtime config validation remains the guard that ensures normal packaged builds receive profile-driven values.

Channel logo replacement runs after runtime config validation through `ci/common/tools/logo-inject/inject.ps1` when `profile.logoPath` is set. Put the replacement image in the profile bundle, for example `ci/profiles/<bundle>/Logo.png`, and configure the source project asset through `logoTargetAssetPath`, for example `Load/Logo.png`. The CI tool reads the target asset `.meta` uuid and replaces the renamed image file in the build output.

Pass `-BuildId` to choose the run directory name:

```cmd
ci\run.cmd -ProfileBundle "towercar-local-test" -Platform "web-mobile" -Stage all -BuildId "local-test-001"
```

## Upload And Notification

Upload is controlled only by `profile.uploadEnabled`. During local tests, set `uploadEnabled` to `false` in the selected profile; the upload stage will write `uploadStatus=SKIPPED` and will not call any external tool.

When real upload is needed:

- `web-mobile` uploads through the protected game web publisher portal when `uploadEnabled=true`. The tool zips the build directory, posts raw ZIP bytes to the portal, verifies the returned SHA-256 and public URL, then records `previewUrl` in `artifacts.json`. The public slug comes from `projectCode`; the public title comes from profile `name`. Configure the upload password in `ci/platforms/web-mobile/tools/game-web-publisher/publish_game.py`.
- `web-mobile` supports COS upload when `cosBucket`, `cosRegion`, `cosKey`, and optional `cosConfigPath` are present in the selected platform profile.
- All platforms support a generic `uploadCommand` plus optional `uploadArgs` array. Arguments can use tokens such as `{buildDir}`, `{outputDir}`, `{projectRoot}`, `{platform}`, `{appId}`, `{version}`, `{channelCode}`, `{wechatPrivateKeyPath}`, and `{wechatRobot}`.
- `wechatgame` uploads through `miniprogram-ci` when `uploadEnabled=true`. Put the WeChat upload private key inside the ProfileBundle and set `wechatPrivateKeyPath` to that relative file path. The tool uses `appId`, `wechatPrivateKeyPath`, `wechatRobot`, `version`, and optional `uploadDesc`.
- `bytedance` uploads through the official `tt-minigame-ide-cli` command `tmg` when `uploadEnabled=true`. The tool logs in with `bytedanceUploadEmail` and `bytedanceUploadPassword`, then runs `tmg upload` with `version` and optional `uploadDesc`. Set `bytedanceUploadCli` only if the command name/path is not `tmg`.

Game web publisher profile fields:

- `webPublisherPortal`: optional portal base URL; defaults to the publisher client default.
- `webPublisherUsername`: optional Basic Auth username; defaults to the publisher client default.
- `webPublisherSourceDir`: optional source directory; defaults to the normal `build/web-mobile` output so the ZIP contains `index.html` at its root.
- `webPublisherZipPath`: optional generated ZIP path; defaults to `ci/output/<run-id>/web-mobile-publish.zip`.
- `webPublisherPython`: optional Python executable path when `python` or `py` is not in `PATH`.
- `webPublisherAllowHttp`: optional boolean for controlled non-HTTPS test environments only.

For Web upload debugging without rebuilding:

```cmd
ci\upload-web-mobile.cmd -List
ci\upload-web-mobile.cmd -OutputRun "20261012-093243-towercar-local-test-web-mobile-all"
ci\upload-web-mobile.cmd -OutputRun "20261012-093243-towercar-local-test-web-mobile-all" -SourceDir "build\web-mobile"
```

The standalone uploader reads `effective-profile.json` and `artifacts.json` from the selected output directory, regenerates `web-mobile-publish.zip`, and calls the same game web publisher tool. It writes retry logs to `upload-retry.log` and upload details to `upload.log`.

For WeChat and ByteDance upload debugging without rebuilding:

```cmd
ci\upload-wechatgame.cmd -List
ci\upload-wechatgame.cmd -OutputRun "20261012-093243-towercar-local-test-wechatgame-all"

ci\upload-bytedance.cmd -List
ci\upload-bytedance.cmd -OutputRun "20261012-093243-towercar-local-test-bytedance-all"
```

The standalone uploaders read the selected output directory and then re-read the original ProfileBundle when available, so credentials that are redacted from `effective-profile.json` can still follow the profile for local retry uploads.

Notifications are controlled by `profile.notifyEnabled`. When true, set `notifyWebhookUrl` to receive a JSON POST containing the final build result. Notification failures are recorded in `artifacts.json` but do not change the build exit code.

## Current Scope

- Reads and validates a GameNexus profile bundle.
- Uses `-Platform` to select `web-mobile`, `wechatgame`, or `bytedance` from one channel profile.
- Runs common and platform script dispatch. Project-specific hooks are not used in the current flow.
- Builds `web-mobile`, `wechatgame`, and `bytedance` with Cocos Creator 2.4.11.
- Injects profile runtime values into build output after build without modifying source files.
- Provides fallback runtime values through `RuntimeChannelConfigLocal.ts` when no injected profile config exists.
- Replaces configured channel logo output images after runtime config validation.
- Supports project-local profiles under `ci/profiles`.
- Writes each run to an isolated subdirectory under `ci/output`.
- Generates the image compression manifest before build and compresses build output images after build when `profile.compressImages=true`.
- Generates `web-mobile` super-html output through `platforms/web-mobile/tools/super-html/run.ps1`, after common image compression, instead of the Cocos Creator extension build hook.
- Shows summarized Cocos Creator progress in the command window.
- Creates structured result and artifact files.
- Implements upload scripts controlled by `profile.uploadEnabled`, generic command upload, and web-mobile COS upload.
- Implements web-mobile game web publisher portal upload when `uploadEnabled=true`.
- Implements WeChat minigame upload through `miniprogram-ci` private-key authentication.
- Implements ByteDance minigame upload through `tt-minigame-ide-cli` email/password authentication.
- Implements optional webhook notification after final result generation.
- Records source status without applying temporary source edits.
