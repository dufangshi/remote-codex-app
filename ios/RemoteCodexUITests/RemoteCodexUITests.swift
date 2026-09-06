import XCTest

final class RemoteCodexUITests: XCTestCase {
    func testLoginNavigateThreadAndOpenCompletedNotification() throws {
        continueAfterFailure = false
        let env = E2eEnv.load()
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["RESET_SESSION"] = "1"
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        app.launch()
        print("E2E_STEP launched")

        let urlField = app.textFields["relayUrlField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 20), "url field")
        urlField.tap()
        urlField.clearAndType(env.relayUrl)
        app.buttons["continueButton"].tap()

        let signInEntry = app.buttons["signInEntryButton"]
        let openDevices = app.buttons["openDevicesButton"]
        let connect = app.buttons["connectDeviceButton"]
        XCTAssertTrue(
            app.waitForAny([signInEntry, openDevices, connect], timeout: 30),
            "sign in, open devices, or connect"
        )
        print("E2E_STEP past home")
        if signInEntry.exists { signInEntry.tap() }

        let identifier = app.textFields["identifierField"]
        if identifier.waitForExistence(timeout: 10) {
            identifier.tap()
            identifier.typeText(env.username)
            let password = app.secureTextFields["passwordField"]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            for _ in 0..<4 where password.frame.maxY > app.windows.firstMatch.frame.maxY - 40 {
                app.swipeUp()
            }
            password.tap()
            sleep(1)
            app.typeText(env.password)
            if app.keyboards.buttons["done"].exists {
                app.keyboards.buttons["done"].tap()
            } else if app.buttons["Done"].exists {
                app.buttons["Done"].tap()
            }
            app.swipeUp()
            let signIn = app.buttons["signInButton"]
            XCTAssertTrue(signIn.waitForExistence(timeout: 5))
            signIn.tap()
            print("E2E_STEP signed in")
            app.dismissKeyboardIfPresent()
            let notice = app.staticTexts["notice"]
            if notice.waitForExistence(timeout: 2) {
                XCTFail("login error: \(notice.label)")
            }
        }

        app.dismissKeyboardIfPresent()
        if app.buttons["openDevicesButton"].waitForExistence(timeout: 3) {
            app.buttons["openDevicesButton"].tap()
        }
        let connectButton = app.buttons["connectDeviceButton"].firstMatch
        XCTAssertTrue(
            app.waitForAny([
                connectButton,
                app.buttons["Connect"],
                app.staticTexts["Workspaces"],
                app.otherElements["deviceList"],
                app.staticTexts["Devices"],
            ], timeout: 30),
            "devices or workspaces"
        )
        if !app.staticTexts["Workspaces"].exists, connectButton.exists {
            print("E2E_STEP connect frame=\(connectButton.frame) hittable=\(connectButton.isHittable)")
            app.tapHittable(connectButton)
        }
        print("E2E_STEP connected")

        let onWorkspaces = app.waitForAny([
            app.staticTexts["Workspaces"],
            app.otherElements["workspaceList"],
            app.staticTexts["No workspaces yet"],
        ], timeout: 30)
        if !onWorkspaces {
            print("E2E_TREE \(app.debugDescription.prefix(4000))")
        }
        XCTAssertTrue(onWorkspaces, "workspaces page")
        print("E2E_STEP workspaces title=\(app.staticTexts["Workspaces"].exists)")
        sleep(5)
        let createdId = env.startThreadAndPrompt()
        print("E2E_STEP prompted id=\(createdId)")
        sleep(3)
        let watch = app.staticTexts["threadWatchCount"]
        print("E2E_STEP watch=\(watch.exists ? watch.label : "missing")")
        let banner = app.buttons["agentNotificationBanner"].firstMatch
        let bannerText = app.staticTexts["Agent run finished."].firstMatch
        let threadScreen = app.otherElements["threadScreen"]
        XCTAssertTrue(
            app.waitForAny([banner, bannerText, threadScreen, app.staticTexts["threadTitle"], app.staticTexts["Thread"]], timeout: 25),
            "expected agent-complete notification or thread"
        )
        if !threadScreen.exists, !app.staticTexts["Thread"].exists {
            if banner.exists {
                app.tapHittable(banner)
            } else if bannerText.exists {
                app.tapHittable(bannerText)
            }
        }
        sleep(1)
        XCTAssertTrue(
            app.waitForAny([
                threadScreen,
                app.otherElements["threadWebView"],
                app.staticTexts["threadTitle"],
                app.staticTexts["Thread"],
                app.webViews["threadWebView"],
                app.webViews.firstMatch,
            ], timeout: 20),
            "expected thread webview after tapping notification"
        )
    }
}

private struct E2eEnv {
    let relayUrl: String
    let username: String
    let password: String
    let token: String
    let deviceId: String
    let workspaceId: String
    let deviceApi: String

    static func load() -> E2eEnv {
        let process = ProcessInfo.processInfo.environment
        let file = URL(fileURLWithPath: "/Users/mac/dev/remote-codex-app/.local/e2e-env.json")
        let json = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        func value(_ key: String, _ fallback: String) -> String {
            process[key] ?? (json[key] as? String) ?? fallback
        }
        let relayUrl = value("E2E_RELAY_URL", (json["relayUrl"] as? String) ?? "http://127.0.0.1:18790")
        let deviceId = value("E2E_DEVICE_ID", json["deviceId"] as? String ?? "")
        let token = value("E2E_TOKEN", json["token"] as? String ?? "")
        let workspaceId = value("E2E_WORKSPACE_ID", json["workspaceId"] as? String ?? "")
        return E2eEnv(
            relayUrl: relayUrl,
            username: value("E2E_USERNAME", json["username"] as? String ?? "mobile"),
            password: value("E2E_PASSWORD", json["password"] as? String ?? "mobile-pass-1"),
            token: token,
            deviceId: deviceId,
            workspaceId: workspaceId,
            deviceApi: value("E2E_DEVICE_API", json["deviceApi"] as? String ?? "\(relayUrl)/relay/devices/\(deviceId)/api")
        )
    }

    func startThreadAndPrompt() -> String {
        let title = "notify-ios"
        let body = """
        {"workspaceId":"\(workspaceId)","title":"\(title)","provider":"codex","model":"ios-e2e-stream","approvalMode":"yolo"}
        """
        let thread = post("\(deviceApi)/threads/start", body)
        let id = thread["id"] as? String ?? ((thread["thread"] as? [String: Any])?["id"] as? String) ?? ""
        _ = post("\(deviceApi)/threads/\(id)/prompt", "{\"prompt\":\"hello, reply me with hello\"}")
        return id
    }

    private func post(_ url: String, _ body: String) -> [String: Any] {
        guard let endpoint = URL(string: url) else { return [:] }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.httpBody = body.data(using: .utf8)
        let sem = DispatchSemaphore(value: 0)
        var payload: [String: Any] = [:]
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("E2E_HTTP \(status) \(url) \(body.prefix(200)) err=\(error?.localizedDescription ?? "")")
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = json
            }
            sem.signal()
        }.resume()
        sem.wait()
        return payload
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let value = value as? String, !value.isEmpty {
            let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            typeText(delete)
        }
        typeText(text)
    }
}

private extension XCUIApplication {
    func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        return elements.contains(where: { $0.exists })
    }

    func dismissKeyboardIfPresent() {
        if keyboards.buttons["done"].exists {
            keyboards.buttons["done"].tap()
        } else if keyboards.buttons["Done"].exists {
            keyboards.buttons["Done"].tap()
        } else if keyboards.element.exists {
            swipeDown()
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 1) {
            allow.tap()
        }
    }

    func tapHittable(_ element: XCUIElement) {
        dismissKeyboardIfPresent()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if element.exists, element.isHittable {
                element.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertTrue(element.exists, "missing element to tap")
        let frame = element.frame
        print("E2E_STEP windowTap frame=\(frame) window=\(windows.firstMatch.frame)")
        coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }
}
