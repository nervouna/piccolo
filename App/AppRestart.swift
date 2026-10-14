import Foundation
import PiccoloUI

/// Quits the running app and starts it again, from a helper process that outlives it.
///
/// The app cannot do this alone: it is gone before it could ask for the new launch. So it starts
/// `/bin/sh` with a short script, which the system keeps running after the app quits, and quits.
/// The script waits for the app to be gone and then opens the bundle through LaunchServices.
///
/// The wait is the point of the script. For a moment after a process has died, LaunchServices still
/// lists its instance as running, and an `open` in that moment goes to the dead instance. It fails
/// (error -600), and it does more than fail: the window server is left waiting for that instance to
/// check in, so that no application is frontmost and none can be brought to the front until some
/// live application is activated. So the script does not run `open` while `lsappinfo` lists an
/// instance of the app, and it asks again when an `open` fails or no instance shows up afterwards.
enum AppRestart {
    /// The script. Its arguments are the process ID of the app that is quitting, the path of its
    /// bundle and its bundle ID. It logs to the unified log under the tag `PiccoloRestart`.
    static let script = #"""
        pid=$1
        bundle=$2
        id=$3

        log() { /usr/bin/logger -t PiccoloRestart "$*"; }

        # Whether LaunchServices lists an instance of the app.
        listed() { /usr/bin/lsappinfo find "bundleid=$id" 2>/dev/null | /usr/bin/grep -q '^ASN:'; }

        # Waits until LaunchServices lists no instance, for at most $1 tenths of a second.
        wait_unlisted() {
            n=0
            while listed && [ "$n" -lt "$1" ]; do
                sleep 0.1
                n=$((n + 1))
            done
        }

        # 1. The old process has to be gone (30 s at most).
        n=0
        while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 300 ]; do
            sleep 0.1
            n=$((n + 1))
        done

        # 2. LaunchServices has to have forgotten it (10 s at most).
        wait_unlisted 100

        # 3. Open the bundle; ask again when that fails or no instance shows up within 10 s.
        attempt=0
        while [ "$attempt" -lt 20 ]; do
            attempt=$((attempt + 1))
            if /usr/bin/open "$bundle" 2>/dev/null; then
                n=0
                while [ "$n" -lt 100 ]; do
                    if listed; then
                        exit 0
                    fi
                    sleep 0.1
                    n=$((n + 1))
                done
                log "attempt $attempt: opened $bundle, but no instance appeared"
            else
                log "attempt $attempt: open of $bundle failed"
            fi
            sleep 0.5
            wait_unlisted 100
        done
        log "gave up starting $bundle"
        exit 1
        """#

    /// Starts the helper for the app with process ID `processID`, which the caller then quits.
    ///
    /// - Throws: ``RestartError`` when the helper could not be started. Nothing was changed then.
    static func startHelper(
        processID: Int32, bundlePath: String, bundleID: String
    ) throws(RestartError) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "piccolo-restart", String(processID), bundlePath, bundleID]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw RestartError(message: error.localizedDescription)
        }
    }
}
