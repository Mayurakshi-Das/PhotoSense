@preconcurrency import AVKit
@preconcurrency import Photos
import SwiftUI
import UIKit

/// Full-screen photo/video gallery backed by UIPageViewController.
///
/// UIPageViewController gives us native one-item-at-a-time snapping based on the
/// actual container geometry. Each page lazily requests only its lightweight
/// preview until it becomes active, then upgrades to a high-quality image or
/// prepares a single AVPlayer.
struct MediaGalleryPreviewView: View {
    let allItems: [MediaAssetIndexRecord]
    let initialAssetId: String
    let onDismiss: () -> Void
    let onDelete: ((MediaAssetIndexRecord) -> Void)?

    @State private var currentIndex: Int
    @State private var thumbnailPrefetchTask: Task<Void, Never>?
    @State private var dragOffset: CGSize = .zero
    @State private var showDeleteConfirmation = false

    init(
        allItems: [MediaAssetIndexRecord],
        initialAssetId: String,
        onDismiss: @escaping () -> Void,
        onDelete: ((MediaAssetIndexRecord) -> Void)? = nil
    ) {
        self.allItems = allItems
        self.initialAssetId = initialAssetId
        self.onDismiss = onDismiss
        self.onDelete = onDelete

        let initialIndex = allItems.firstIndex { $0.id == initialAssetId } ?? 0
        _currentIndex = State(initialValue: min(max(0, initialIndex), max(0, allItems.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack {
                if allItems.isEmpty {
                    ContentUnavailableView(
                        "Item Unavailable",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("This item is no longer available in your photo library.")
                    )
                    .foregroundStyle(.white)
                } else {
                    GalleryPageView(items: allItems, currentIndex: $currentIndex)
                        .ignoresSafeArea()
                }

                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .allowsHitTesting(true)
            }
            .offset(y: max(0, dragOffset.height))
            .scaleEffect(dismissScale)
        }
        .statusBarHidden(false)
        .simultaneousGesture(dismissDragGesture)
        .alert(
            "Delete This Item?",
            isPresented: $showDeleteConfirmation,
            presenting: currentItem
        ) { item in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?(item)
                onDismiss()
            }
        } message: { item in
            Text("This \(item.kind == .video ? "video" : "photo") will be moved to the Bin and can be recovered for 30 days.")
        }
        .onAppear {
            prefetchThumbnails(around: currentIndex)
        }
        .onChange(of: currentIndex) { _, newIndex in
            prefetchThumbnails(around: newIndex)
        }
        .onDisappear {
            thumbnailPrefetchTask?.cancel()
            thumbnailPrefetchTask = nil
        }
    }

    private var currentItem: MediaAssetIndexRecord? {
        guard allItems.indices.contains(currentIndex) else { return nil }
        return allItems[currentIndex]
    }

    private var dismissScale: CGFloat {
        let progress = min(max(dragOffset.height, 0), 260) / 260
        return 1 - (progress * 0.10)
    }

    private var backgroundOpacity: Double {
        let progress = min(max(dragOffset.height, 0), 320) / 320
        return 1 - (progress * 0.55)
    }

    private var topBar: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")

            Spacer()

            VStack(spacing: 2) {
                Text("\(min(currentIndex + 1, allItems.count)) of \(allItems.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                if let date = currentItem?.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Spacer()

            if onDelete != nil {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Delete")
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.72), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var bottomBar: some View {
        HStack {
            if let item = currentItem {
                HStack(spacing: 8) {
                    if !item.resolutionString.isEmpty {
                        Text(item.resolutionString)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if let size = item.formattedFileSize {
                        Text(size)
                            .font(.caption)
                    }

                    if item.kind == .video {
                        Text(item.formattedDuration)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func prefetchThumbnails(around index: Int) {
        thumbnailPrefetchTask?.cancel()

        let radius = thumbnailPrefetchRadius(itemCount: allItems.count)
        let items = allItems
        let start = max(0, index - radius)
        let end = min(max(0, items.count - 1), index + radius)
        guard start <= end else { return }

        let idsToPrefetch = items[start...end].map(\.id)
        thumbnailPrefetchTask = Task(priority: .utility) {
            for id in idsToPrefetch {
                guard !Task.isCancelled else { return }
                _ = await ThumbnailPipeline.shared.thumbnail(
                    for: id,
                    targetSize: CGSize(width: 520, height: 520)
                )
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard vertical > 0, vertical > horizontal else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let predictedVertical = value.predictedEndTranslation.height
                let shouldDismiss = vertical > 120 && vertical > horizontal * 1.2 || predictedVertical > 220

                if shouldDismiss {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        dragOffset = CGSize(width: value.translation.width, height: 700)
                    }
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func thumbnailPrefetchRadius(itemCount: Int) -> Int {
        guard itemCount > 1 else { return 0 }

        let baseRadius = UIDevice.current.userInterfaceIdiom == .pad ? 3 : 2
        if ProcessInfo.processInfo.physicalMemory >= 6_000_000_000 {
            return min(baseRadius + 1, itemCount - 1)
        }
        return min(baseRadius, itemCount - 1)
    }
}

// MARK: - UIKit Paging Bridge

private struct GalleryPageView: UIViewControllerRepresentable {
    let items: [MediaAssetIndexRecord]
    @Binding var currentIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black

        if let initialController = context.coordinator.controller(for: currentIndex) {
            controller.setViewControllers(
                [initialController],
                direction: .forward,
                animated: false
            )
        }

        return controller
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refreshCachedControllers()

        let visibleIndex = context.coordinator.visibleIndex(in: pageViewController)
        guard visibleIndex != currentIndex,
              let controller = context.coordinator.controller(for: currentIndex) else {
            return
        }

        let direction: UIPageViewController.NavigationDirection = currentIndex > visibleIndex ? .forward : .reverse
        pageViewController.setViewControllers(
            [controller],
            direction: direction,
            animated: false
        )
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: GalleryPageView
        private var controllerCache: [Int: UIHostingController<GalleryPageContentView>] = [:]

        init(_ parent: GalleryPageView) {
            self.parent = parent
        }

        func controller(for index: Int) -> UIHostingController<GalleryPageContentView>? {
            guard parent.items.indices.contains(index) else { return nil }

            if let cached = controllerCache[index] {
                cached.rootView = pageContent(for: index)
                return cached
            }

            let controller = UIHostingController(rootView: pageContent(for: index))
            controller.view.backgroundColor = .black
            controllerCache[index] = controller
            pruneCache(around: parent.currentIndex)
            return controller
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = index(for: viewController) else { return nil }
            return controller(for: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = index(for: viewController) else { return nil }
            return controller(for: index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let visible = pageViewController.viewControllers?.first,
                  let index = index(for: visible) else { return }

            parent.currentIndex = index
            refreshCachedControllers()
            pruneCache(around: index)
        }

        func refreshCachedControllers() {
            for index in controllerCache.keys {
                controllerCache[index]?.rootView = pageContent(for: index)
            }
            pruneCache(around: parent.currentIndex)
        }

        func visibleIndex(in pageViewController: UIPageViewController) -> Int {
            guard let visible = pageViewController.viewControllers?.first,
                  let index = index(for: visible) else {
                return parent.currentIndex
            }
            return index
        }

        private func pageContent(for index: Int) -> GalleryPageContentView {
            GalleryPageContentView(
                item: parent.items[index],
                isActive: index == parent.currentIndex
            )
        }

        private func index(for viewController: UIViewController) -> Int? {
            for (index, controller) in controllerCache where controller === viewController {
                return index
            }
            return nil
        }

        private func pruneCache(around index: Int) {
            let radius = 2
            let validRange = max(0, index - radius)...min(max(0, parent.items.count - 1), index + radius)
            for cachedIndex in controllerCache.keys where !validRange.contains(cachedIndex) {
                controllerCache[cachedIndex] = nil
            }
        }
    }
}

// MARK: - Page Content

private struct GalleryPageContentView: View {
    let item: MediaAssetIndexRecord
    let isActive: Bool

    var body: some View {
        if item.kind == .video {
            GalleryVideoItemView(item: item, isActive: isActive)
        } else {
            GalleryPhotoItemView(item: item, isActive: isActive)
        }
    }
}

// MARK: - Photo Page

@MainActor
private struct GalleryPhotoItemView: View {
    let item: MediaAssetIndexRecord
    let isActive: Bool

    @Environment(\.displayScale) private var displayScale

    @State private var previewImage: UIImage?
    @State private var highQualityImage: UIImage?
    @State private var loadToken = UUID()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewImage, highQualityImage == nil {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                if let highQualityImage {
                    Image(uiImage: highQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }

                if previewImage == nil && highQualityImage == nil {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: "\(item.id)-\(isActive)-\(Int(geometry.size.width))x\(Int(geometry.size.height))") {
                await loadImages(targetSize: targetPixelSize(for: geometry.size))
            }
        }
        .background(Color.black)
        .onChange(of: item.id) { _, _ in
            resetImages()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                highQualityImage = nil
            }
        }
    }

    private func loadImages(targetSize: CGSize) async {
        let token = UUID()
        loadToken = token

        if previewImage == nil,
           let thumbnail = await ThumbnailPipeline.shared.thumbnail(
            for: item.id,
            targetSize: CGSize(width: 520, height: 520)
           ) {
            guard !Task.isCancelled, token == loadToken else { return }
            previewImage = thumbnail
        }

        guard isActive, !Task.isCancelled, token == loadToken else { return }

        if let image = await GalleryPhotoKitLoader.requestImage(
            assetId: item.id,
            targetSize: targetSize
        ) {
            guard !Task.isCancelled, isActive, token == loadToken else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                highQualityImage = image
            }
        }
    }

    private func targetPixelSize(for containerSize: CGSize) -> CGSize {
        let width = max(1, containerSize.width * displayScale)
        let height = max(1, containerSize.height * displayScale)
        return CGSize(width: width, height: height)
    }

    private func resetImages() {
        loadToken = UUID()
        previewImage = nil
        highQualityImage = nil
    }
}

// MARK: - Video Page

@MainActor
private struct GalleryVideoItemView: View {
    let item: MediaAssetIndexRecord
    let isActive: Bool

    @State private var posterImage: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoadingPlayer = false
    @State private var loadToken = UUID()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let posterImage, player == nil {
                    Image(uiImage: posterImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }

                if posterImage == nil || (isActive && isLoadingPlayer && player == nil) {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading video...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: "\(item.id)-\(isActive)") {
                await loadPosterAndPlayerIfNeeded()
            }
        }
        .background(Color.black)
        .onChange(of: item.id) { _, _ in
            resetVideo()
        }
        .onChange(of: isActive) { _, active in
            if active {
                player?.play()
            } else {
                releasePlayer()
            }
        }
        .onDisappear {
            releasePlayer()
        }
    }

    private func loadPosterAndPlayerIfNeeded() async {
        let token = UUID()
        loadToken = token

        if posterImage == nil,
           let thumbnail = await ThumbnailPipeline.shared.thumbnail(
            for: item.id,
            targetSize: CGSize(width: 720, height: 720)
           ) {
            guard !Task.isCancelled, token == loadToken else { return }
            posterImage = thumbnail
        }

        guard isActive, !Task.isCancelled, token == loadToken else {
            releasePlayer()
            return
        }

        isLoadingPlayer = true

        let asset = await GalleryPhotoKitLoader.requestAVAsset(assetId: item.id)

        guard !Task.isCancelled, isActive, token == loadToken else {
            isLoadingPlayer = false
            return
        }

        guard let asset else {
            isLoadingPlayer = false
            return
        }

        let playerItem = AVPlayerItem(asset: asset.asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = newPlayer
        isLoadingPlayer = false
        newPlayer.play()
    }

    private func resetVideo() {
        loadToken = UUID()
        posterImage = nil
        releasePlayer()
    }

    private func releasePlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isLoadingPlayer = false
    }
}

// MARK: - PhotoKit Loading

private enum GalleryPhotoKitLoader {
    static func requestImage(assetId: String, targetSize: CGSize) async -> UIImage? {
        let box = GalleryRequestBox()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                guard let asset = fetchResult.firstObject else {
                    continuation.resume(returning: nil)
                    return
                }

                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false

                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    let hasError = info?[PHImageErrorKey] != nil

                    guard !isDegraded || wasCancelled || hasError else { return }
                    box.resumeImageOnce(
                        returning: wasCancelled || hasError ? nil : image,
                        continuation: continuation
                    )
                }

                box.requestID = requestID
            }
        }, onCancel: {
            PHImageManager.default().cancelImageRequest(box.requestID)
        })
    }

    static func requestAVAsset(assetId: String) async -> SendableAVAsset? {
        let box = GalleryRequestBox()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                guard let asset = fetchResult.firstObject else {
                    continuation.resume(returning: nil)
                    return
                }

                let options = PHVideoRequestOptions()
                options.deliveryMode = .automatic
                options.version = .current
                options.isNetworkAccessAllowed = true

                let requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, _, info in
                    let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    let hasError = info?[PHImageErrorKey] != nil
                    nonisolated(unsafe) let transferred = asset
                    let wrapped = transferred.map { SendableAVAsset(asset: $0) }
                    continuation.resume(returning: wasCancelled || hasError ? nil : wrapped)
                }

                box.requestID = requestID
            }
        }, onCancel: {
            PHImageManager.default().cancelImageRequest(box.requestID)
        })
    }
}

private struct SendableAVAsset: @unchecked Sendable {
    let asset: AVAsset
}

private final class GalleryRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    var requestID: PHImageRequestID = PHInvalidImageRequestID

    func resumeImageOnce(returning value: UIImage?, continuation: CheckedContinuation<UIImage?, Never>) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }

}
