import AppKit

// Entry point of the acceptance fixture: a plain AppKit app that opens windows with
// controlled properties on request, so that acceptance tests have something real to
// move and resize. It is a regular app (Dock icon, can own the key window) and hosts
// a control server; see FixtureAppDelegate.
let application = NSApplication.shared
let delegate = FixtureAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
