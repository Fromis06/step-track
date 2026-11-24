import SwiftUI
import UIKit
import SceneKit

struct BodyMap3DView: UIViewRepresentable {
    @Binding var selectedRegion: BodyRegionID?
    @Binding var isBackView: Bool
    var resetTrigger: Int
    var accentColor: Color
    var structuralColor: Color
    var defaultMuscleColor: Color
    var cardioColor: Color
    var backgroundColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.accessibilityIdentifier = "bodyMap3DView"
        scnView.backgroundColor = UIColor(backgroundColor)
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false

        let scene = Self.loadBodyScene()
        scnView.scene = scene

        let coordinator = context.coordinator
        coordinator.indexNodes(in: scene)

        let lookAtNode = SCNNode()
        lookAtNode.position = SCNVector3(0, 0.92, 0)
        scene.rootNode.addChildNode(lookAtNode)
        coordinator.lookAtNode = lookAtNode

        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.05
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.92, isBackView ? -2.65 : 2.65)
        cameraNode.eulerAngles = SCNVector3(0, isBackView ? Float.pi : 0, 0)
        scene.rootNode.addChildNode(cameraNode)
        coordinator.cameraNode = cameraNode

        scnView.pointOfView = cameraNode
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.target = SCNVector3(0, 0.92, 0)
        scnView.defaultCameraController.inertiaEnabled = true
        scnView.defaultCameraController.minimumVerticalAngle = -45
        scnView.defaultCameraController.maximumVerticalAngle = 45

        Self.attachLighting(to: scene.rootNode)

        let tapRecognizer = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        scnView.addGestureRecognizer(tapRecognizer)

        coordinator.lastIsBackView = isBackView
        coordinator.lastResetTrigger = resetTrigger
        coordinator.applyMaterials(
            selectedRegion: selectedRegion,
            accentColor: accentColor,
            structuralColor: structuralColor,
            defaultMuscleColor: defaultMuscleColor,
            cardioColor: cardioColor
        )

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        scnView.backgroundColor = UIColor(backgroundColor)

        coordinator.applyMaterials(
            selectedRegion: selectedRegion,
            accentColor: accentColor,
            structuralColor: structuralColor,
            defaultMuscleColor: defaultMuscleColor,
            cardioColor: cardioColor
        )

        if coordinator.lastIsBackView != isBackView || coordinator.lastResetTrigger != resetTrigger {
            coordinator.lastIsBackView = isBackView
            coordinator.lastResetTrigger = resetTrigger

            if let cameraNode = coordinator.cameraNode {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.35
                scnView.pointOfView = cameraNode
                cameraNode.position = SCNVector3(0, 0.92, isBackView ? -2.65 : 2.65)
                cameraNode.eulerAngles = SCNVector3(0, isBackView ? Float.pi : 0, 0)
                scnView.defaultCameraController.target = SCNVector3(0, 0.92, 0)
                SCNTransaction.commit()
            }
        }
    }

    // MARK: - Scene Loading & Lighting

    nonisolated static func loadBodyScene(from explicitURL: URL? = nil) -> SCNScene {
        let resolvedURL: URL? = explicitURL ?? {
            let bundles: [Bundle] = [.main, Bundle(for: Coordinator.self)]
            for bundle in bundles {
                if let url = bundle.url(forResource: "human_body", withExtension: "obj")
                    ?? bundle.url(forResource: "human_body", withExtension: "obj", subdirectory: "Models3D") {
                    return url
                }
            }
            return nil
        }()

        guard let url = resolvedURL,
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return SCNScene()
        }

        var globalVertices: [SCNVector3] = []
        var globalNormals: [SCNVector3] = []
        globalVertices.reserveCapacity(2800)
        globalNormals.reserveCapacity(2800)

        struct GroupBuilder {
            let name: String
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [UInt32] = []
            var pairToLocal: [UInt64: UInt32] = [:]
        }

        var groups: [GroupBuilder] = []
        var currentGroup = GroupBuilder(name: "body")

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("o ") {
                if !currentGroup.indices.isEmpty {
                    groups.append(currentGroup)
                }
                let groupName = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentGroup = GroupBuilder(name: groupName)
            } else if line.hasPrefix("v ") {
                let parts = line.split(whereSeparator: \.isWhitespace)
                if parts.count >= 4,
                   let x = Float(parts[1]),
                   let y = Float(parts[2]),
                   let z = Float(parts[3]) {
                    globalVertices.append(SCNVector3(x, y, z))
                }
            } else if line.hasPrefix("vn ") {
                let parts = line.split(whereSeparator: \.isWhitespace)
                if parts.count >= 4,
                   let x = Float(parts[1]),
                   let y = Float(parts[2]),
                   let z = Float(parts[3]) {
                    globalNormals.append(SCNVector3(x, y, z))
                }
            } else if line.hasPrefix("f ") {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 4 else { continue }
                var faceLocalIndices: [UInt32] = []
                faceLocalIndices.reserveCapacity(parts.count - 1)

                for token in parts.dropFirst() {
                    let sub = token.split(separator: "/", omittingEmptySubsequences: false)
                    guard let vIdx1 = sub.first.flatMap({ Int($0) }),
                          vIdx1 >= 1, vIdx1 <= globalVertices.count else { continue }
                    let vnIdx1: Int
                    if sub.count >= 3, let parsedVN = Int(sub[2]), parsedVN >= 1, parsedVN <= globalNormals.count {
                        vnIdx1 = parsedVN
                    } else {
                        vnIdx1 = 0
                    }

                    let key = (UInt64(vIdx1) << 32) | UInt64(vnIdx1)
                    if let existing = currentGroup.pairToLocal[key] {
                        faceLocalIndices.append(existing)
                    } else {
                        let localIdx = UInt32(currentGroup.vertices.count)
                        currentGroup.vertices.append(globalVertices[vIdx1 - 1])
                        if vnIdx1 >= 1 {
                            currentGroup.normals.append(globalNormals[vnIdx1 - 1])
                        } else {
                            currentGroup.normals.append(SCNVector3(0, 0, 1))
                        }
                        currentGroup.pairToLocal[key] = localIdx
                        faceLocalIndices.append(localIdx)
                    }
                }

                if faceLocalIndices.count >= 3 {
                    for i in 1..<(faceLocalIndices.count - 1) {
                        currentGroup.indices.append(faceLocalIndices[0])
                        currentGroup.indices.append(faceLocalIndices[i])
                        currentGroup.indices.append(faceLocalIndices[i + 1])
                    }
                }
            }
        }
        if !currentGroup.indices.isEmpty {
            groups.append(currentGroup)
        }

        let scene = SCNScene()
        for group in groups {
            let vertexSource = SCNGeometrySource(vertices: group.vertices)
            let normalSource = SCNGeometrySource(normals: group.normals)
            let element = SCNGeometryElement(indices: group.indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.name = group.name
            scene.rootNode.addChildNode(node)
        }
        return scene
    }

    private static func attachLighting(to rootNode: SCNNode) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 450
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        let frontLight = SCNLight()
        frontLight.type = .directional
        frontLight.intensity = 820
        let frontNode = SCNNode()
        frontNode.light = frontLight
        frontNode.position = SCNVector3(0.4, 2.2, 2.5)
        frontNode.look(at: SCNVector3(0, 0.92, 0))
        rootNode.addChildNode(frontNode)

        let backLight = SCNLight()
        backLight.type = .directional
        backLight.intensity = 760
        let backNode = SCNNode()
        backNode.light = backLight
        backNode.position = SCNVector3(-0.4, 2.2, -2.5)
        backNode.look(at: SCNVector3(0, 0.92, 0))
        rootNode.addChildNode(backNode)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: BodyMap3DView
        var regionNodes: [BodyRegionID: [SCNNode]] = [:]
        var structuralNodes: [SCNNode] = []
        var cameraNode: SCNNode?
        var lookAtNode: SCNNode?
        var lastIsBackView = false
        var lastResetTrigger = 0

        init(parent: BodyMap3DView) {
            self.parent = parent
        }

        func indexNodes(in scene: SCNScene) {
            regionNodes.removeAll()
            structuralNodes.removeAll()

            scene.rootNode.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }

                // Clone SCNMaterial per node so highlighting one region never mutates siblings.
                geometry.materials = geometry.materials.map {
                    ($0.copy() as? SCNMaterial) ?? SCNMaterial()
                }
                if geometry.materials.isEmpty {
                    geometry.materials = [SCNMaterial()]
                }

                if let resolvedName = self.resolveGroupName(startingAt: node) {
                    if BodyRegionID.structuralNodeNames.contains(resolvedName) {
                        self.structuralNodes.append(node)
                    } else if let region = BodyRegionID(rawValue: resolvedName) {
                        self.regionNodes[region, default: []].append(node)
                    } else {
                        self.structuralNodes.append(node)
                    }
                } else {
                    self.structuralNodes.append(node)
                }
            }
        }

        func applyMaterials(
            selectedRegion: BodyRegionID?,
            accentColor: Color,
            structuralColor: Color,
            defaultMuscleColor: Color,
            cardioColor: Color
        ) {
            let accentUI = UIColor(accentColor)
            let structuralUI = UIColor(structuralColor)
            let muscleUI = UIColor(defaultMuscleColor)
            let cardioUI = UIColor(cardioColor)

            for node in structuralNodes {
                for material in node.geometry?.materials ?? [] {
                    material.lightingModel = .blinn
                    material.diffuse.contents = structuralUI
                    material.specular.contents = UIColor(white: 0.18, alpha: 1.0)
                    material.shininess = 0.15
                    material.emission.contents = UIColor.black
                }
            }

            for (region, nodes) in regionNodes {
                let isSelected = (selectedRegion == region)
                let baseColor = (region == .cardio) ? cardioUI : muscleUI
                for node in nodes {
                    for material in node.geometry?.materials ?? [] {
                        material.lightingModel = .blinn
                        material.diffuse.contents = isSelected ? accentUI : baseColor
                        material.specular.contents = UIColor(white: isSelected ? 0.45 : 0.25, alpha: 1.0)
                        material.shininess = isSelected ? 0.45 : 0.25
                        material.emission.contents = isSelected ? accentUI.withAlphaComponent(0.32) : UIColor.black
                    }
                }
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scnView = recognizer.view as? SCNView else { return }
            let point = recognizer.location(in: scnView)
            let hits = scnView.hitTest(
                point,
                options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]
            )
            guard let firstHit = hits.first else { return }
            guard let name = resolveGroupName(startingAt: firstHit.node) else { return }
            guard !BodyRegionID.structuralNodeNames.contains(name),
                  let region = BodyRegionID(rawValue: name) else {
                return
            }

            DispatchQueue.main.async {
                if self.parent.selectedRegion == region {
                    self.parent.selectedRegion = nil
                } else {
                    self.parent.selectedRegion = region
                }
            }
        }

        private func resolveGroupName(startingAt node: SCNNode) -> String? {
            var current: SCNNode? = node
            while let candidate = current {
                if let name = candidate.name, !name.isEmpty {
                    if BodyRegionID(rawValue: name) != nil || BodyRegionID.structuralNodeNames.contains(name) {
                        return name
                    }
                }
                current = candidate.parent
            }
            return nil
        }
    }
}
