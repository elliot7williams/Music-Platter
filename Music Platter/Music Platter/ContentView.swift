//
//  ContentView.swift
//  Music Platter
//
//  Created by Elliot Williams on 2025-08-24.
//

import SwiftUI
import MediaPlayer
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

// MARK: - Album Item with Precomputed Data
struct AlbumItem: Identifiable {
    let id = UUID()
    let mediaItem: MPMediaItem
    let image: UIImage?
    let gradient: [Color]
    let hue: Double
    var songs: [MPMediaItem] = []
}

// MARK: - Media Loader
class MusicLibrary: ObservableObject {
    @Published var items: [AlbumItem] = []
    @Published var isLoading = true
    @Published var hasError = false
    @Published var errorMessage = ""
    
    init() {
        // Delay the request to ensure the view is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestAccess()
        }
    }
    
    // Changed from private to internal so it can be called from the view
    func requestAccess() {
        let status = MPMediaLibrary.authorizationStatus()
        
        if status == .authorized {
            self.loadAlbumsInBackground()
        } else if status == .notDetermined {
            MPMediaLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self.loadAlbumsInBackground()
                    } else {
                        self.hasError = true
                        self.errorMessage = "Music library access denied. Please enable access in Settings."
                        self.isLoading = false
                    }
                }
            }
        } else {
            self.hasError = true
            self.errorMessage = "Music library access denied. Please enable access in Settings."
            self.isLoading = false
        }
    }
    
    private func loadAlbumsInBackground() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let query = MPMediaQuery.albums()
                let collections = query.collections ?? []
                
                // Create a safe array of album items
                var albumItems: [AlbumItem] = []
                
                for (index, collection) in collections.enumerated() {
                    // Only process a reasonable number of albums to prevent memory issues
                    if index >= 200 { break }
                    
                    guard let item = collection.representativeItem else { continue }
                    
                    let artwork = item.artwork
                    let image = artwork?.image(at: CGSize(width: 200, height: 200))
                    
                    // Extract colors from the image or use a fallback
                    let gradient: [Color]
                    if let image = image {
                        let uiColors = image.extractDominantColors()
                        gradient = uiColors.map { Color($0) }
                    } else {
                        // Fallback to hue-based gradient
                        let hue = Double(index) * (360.0 / Double(max(1, collections.count)))
                        gradient = [Color(hue: hue/360, saturation: 0.7, brightness: 0.5),
                                   Color(hue: (hue + 60)/360, saturation: 0.7, brightness: 0.5)]
                    }
                    
                    // Get all songs for this album
                    let songs = collection.items
                    
                    let albumItem = AlbumItem(mediaItem: item, image: image, gradient: gradient, hue: Double(index), songs: songs)
                    albumItems.append(albumItem)
                }
                
                DispatchQueue.main.async {
                    self.items = albumItems
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.hasError = true
                    self.errorMessage = "Failed to load music library: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func searchAlbums(query: String) -> [AlbumItem] {
        if query.isEmpty {
            return items
        }
        
        return items.filter { album in
            let title = album.mediaItem.albumTitle ?? ""
            let artist = album.mediaItem.albumArtist ?? ""
            
            return title.localizedCaseInsensitiveContains(query) ||
                   artist.localizedCaseInsensitiveContains(query)
        }
    }
    
    // Public method to retry loading
    func retryLoading() {
        isLoading = true
        hasError = false
        errorMessage = ""
        requestAccess()
    }
}

// MARK: - Music Player
class MusicPlayer: ObservableObject {
    private var player: AVPlayer?
    
    func playSong(_ song: MPMediaItem) {
        if let assetURL = song.assetURL {
            player = AVPlayer(url: assetURL)
            player?.play()
        }
    }
    
    func stop() {
        player?.pause()
        player = nil
    }
}

// MARK: - Disk View
struct AlbumDiskView: View {
    @StateObject private var library = MusicLibrary()
    @StateObject private var musicPlayer = MusicPlayer()
    @State private var rotation: Double = 0
    @State private var selectedAlbumId: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var showAlbumDetail: Bool = false
    @State private var selectedAlbumForDetail: AlbumItem?
    @State private var showSearchPanel: Bool = false
    @State private var searchText: String = ""
    @State private var frontAlbumGradient: [Color] = [.black, .purple]
    
    private let radius: CGFloat = 150
    private let diskSize: CGFloat = 350
    private let visibleCardCount: Int = 12
    
    private var filteredAlbums: [AlbumItem] {
        if searchText.isEmpty {
            return library.items
        } else {
            return library.searchAlbums(query: searchText)
        }
    }
    
    // Safe index calculation to prevent crashes
    private func safeAlbumIndex(for index: Int) -> Int {
        guard !filteredAlbums.isEmpty else { return 0 }
        let totalAlbums = filteredAlbums.count
        let baseIndex = (Int(rotation / (360.0 / Double(visibleCardCount))) + index)
        return (baseIndex % totalAlbums + totalAlbums) % totalAlbums
    }
    
    // Find the front album (closest to 0 degrees)
    private func updateFrontAlbum() {
        guard !filteredAlbums.isEmpty else {
            frontAlbumGradient = [.black, .purple]
            return
        }
        
        // Find the album closest to the front (0 degrees)
        var minAngle = Double.greatestFiniteMagnitude
        var frontAlbum: AlbumItem? = nil
        
        for i in 0..<min(visibleCardCount, filteredAlbums.count) {
            let safeIndex = safeAlbumIndex(for: i)
            guard safeIndex < filteredAlbums.count else { continue }
            
            let angle = Double(i) * (360.0 / Double(visibleCardCount)) + rotation
            // Normalize angle to be between -180 and 180
            let normalizedAngle = (angle + 180).truncatingRemainder(dividingBy: 360) - 180
            let absAngle = abs(normalizedAngle)
            
            if absAngle < minAngle {
                minAngle = absAngle
                frontAlbum = filteredAlbums[safeIndex]
            }
        }
        
        if let album = frontAlbum {
            withAnimation(.easeInOut(duration: 0.5)) {
                frontAlbumGradient = album.gradient
            }
        }
    }
    
    // Extracted view for the disk content to simplify the main body
    private func diskContent() -> some View {
        ZStack {
            // Disk outline
            Circle()
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                .frame(width: diskSize, height: diskSize)
            
            // Album cards arranged in a circle using trigonometry
            // Safe ForEach implementation
            ForEach(0..<min(visibleCardCount, filteredAlbums.count), id: \.self) { index in
                let safeIndex = safeAlbumIndex(for: index)
                
                // Only create view if index is valid
                if safeIndex < filteredAlbums.count {
                    let item = filteredAlbums[safeIndex]
                    
                    // Calculate position using trigonometry
                    let angle = Double(index) * (360.0 / Double(visibleCardCount)) + rotation
                    let angleRadians = angle * Double.pi / 180
                    let x = radius * cos(angleRadians)
                    let y = radius * sin(angleRadians)
                    
                    AlbumCard(
                        image: item.image,
                        gradient: item.gradient,
                        hue: item.hue,
                        isSelected: selectedAlbumId == item.id,
                        onHoverChange: { _ in },
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                selectedAlbumId = selectedAlbumId == item.id ? nil : item.id
                            }
                        },
                        onDoubleTap: {
                            selectedAlbumForDetail = item
                            showAlbumDetail = true
                        }
                    )
                    .offset(x: x, y: y)
                }
            }
        }
        .frame(width: diskSize, height: diskSize)
        .rotation3DEffect(
            .degrees(60),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            anchorZ: 0,
            perspective: 0.2
        )
    }
    
    // Extracted view for the loading state
    private var loadingView: some View {
        VStack {
            ProgressView("Loading Music Library...")
                .foregroundColor(.white)
                .padding()
            
            Text("This may take a moment if you have a large music library")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    // Extracted view for the error state
    private var errorView: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.white)
                .padding()
            
            Text(library.errorMessage)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Try Again") {
                library.retryLoading()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
    
    // Extracted view for the empty state
    private var emptyView: some View {
        VStack {
            Image(systemName: "music.note")
                .font(.system(size: 50))
                .foregroundColor(.white)
                .padding()
            
            Text("No albums found in your library")
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            .padding()
            
            Button("Try Again") {
                library.retryLoading()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient based on front album
                LinearGradient(colors: frontAlbumGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                if library.isLoading {
                    loadingView
                } else if library.hasError {
                    errorView
                } else if library.items.isEmpty {
                    emptyView
                } else {
                    // Disk container
                    diskContent()
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                    // Update rotation based on drag
                                    rotation += Double(value.translation.width / 10)
                                    updateFrontAlbum()
                                }
                                .onEnded { value in
                                    // Add momentum to the rotation
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)) {
                                        rotation += Double(value.predictedEndTranslation.width / 50)
                                    }
                                    dragOffset = 0
                                    updateFrontAlbum()
                                }
                        )
                    
                    // Search button positioned based on screen size
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    showSearchPanel.toggle()
                                }
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(15)
                                    .background(Circle().fill(Color.blue))
                                    .shadow(radius: 10)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                    
                    // Search panel
                    if showSearchPanel {
                        SearchPanelView(
                            searchText: $searchText,
                            isPresented: $showSearchPanel,
                            albums: filteredAlbums,
                            onAlbumSelected: { album in
                                selectedAlbumForDetail = album
                                showAlbumDetail = true
                                showSearchPanel = false
                            }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .onChange(of: rotation) { _ in
                updateFrontAlbum()
            }
            .onChange(of: searchText) { _ in
                updateFrontAlbum()
            }
            .onAppear {
                updateFrontAlbum()
            }
        }
        .sheet(isPresented: $showAlbumDetail) {
            if let album = selectedAlbumForDetail {
                AlbumDetailView(album: album, musicPlayer: musicPlayer)
            }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - Search Panel View
struct SearchPanelView: View {
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let albums: [AlbumItem]
    let onAlbumSelected: (AlbumItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Search albums...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .padding(.top)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .padding(.trailing)
                .padding(.top)
            }
            
            if albums.isEmpty {
                Text("No albums found")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(albums) { album in
                            Button(action: {
                                onAlbumSelected(album)
                            }) {
                                HStack {
                                    if let image = album.image {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .cornerRadius(6)
                                    } else {
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(hue: album.hue/360, saturation: 0.7, brightness: 0.6),
                                                        Color(hue: (album.hue + 30)/360, saturation: 0.7, brightness: 0.6)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 50, height: 50)
                                            .cornerRadius(6)
                                            .overlay(
                                                Text("Album")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 10, weight: .bold))
                                            )
                                    }
                                    
                                    VStack(alignment: .leading) {
                                        Text(album.mediaItem.albumTitle ?? "Unknown Album")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text(album.mediaItem.albumArtist ?? "Unknown Artist")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .padding(.leading, 8)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.9), Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(radius: 20)
        )
        .padding(.trailing, 15)
        .padding(.bottom, 80)
    }
}

// MARK: - Album Card with Enhanced 3D Effect
struct AlbumCard: View {
    let image: UIImage?
    let gradient: [Color]
    let hue: Double
    let isSelected: Bool
    var onHoverChange: ([Color]) -> Void
    var onSelect: () -> Void
    var onDoubleTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                // Fallback gradient based on hue
                LinearGradient(
                    colors: [
                        Color(hue: hue/360, saturation: 0.7, brightness: 0.6),
                        Color(hue: (hue + 30)/360, saturation: 0.7, brightness: 0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text("Album")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .bold))
                )
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.7), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
        )
        .scaleEffect(isHovering || isSelected ? 1.15 : 1.0)
        .offset(y: isHovering || isSelected ? -20 : 0)
        .zIndex(isHovering || isSelected ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .onLongPressGesture(minimumDuration: 0.2) {
            // Simulate double tap with long press
            onDoubleTap()
        }
    }
}

// MARK: - Album Detail View
struct AlbumDetailView: View {
    let album: AlbumItem
    @ObservedObject var musicPlayer: MusicPlayer
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                // Album artwork and info
                HStack {
                    if let image = album.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .cornerRadius(10)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(album.mediaItem.albumTitle ?? "Unknown Album")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(album.mediaItem.albumArtist ?? "Unknown Artist")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("\(album.songs.count) songs")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 10)
                    
                    Spacer()
                }
                .padding()
                
                // Song list
                if album.songs.isEmpty {
                    Text("No songs available")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(album.songs, id: \.persistentID) { song in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(song.title ?? "Unknown Title")
                                        .font(.headline)
                                    Text(song.albumTrackNumber > 0 ? "Track \(song.albumTrackNumber)" : "")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    musicPlayer.playSong(song)
                                }) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationBarTitle("Album Details", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - Color Extraction Utilities
extension UIImage {
    func extractDominantColors() -> [UIColor] {
        guard let cgImage = self.cgImage else { return [] }
        
        // Reduce image size for faster processing
        let targetSize = CGSize(width: 50, height: 50)
        let resizedImage = self.resize(to: targetSize)
        
        guard let resizedCGImage = resizedImage?.cgImage else { return [] }
        
        // Get pixel data
        let width = resizedCGImage.width
        let height = resizedCGImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: totalBytes)
        
        guard let context = CGContext(data: &rawData,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return []
        }
        
        context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Collect colors
        var colors: [UIColor] = []
        for y in 0..<height {
            for x in 0..<width {
                let byteIndex = (bytesPerRow * y) + x * bytesPerPixel
                let red = CGFloat(rawData[byteIndex]) / 255.0
                let green = CGFloat(rawData[byteIndex + 1]) / 255.0
                let blue = CGFloat(rawData[byteIndex + 2]) / 255.0
                let alpha = CGFloat(rawData[byteIndex + 3]) / 255.0
                
                if alpha > 0.5 { // Ignore mostly transparent pixels
                    colors.append(UIColor(red: red, green: green, blue: blue, alpha: 1.0))
                }
            }
        }
        
        // If we couldn't extract colors, return some defaults
        if colors.isEmpty {
            return [UIColor.systemPurple, UIColor.systemIndigo]
        }
        
        // Simple approach: take the first and a contrasting color
        // For a more sophisticated approach, you could implement k-means clustering
        let primaryColor = colors.first!
        
        // Find a contrasting color (complementary or with different brightness)
        var secondaryColor: UIColor
        if colors.count > 1 {
            // Try to find a color that's significantly different
            let midIndex = min(colors.count / 2, colors.count - 1)
            secondaryColor = colors[midIndex]
        } else {
            // Create a complementary color
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            
            if primaryColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
                let complementaryHue = (hue + 0.5).truncatingRemainder(dividingBy: 1.0)
                secondaryColor = UIColor(hue: complementaryHue, saturation: saturation, brightness: brightness, alpha: alpha)
            } else {
                secondaryColor = UIColor.systemIndigo
            }
        }
        
        return [primaryColor, secondaryColor]
    }
    
    func resize(to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}

// MARK: - Preview
struct AlbumDiskView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumDiskView()
    }
}
