import Foundation
// import UIKit // Temporarily removed to isolate UIKit dependencies
import Combine // Added for ObservableObject
import MultipeerConnectivity

// Define a protocol for messages or use Codable structs directly
struct AppMessage: Codable {
    let type: MessageType
    let payload: Data // Use Data for flexible payload, encode/decode specific types
}

enum MessageType: String, Codable {
    case userProfileUpdate
    case gridUpdate
    // Add more message types as needed
}

class NetworkService: NSObject, ObservableObject {
    private let serviceType = "grid-app" // Max 15 chars, only a-z, 0-9, and hyphens

    private let myPeerID: MCPeerID
    private var session: MCSession
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser
    private var nearbyServiceBrowser: MCNearbyServiceBrowser

    @Published var connectedPeers: [MCPeerID] = []

    // Closures to handle received data - GridViewModel will set these
    var onUserProfileReceived: ((UserProfile) -> Void)?
    var onGridNodeReceived: ((GridNode) -> Void)? // Or perhaps the whole grid or changes
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?


    override init() {
        // For now, use host name instead of UIDevice.current.name for macOS compatibility
        self.myPeerID = MCPeerID(displayName: ProcessInfo.processInfo.hostName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.nearbyServiceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)

        super.init()

        self.session.delegate = self
        self.nearbyServiceAdvertiser.delegate = self
        self.nearbyServiceBrowser.delegate = self

        startHosting()
        startBrowsing()
    }

    deinit {
        stopHosting()
        stopBrowsing()
    }

    func startHosting() {
        nearbyServiceAdvertiser.startAdvertisingPeer()
        print("Started hosting as \(myPeerID.displayName)")
    }

    func stopHosting() {
        nearbyServiceAdvertiser.stopAdvertisingPeer()
        print("Stopped hosting")
    }

    func startBrowsing() {
        nearbyServiceBrowser.startBrowsingForPeers()
        print("Started browsing for peers")
    }

    func stopBrowsing() {
        nearbyServiceBrowser.stopBrowsingForPeers()
        print("Stopped browsing")
    }

    func sendUserProfile(_ profile: UserProfile) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let profileData = try JSONEncoder().encode(profile)
            let message = AppMessage(type: .userProfileUpdate, payload: profileData)
            let messageData = try JSONEncoder().encode(message)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Error sending user profile: \(error.localizedDescription)")
        }
    }
    
    func sendGridNodeUpdate(_ node: GridNode) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let nodeData = try JSONEncoder().encode(node)
            let message = AppMessage(type: .gridUpdate, payload: nodeData)
            let messageData = try JSONEncoder().encode(message)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Error sending grid node update: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension NetworkService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    self.onPeerConnected?(peerID)
                    print("Connected to: \(peerID.displayName)")
                }
            case .notConnected:
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                    self.onPeerDisconnected?(peerID)
                    print("Disconnected from: \(peerID.displayName)")
                }
            case .connecting:
                print("Connecting to: \(peerID.displayName)")
            @unknown default:
                print("Unknown state for peer \(peerID.displayName): \(state)")
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            do {
                let decoder = JSONDecoder()
                let message = try decoder.decode(AppMessage.self, from: data)
                
                switch message.type {
                case .userProfileUpdate:
                    let userProfile = try decoder.decode(UserProfile.self, from: message.payload)
                    self.onUserProfileReceived?(userProfile)
                    print("Received profile from \(peerID.displayName): \(userProfile.userID)")
                case .gridUpdate:
                    let gridNode = try decoder.decode(GridNode.self, from: message.payload)
                    self.onGridNodeReceived?(gridNode)
                     print("Received grid node update from \(peerID.displayName)")
                }
            } catch {
                print("Error decoding received data: \(error.localizedDescription)")
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Stream data not used in this example
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Resource sharing not used in this example
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Resource sharing not used in this example
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension NetworkService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Automatically accept invitations for simplicity in this example
        print("Received invitation from \(peerID.displayName)")
        invitationHandler(true, self.session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Error advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension NetworkService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Invite found peers to connect
        print("Found peer: \(peerID.displayName). Inviting...")
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
        // Handle lost peer if necessary, MCSessionDelegate handles disconnection
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Error browsing for peers: \(error.localizedDescription)")
    }
} 