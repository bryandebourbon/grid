import SwiftUI
import MapKit
import CloudKit

struct GridPeopleMapView: View {
    @ObservedObject var viewModel: GridViewModel
    var onSelectPerson: (String) -> Void
    @State private var position: MapCameraPosition
    @State private var hasFittedCamera: Bool

    init(viewModel: GridViewModel, onSelectPerson: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.onSelectPerson = onSelectPerson
        let center = viewModel.locationService.currentLocation?.coordinate
            ?? viewModel.currentUserProfile?.location?.coordinate
        if let center {
            _position = State(initialValue: .region(GridPeopleMapLogic.region(around: center)))
            _hasFittedCamera = State(initialValue: true)
        } else {
            _position = State(initialValue: .region(GridPeopleMapLogic.defaultRegion))
            _hasFittedCamera = State(initialValue: false)
        }
    }

    private var pins: [GridPeopleMapLogic.Pin] {
        let me = viewModel.currentUserProfile
        let tabProfiles = viewModel.nodes(for: viewModel.peopleTab).flatMap { $0 }.compactMap(\.userProfile)
        let includeHidden = viewModel.peopleTab.showsHiddenPeers(masterUnlocked: viewModel.seesHiddenPeople)
        let nearby = viewModel.proximityService.activeNearbyProfiles.filter { profile in
            profile.deviceID == me?.deviceID
                || GridMasterViewerLogic.shouldShowPeer(profile, includeHidden: includeHidden)
        }
        let others = (tabProfiles.isEmpty ? nearby : tabProfiles).filter { profile in
            profile.deviceID != me?.deviceID
        }
        let selfProfiles = viewModel.isDiscoverable ? [me].compactMap { $0 } : []
        return GridPeopleMapLogic.pins(
            fromProfiles: others + selfProfiles,
            currentDeviceID: me?.deviceID,
            includeHidden: includeHidden
        )
    }

    private var fallbackCenter: CLLocationCoordinate2D? {
        viewModel.locationService.currentLocation?.coordinate
            ?? viewModel.currentUserProfile?.location?.coordinate
    }

    private var locationAuthorized: Bool {
        let status = viewModel.locationService.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var body: some View {
        GeometryReader { proxy in
            Map(position: $position) {
                if locationAuthorized {
                    UserAnnotation()
                }
                ForEach(pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate, anchor: .bottom) {
                        Button {
                            onSelectPerson(pin.deviceID)
                        } label: {
                            MapPersonPin(
                                name: pin.name,
                                deviceID: pin.deviceID,
                                profileImage: profile(for: pin)?.profileImage,
                                isCurrentUser: pin.isCurrentUser,
                                isHidden: pin.isHidden
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pin.name)
                    }
                }
                ForEach(viewModel.interestHeatBlobs) { blob in
                    Annotation("", coordinate: blob.coordinate, anchor: .center) {
                        Circle()
                            .fill(Color(red: 1, green: 0.18, blue: 0.24).opacity(blob.opacity))
                            .frame(width: blob.radius, height: blob.radius)
                            .allowsHitTesting(false)
                    }
                    .annotationTitles(.hidden)
                    .annotationSubtitles(.hidden)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
            }
            .mapControlVisibility(.visible)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(red: 0.85, green: 0.89, blue: 0.86))
        .onAppear {
            if viewModel.locationService.authorizationStatus == .notDetermined {
                viewModel.locationService.requestLocationPermission()
            } else {
                viewModel.locationService.requestLocationOnce()
            }
            viewModel.recordInterestFootsteps(for: viewModel.currentUserProfile)
            viewModel.refreshInterestHeatmap()
            if viewModel.followsUserLocation {
                centerOnBlueDot()
            } else {
                fitCamera(force: true)
            }
        }
        .refreshable {
            await viewModel.refreshPeopleAndMessages()
        }
        .onChange(of: pins.map(\.id)) { _ in
            guard viewModel.followsUserLocation == false else { return }
            fitCamera(force: false)
        }
        .onChange(of: viewModel.isDiscoverable) { _ in
            guard viewModel.followsUserLocation == false else { return }
            fitCamera(force: false)
        }
        .onChange(of: viewModel.locationService.currentLocation?.coordinate.latitude) { _ in
            guard viewModel.followsUserLocation == false else { return }
            fitCamera(force: false)
        }
        .onChange(of: viewModel.recenterMapToken) { _ in
            centerOnBlueDot()
        }
        .onChange(of: viewModel.peopleTab) { _ in
            guard viewModel.followsUserLocation == false else { return }
            hasFittedCamera = false
            fitCamera(force: true)
        }
    }

    private func profile(for pin: GridPeopleMapLogic.Pin) -> UserProfile? {
        if pin.deviceID == viewModel.currentUserProfile?.deviceID {
            return viewModel.currentUserProfile
        }
        return viewModel.nodes(for: viewModel.peopleTab)
            .flatMap { $0 }
            .compactMap(\.userProfile)
            .first { $0.deviceID == pin.deviceID }
            ?? viewModel.proximityService.activeNearbyProfiles.first { $0.deviceID == pin.deviceID }
    }

    /// Keep the camera on you. Heatmap dots can cover a wide radius; they should not pull the zoom out.
    private func fitCamera(force: Bool) {
        guard force || hasFittedCamera == false else { return }
        if let fallbackCenter {
            position = .region(GridPeopleMapLogic.region(around: fallbackCenter))
            hasFittedCamera = true
        }
    }

    private func centerOnBlueDot() {
        let fallback: MapCameraPosition = {
            if let fallbackCenter {
                return .region(GridPeopleMapLogic.region(around: fallbackCenter))
            }
            return .automatic
        }()
        position = fallback
        hasFittedCamera = true
        Task { @MainActor in
            position = .userLocation(followsHeading: false, fallback: fallback)
        }
    }
}

private struct MapPersonPin: View {
    let name: String
    let deviceID: String
    let profileImage: CKAsset?
    let isCurrentUser: Bool
    var isHidden: Bool = false
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        VStack(spacing: 4) {
            avatar
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: isCurrentUser ? 3 : 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isHidden {
                        HiddenUserBadge(size: 14)
                            .offset(x: 2, y: 2)
                    }
                }
                .shadow(color: .black.opacity(0.28), radius: 3, y: 1)

            Text(name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .onAppear {
            imageLoader.loadImage(from: profileImage)
        }
        .onChange(of: ProfileImageRefreshLogic.loadKey(for: profileImage)) { _ in
            imageLoader.loadImage(from: profileImage)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let loadedImage = imageLoader.image {
            loadedImage
                .resizable()
                .scaledToFill()
        } else {
            InitialsAvatarFill(name: name, seed: deviceID, gridColumns: 5)
        }
    }
}
