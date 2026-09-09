import SwiftUI
import MapKit
import CloudKit

struct GridPeopleMapView: View {
    @ObservedObject var viewModel: GridViewModel
    var onSelectPerson: (String) -> Void
    @State private var position: MapCameraPosition = .region(GridPeopleMapLogic.defaultRegion)

    private var pins: [GridPeopleMapLogic.Pin] {
        let me = viewModel.currentUserProfile
        let tabProfiles = viewModel.nodes(for: viewModel.peopleTab).flatMap { $0 }.compactMap(\.userProfile)
        let nearby = viewModel.proximityService.activeNearbyProfiles
        let profiles = tabProfiles.isEmpty ? nearby : tabProfiles
        return GridPeopleMapLogic.pins(
            fromProfiles: profiles + [me].compactMap { $0 },
            currentDeviceID: me?.deviceID
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
                                isCurrentUser: pin.isCurrentUser
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pin.name)
                    }
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapUserLocationButton()
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
            fitPins()
        }
        .onChange(of: pins.map(\.id)) { _ in
            fitPins()
        }
        .onChange(of: viewModel.locationService.currentLocation?.coordinate.latitude) { _ in
            fitPins()
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

    private func fitPins() {
        if let region = GridPeopleMapLogic.region(for: pins) {
            position = .region(region)
        } else if let fallbackCenter {
            position = .region(GridPeopleMapLogic.region(around: fallbackCenter))
        } else {
            position = .region(GridPeopleMapLogic.defaultRegion)
        }
    }
}

private struct MapPersonPin: View {
    let name: String
    let deviceID: String
    let profileImage: CKAsset?
    let isCurrentUser: Bool
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
