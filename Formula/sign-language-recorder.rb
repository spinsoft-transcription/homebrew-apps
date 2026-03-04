# ============================================================
# Homebrew Formula for Sign Language Recorder
# ============================================================
#
# Setup:
#   1. Create a GitHub repo: spinsoft-transcription/homebrew-apps
#   2. Put this file as: Formula/sign-language-recorder.rb
#   3. Build the tarball:  bash scripts/build_tarball.sh 0.1.0
#   4. Upload dist/sign-language-recorder-0.1.0.tar.gz to:
#      - GitHub Releases, Google Drive, S3, or any HTTP server
#   5. Update 'url' and 'sha256' below
#
# Users install with:
#   brew tap spinsoft-transcription/apps
#   brew install sign-language-recorder
#
# Or single command:
#   brew install spinsoft-transcription/apps/sign-language-recorder
#
# Update:
#   brew upgrade sign-language-recorder
#
# ============================================================

class SignLanguageRecorder < Formula
  desc "Sign Language Video Recording and Labeling Application"
  homepage "https://github.com/spinsoft-transcription/sign-language-recorder-app"

  # ── UPDATE THESE when you release a new version ─────────────
  url "https://github.com/spinsoft-transcription/homebrew-apps/releases/download/v0.1.10/sign-language-recorder-0.1.10.tar.gz"
  sha256 "0d551a8b865a62d16ec2e705153447c7a72048009d0159a4d74d814b903a3917"
  version "0.1.10"
  # ────────────────────────────────────────────────────────────

  license "MIT"

  depends_on "python@3.12"
  depends_on "uv"
  depends_on "ffmpeg"
  depends_on :macos

  # Prevent Homebrew from ad-hoc signing PySide6/Qt binaries (they have nested bundles)
  skip_clean ".venv"

  def install
    # Install app + scripts from the tarball (no data/output/venv)
    prefix.install Dir["app", "scripts"]

    # venv lives in var/ so it persists across brew upgrades (avoids re-downloading ~2GB)
    venv_dir = var/"sign-language-recorder/.venv"

    # Only create venv + install deps if it doesn't exist yet (skip on upgrade)
    unless (venv_dir/"bin/python").exist?
      venv_dir.mkpath
      python = Formula["python@3.12"].opt_bin/"python3.12"
      system "uv", "venv", "--python", python.to_s, "--relocatable", venv_dir.to_s
      system "uv", "pip", "install", "--python", venv_dir/"bin/python",
             "-r", prefix/"app/requirement.txt"

      # Fix PySide6 codesigning — Homebrew's ad-hoc signing chokes on nested Qt frameworks.
      # Must sign inner bundles first (bottom-up), then the outer framework.
      pyside6_dir = venv_dir/"lib/python3.12/site-packages/PySide6"
      if pyside6_dir.exist?
        Dir.glob(pyside6_dir/"Qt/lib/**/*.app").each do |app_bundle|
          system "codesign", "--force", "--sign", "-", app_bundle
        end
        Dir.glob(pyside6_dir/"Qt/lib/*.framework").each do |framework|
          system "codesign", "--force", "--sign", "-", framework
        end
        Dir.glob(pyside6_dir/"**/*.{dylib,so}").each do |lib|
          system "codesign", "--force", "--sign", "-", lib rescue nil
        end
      end
    else
      ohai "Reusing existing venv at #{venv_dir}"
    end

    # Create CLI launcher with auto-setup for Launchpad .app bundle
    # Homebrew sandbox blocks writes to /Applications in both install and post_install,
    # so the launcher creates the .app bundle on first run (runs as user, no sandbox).
    (bin/"sign-language-recorder").write <<~EOS
      #!/bin/bash
      export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
      export LANG="en_US.UTF-8"

      INSTALL_DIR="#{prefix}"
      VENV_PYTHON="#{var}/sign-language-recorder/.venv/bin/python"
      APP_BUNDLE="/Applications/Sign Language Recorder.app"
      APP_VERSION="#{version}"

      setup_app_bundle() {
          # Check if .app already exists with current version
          if [[ -d "$APP_BUNDLE" ]]; then
              local existing_ver
              existing_ver=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null)
              [[ "$existing_ver" == "$APP_VERSION" ]] && return 0
              rm -rf "$APP_BUNDLE"
          fi

          echo "Setting up Launchpad icon..."
          mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

          # Copy icon
          if [[ -f "$INSTALL_DIR/app/assets/app.icns" ]]; then
              cp "$INSTALL_DIR/app/assets/app.icns" "$APP_BUNDLE/Contents/Resources/app.icns"
          fi

          # Info.plist
          cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
       "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>CFBundleExecutable</key>
          <string>launcher</string>
          <key>CFBundleIdentifier</key>
          <string>com.spinsoft.signlanguagerecorder</string>
          <key>CFBundleName</key>
          <string>Sign Language Recorder</string>
          <key>CFBundleDisplayName</key>
          <string>Sign Language Recorder</string>
          <key>CFBundleVersion</key>
          <string>__VERSION__</string>
          <key>CFBundleShortVersionString</key>
          <string>__VERSION__</string>
          <key>CFBundleIconFile</key>
          <string>app</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>LSMinimumSystemVersion</key>
          <string>12.0</string>
          <key>NSCameraUsageDescription</key>
          <string>This app needs camera access to record sign language videos.</string>
          <key>NSMicrophoneUsageDescription</key>
          <string>This app may use the microphone for audio recording.</string>
          <key>NSHighResolutionCapable</key>
          <true/>
      </dict>
      </plist>
      PLIST
          sed -i '' "s/__VERSION__/$APP_VERSION/g" "$APP_BUNDLE/Contents/Info.plist"

          # Launcher script
          cat > "$APP_BUNDLE/Contents/MacOS/launcher" << 'LAUNCHER'
      #!/bin/bash
      export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
      export LANG="en_US.UTF-8"
      SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
      # Re-exec through the CLI launcher so paths are always correct
      exec "#{bin}/sign-language-recorder" "$@"
      LAUNCHER
          chmod 755 "$APP_BUNDLE/Contents/MacOS/launcher"

          echo "Launchpad icon installed."
          killall Dock 2>/dev/null || true
      }

      if [[ "$1" == "--update" ]]; then
          brew upgrade sign-language-recorder 2>/dev/null || brew upgrade spinsoft-transcription/apps/sign-language-recorder
          exit $?
      fi

      if [[ "$1" == "--setup" ]]; then
          setup_app_bundle
          exit $?
      fi

      # Auto-setup .app bundle on first run (silent)
      setup_app_bundle 2>/dev/null

      # Settings and DB live in var/ so they persist across brew upgrades
      PERSISTENT_DIR="#{var}/sign-language-recorder"
      mkdir -p "$PERSISTENT_DIR"

      # Create default settings only on first install
      if [[ ! -f "$PERSISTENT_DIR/settings.yaml" ]]; then
          cat > "$PERSISTENT_DIR/settings.yaml" << 'SETTINGS'
      camera_id: 0
      controller_vdo_height: 500
      controller_vdo_width: 500
      database_location: sign_language.db
      enable_preview_window: false
      enable_teleprompter_window: false
      font_path: assets/font/Prompt-Regular.ttf
      main_font_size: 14
      main_monitor: 0
      mask_path: assets/mask_komkit_v1.png
      output_directory: output
      output_video_fps: 25.0
      output_video_height: 2160
      output_video_width: 3840
      rest_pose_detection_threshold: 0.5
      session_length: 10
      queue_web_enabled: false
      queue_web_url: ""
      queue_web_api_key: ""
      queue_web_data_dir: data
      SETTINGS
      fi

      # Symlink persistent settings + DB into app dir (app reads from CWD)
      ln -sf "$PERSISTENT_DIR/settings.yaml" "$INSTALL_DIR/app/settings.yaml"

      # DB: if it exists in app dir but not in persistent dir (first migration), move it
      if [[ -f "$INSTALL_DIR/app/sign_language.db" && ! -L "$INSTALL_DIR/app/sign_language.db" ]]; then
          mv "$INSTALL_DIR/app/sign_language.db" "$PERSISTENT_DIR/sign_language.db"
      fi
      # Always symlink so the app creates/reads DB in persistent location
      ln -sf "$PERSISTENT_DIR/sign_language.db" "$INSTALL_DIR/app/sign_language.db"

      # Symlink persistent data/ and output/ directories
      for dir in data output; do
          mkdir -p "$PERSISTENT_DIR/$dir"
          # Remove placeholder dir from install if present, then symlink
          [[ -d "$INSTALL_DIR/app/$dir" && ! -L "$INSTALL_DIR/app/$dir" ]] && rm -rf "$INSTALL_DIR/app/$dir"
          ln -sf "$PERSISTENT_DIR/$dir" "$INSTALL_DIR/app/$dir"
      done

      # App must run from app/ directory (all relative paths assume this)
      cd "$INSTALL_DIR/app" || exit 1
      exec "$VENV_PYTHON" app.py "$@"
    EOS
  end

  def caveats
    <<~EOS
      Sign Language Recorder has been installed!

      Launch from:
        • Terminal  — sign-language-recorder
        • Launchpad — icon is auto-created on first launch

      If Launchpad icon doesn't appear, run:
        sign-language-recorder --setup

      Update:
        brew upgrade sign-language-recorder

      Camera access: macOS will prompt for camera permission on first launch.
    EOS
  end

  test do
    assert_match "usage", shell_output("#{bin}/sign-language-recorder --help 2>&1", 1)
  end
end
