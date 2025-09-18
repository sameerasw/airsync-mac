class Airsync < Formula
  desc "Sync Android notifications to macOS with clipboard and media control"
  homepage "https://github.com/sameerasw/airsync-mac"
  version "2.0.20"
  
  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/sameerasw/airsync-mac/releases/download/v#{version}/AirSync-arm64.zip"
      sha256 "PLACEHOLDER_ARM64_SHA256"
    else
      url "https://github.com/sameerasw/airsync-mac/releases/download/v#{version}/AirSync-x86_64.zip"
      sha256 "PLACEHOLDER_X86_64_SHA256"
    end
  end

  depends_on macos: :sonoma

  def install
    prefix.install "AirSync.app"
  end

  def post_install
    # Remove quarantine attribute to prevent macOS security dialogs
    system "xattr", "-r", "-d", "com.apple.quarantine", "#{prefix}/AirSync.app"
  rescue
    # Ignore errors if xattr fails (e.g., if attribute doesn't exist)
    nil
  end

  def caveats
    <<~EOS
      AirSync has been installed to:
        #{prefix}/AirSync.app

      To use AirSync:
      1. Open AirSync from Applications or run: open "#{prefix}/AirSync.app"
      2. Allow network access when prompted
      3. Follow the setup instructions to connect your Android device

      You may need to manually allow the app in System Preferences > Privacy & Security
      if macOS prevents it from opening initially.

      For wireless ADB setup, see: https://github.com/sameerasw/airsync-android/blob/main/README.md#adb-setup
    EOS
  end

  test do
    assert_predicate prefix/"AirSync.app", :exist?
    assert_predicate prefix/"AirSync.app/Contents/Info.plist", :exist?
  end
end