import AppKit

let app = NSWorkspace.shared.frontmostApplication
print(app?.localizedName ?? "None")
