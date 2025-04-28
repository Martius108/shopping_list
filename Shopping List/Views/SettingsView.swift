//
//  SettingsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 27.04.25.
//

import Foundation
import SwiftUI
import SwiftData

struct SettingsView: View {
    
    // Access the model context from the environment
    @Environment(\.modelContext) private var modelContext
    // Set a variable to react onto the color scheme
    @Environment(\.colorScheme) var colorScheme
    // Set the settings instance and bind it to the content view
    @Binding var settings: ViewSettings
    
    @State private var selectedImage: UIImage? = nil // For the image picker
    @State private var showImagePicker = false // To trigger the image picker
    
    var body: some View {
        
        Form {
            // Scheme Mode Picker
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
            
            // Background Image Picker
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
                        try modelContext.save()  // Speichern des Kontextes
                        print("Image saved. Size: \(backgroundImageData.count) Bytes")
                    } catch {
                        print("Image upload failded: \(error.localizedDescription)")
                    }
                }
            }
            
            // Opacity Slider
            Section(header: Text("Opacity")) {
                Slider(value: $settings.elementOpacity, in: 0...1, step: 0.02)
                    .padding()
                Text("Opacity: \(Int(settings.elementOpacity * 100))%")
            }
            .onChange(of: settings.elementOpacity) { oldValue, newValue in
                settings.elementOpacity = newValue
                do {
                    try modelContext.save()
                    print("Opacity changed: \(settings.elementOpacity)")
                } catch {
                    print("Saving opacity failed: \(error.localizedDescription)")
                }
            }
            // Background color picker
            Section(header: Text("Background Color")) {
                ColorPicker("Select Background Color", selection: Binding(
                    get: { Color(hex: settings.backgroundColor) },
                    set: { newColor in
                        settings.backgroundImageData = nil
                        settings.backgroundColor = newColor.toHex()
                        do {
                            try modelContext.save() // Speichern der neuen Farbe
                            print("Color changed: \(settings.backgroundColor)")
                        } catch {
                            print("Saving color failded: \(error.localizedDescription)")
                        }
                    }
                ))
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onDisappear {
            // Do ssomething here
        }
        .navigationTitle("Settings")
    }
}

// Simple Image Picker for selecting images
struct ImagePicker: View {
    @Binding var image: UIImage?
    
    var body: some View {
        ImagePickerController(image: $image)
    }
}

// UIKit ImagePickerController wrapped in SwiftUI for image picking
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

