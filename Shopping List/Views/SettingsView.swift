//
//  SettingsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 27.04.25.
//

import Foundation
import SwiftUI
import SwiftData

// View for adjusting app settings like theme, background, and opacity
struct SettingsView: View {
    
    // Access the model context to save changes
    @Environment(\.modelContext) private var modelContext
    // Access the current color scheme (light/dark mode)
    @Environment(\.colorScheme) var colorScheme
    // Bind the settings instance to this view
    @Binding var settings: ViewSettings
    
    // Local state for handling image selection
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false

    var body: some View {
        
        Form {
            // Theme Mode Picker Section
            Section(header: Text("Theme Mode")) {
                Picker("Select Theme", selection: $settings.themeMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: settings.themeMode) { oldValue, newValue in
                    settings.themeMode = newValue
                    do {
                        try modelContext.save()
                        print("Theme mode changed from \(oldValue) to \(newValue)")
                    } catch {
                        print("Saving theme mode failed: \(error.localizedDescription)")
                    }
                }
            }
            
            // Background Image Picker Section
            Section(header: Text("Background Image")) {
                Button("Select Image") {
                    showImagePicker.toggle()
                }
                
                if let selectedImage = selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                }
            }
            .onChange(of: selectedImage) { oldImage, newImage in
                if let newImage = newImage {
                    settings.backgroundImageData = newImage.jpegData(compressionQuality: 0.8)
                    guard let backgroundImageData = settings.backgroundImageData else {
                        print("Image data is nil.")
                        return
                    }
                    do {
                        try modelContext.save()
                        print("Image saved. Size: \(backgroundImageData.count) Bytes")
                    } catch {
                        print("Saving background image failed: \(error.localizedDescription)")
                    }
                }
            }
            
            // Opacity Slider Section
            Section(header: Text("Opacity")) {
                Slider(value: $settings.elementOpacity, in: 0...1, step: 0.02)
                    .padding()
                Text("Opacity: \(Int(settings.elementOpacity * 100))%")
            }
            .onChange(of: settings.elementOpacity) { oldValue, newValue in
                settings.elementOpacity = newValue
                do {
                    try modelContext.save()
                    print("Opacity changed to: \(Int(newValue * 100))%")
                } catch {
                    print("Saving opacity failed: \(error.localizedDescription)")
                }
            }
            
            // Background Color Picker Section
            Section(header: Text("Background Color")) {
                ColorPicker("Select Background Color", selection: Binding(
                    get: { Color(hex: settings.backgroundColor) },
                    set: { newColor in
                        // Reset background image when a new color is chosen
                        settings.backgroundImageData = nil
                        settings.backgroundColor = newColor.toHex()
                        do {
                            try modelContext.save()
                            print("Background color changed to: \(settings.backgroundColor)")
                        } catch {
                            print("Saving background color failed: \(error.localizedDescription)")
                        }
                    }
                ))
            }
        }
        .sheet(isPresented: $showImagePicker) {
            // Present the native image picker
            ImagePicker(image: $selectedImage)
        }
        .navigationTitle("Settings")
    }
}

// Simple SwiftUI wrapper for presenting the image picker
struct ImagePicker: View {
    @Binding var image: UIImage?
    
    var body: some View {
        ImagePickerController(image: $image)
    }
}

// UIKit-based image picker wrapped for SwiftUI
struct ImagePickerController: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(image: $image)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // Coordinator to handle image picking actions
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding var image: UIImage?
        
        init(image: Binding<UIImage?>) {
            _image = image
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let selectedImage = info[.originalImage] as? UIImage {
                image = selectedImage
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
