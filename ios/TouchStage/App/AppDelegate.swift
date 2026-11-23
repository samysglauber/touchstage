import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = MainViewController()
        win.makeKeyAndVisible()
        self.window = win
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Prevent accidental note hanging on background
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Resumed
    }
}
