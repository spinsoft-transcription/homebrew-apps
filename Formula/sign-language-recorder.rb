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
  url "https://github.com/spinsoft-transcription/homebrew-apps/releases/download/v0.1.5/sign-language-recorder-0.1.5.tar.gz"
  sha256 "11ce2759e701ba0abd0fcce23fda7061bb11efecfed34d2625166c9c780cd86f"
  version "0.1.5"
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

    # Create virtual environment using Homebrew's stable Python (not uv's temp download)
    venv = prefix/".venv"
    python = Formula["python@3.12"].opt_bin/"python3.12"
    system "uv", "venv", "--python", python.to_s, "--relocatable", venv.to_s
    system "uv", "pip", "install", "--python", venv/"bin/python",
           "-r", prefix/"app/requirement.txt"

    # Fix PySide6 codesigning — Homebrew's ad-hoc signing chokes on nested Qt frameworks.
    # Must sign inner bundles first (bottom-up), then the outer framework.
    pyside6_dir = venv/"lib/python3.12/site-packages/PySide6"
    if pyside6_dir.exist?
      # 1. Sign all nested .app bundles inside frameworks first
      Dir.glob(pyside6_dir/"Qt/lib/**/*.app").each do |app_bundle|
        system "codesign", "--force", "--sign", "-", app_bundle
      end
      # 2. Sign all frameworks (now their subcomponents are already signed)
      Dir.glob(pyside6_dir/"Qt/lib/*.framework").each do |framework|
        system "codesign", "--force", "--sign", "-", framework
      end
      # 3. Sign any remaining Mach-O binaries/dylibs
      Dir.glob(pyside6_dir/"**/*.{dylib,so}").each do |lib|
        system "codesign", "--force", "--sign", "-", lib rescue nil
      end
    end

    # Create CLI launcher
    (bin/"sign-language-recorder").write <<~EOS
      #!/bin/bash
      export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
      export LANG="en_US.UTF-8"

      INSTALL_DIR="#{prefix}"
      VENV_PYTHON="$INSTALL_DIR/.venv/bin/python"

      if [[ "$1" == "--update" ]]; then
          brew upgrade sign-language-recorder 2>/dev/null || brew upgrade spinsoft-transcription/apps/sign-language-recorder
          exit $?
      fi

      # App must run from app/ directory (all relative paths assume this)
      cd "$INSTALL_DIR/app" || exit 1
      exec "$VENV_PYTHON" app.py "$@"
    EOS
  end

  def post_install
    create_app_bundle
    create_default_settings
  end

  def create_app_bundle
    app_bundle = Pathname.new("/Applications/Sign Language Recorder.app")

    # Always recreate to pick up new icon/version on upgrade
    rm_rf app_bundle if app_bundle.exist?

    (app_bundle/"Contents/MacOS").mkpath
    (app_bundle/"Contents/Resources").mkpath

    # Copy icon if generated
    icon_src = prefix/"app/assets/app.icns"
    if icon_src.exist?
      cp icon_src, app_bundle/"Contents/Resources/app.icns"
    end

    # Info.plist
    (app_bundle/"Contents/Info.plist").write <<~XML
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
          <string>#{version}</string>
          <key>CFBundleShortVersionString</key>
          <string>#{version}</string>
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
    XML

    # Launcher script
    (app_bundle/"Contents/MacOS/launcher").write <<~EOS
      #!/bin/bash
      export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
      export LANG="en_US.UTF-8"
      cd "#{prefix}/app" || exit 1
      exec "#{prefix}/.venv/bin/python" app.py "$@"
    EOS
    (app_bundle/"Contents/MacOS/launcher").chmod 0755
  end

  def create_default_settings
    settings_file = prefix/"app/settings.yaml"
    return if settings_file.exist?

    settings_file.write <<~YAML
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
    YAML
  end

  def caveats
    <<~EOS
      Sign Language Recorder has been installed!

      Launch from:
        • Launchpad — search "Sign Language Recorder"
        • Terminal  — sign-language-recorder

      Update:
        brew upgrade sign-language-recorder

      The app icon should appear in Launchpad automatically.
      If not, try: killall Dock

      Camera access: macOS will prompt for camera permission on first launch.
    EOS
  end

  test do
    assert_match "usage", shell_output("#{bin}/sign-language-recorder --help 2>&1", 1)
  end
end
