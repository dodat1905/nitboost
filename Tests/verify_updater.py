from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build.noindex/NitBoost.app"
TOOLS = ROOT / "build.noindex/Sparkle-2.10.1/bin"
INFO = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
VERSION = INFO["CFBundleShortVersionString"]
ARCHIVE = ROOT / f"dist/NitBoost-{VERSION}.zip"


def run(arguments, **options):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, **options).stdout.strip()


def wait_for(predicate, message, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except (subprocess.CalledProcessError, FileNotFoundError, plistlib.InvalidFileException):
            pass
        time.sleep(0.2)
    raise RuntimeError(message)


def stop_app():
    subprocess.run(["pkill", "-TERM", "-x", "NitBoost"], capture_output=True)
    wait_for(lambda: subprocess.run(["pgrep", "-x", "NitBoost"], capture_output=True).returncode != 0, "NitBoost did not stop")


def apple_script(body):
    return run(["osascript", "-e", f'tell application "System Events"\ntell process "NitBoost"\n{body}\nend tell\nend tell'])


def press_button(title):
    wait_for(lambda: apple_script(f'get exists button "{title}" of window 1') == "true", f"Missing updater button: {title}")
    apple_script(f'perform action "AXPress" of button "{title}" of window 1')


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, format, *arguments):
        pass


was_running = subprocess.run(["pgrep", "-x", "NitBoost"], capture_output=True).returncode == 0
with tempfile.TemporaryDirectory(prefix="updater-test-", dir=ROOT / "build.noindex") as directory:
    stage = Path(directory)
    public = stage / "public"
    public.mkdir()
    run(["ditto", str(ARCHIVE), str(public / ARCHIVE.name)])
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(public)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    prefix = f"http://127.0.0.1:{server.server_port}/"
    run([str(TOOLS / "generate_appcast"), "--account", "com.dodat.nitboost", "--maximum-deltas", "0", "--disable-signing-warning", "--download-url-prefix", prefix, str(public)])
    feed = ET.parse(public / "appcast.xml")
    assert feed.findtext("./channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version") == INFO["CFBundleVersion"]
    host = stage / "NitBoost.app"
    run(["ditto", str(APP), str(host)])
    host_info = dict(INFO)
    host_info.update({
        "CFBundleVersion": str(int(INFO["CFBundleVersion"]) - 1),
        "CFBundleShortVersionString": "1.0.0",
        "SUFeedURL": prefix + "appcast.xml",
        "SUEnableAutomaticChecks": False,
        "SUAutomaticallyUpdate": False,
        "SUDefaultsDomain": "com.dodat.nitboost." + stage.name,
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
    })
    (host / "Contents/Info.plist").write_bytes(plistlib.dumps(host_info))
    identities = run(["security", "find-identity", "-p", "codesigning"])
    identity = "XDRBoost Local Signing" if '"XDRBoost Local Signing"' in identities else "-"
    run(["codesign", "--force", "--sign", identity, str(host)])
    try:
        stop_app()
        run(["open", "-n", str(host)])
        wait_for(lambda: apple_script("get exists menu bar item 1 of menu bar 1") == "true", "Test app did not start")
        apple_script('click menu bar item 1 of menu bar 1\nperform action "AXPress" of menu item "Check for Updates…" of menu 1 of menu bar item 1 of menu bar 1')
        press_button("Install Update")
        press_button("Install and Relaunch")
        wait_for(lambda: plistlib.loads((host / "Contents/Info.plist").read_bytes())["CFBundleVersion"] == INFO["CFBundleVersion"], "Sparkle did not replace the app")
        wait_for(lambda: subprocess.run(["pgrep", "-f", str(host / "Contents/MacOS/NitBoost")], capture_output=True).returncode == 0, "Sparkle did not relaunch the app")
        assert plistlib.loads((host / "Contents/Info.plist").read_bytes()) == INFO
        assert (host / "Contents/MacOS/NitBoost").read_bytes() == (APP / "Contents/MacOS/NitBoost").read_bytes()
        run(["codesign", "--verify", "--deep", "--strict", str(host)])
        print("PASS: Sparkle fetched a signed feed, downloaded the signed update, replaced the older app, and relaunched it", flush=True)
    finally:
        stop_app()
        server.shutdown()
        server.server_close()
        subprocess.run(["defaults", "delete", host_info["SUDefaultsDomain"]], capture_output=True)
        if was_running:
            run(["open", "-n", "/Applications/NitBoost.app"])
