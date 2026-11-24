import SwiftUI
import UIKit
import SceneKit
import SceneKit.ModelIO
import ModelIO

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
        let lookConstraint = SCNLookAtConstraint(target: lookAtNode)
        lookConstraint.isGimbalLockEnabled = true
        cameraNode.constraints = [lookConstraint]
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
                scnView.defaultCameraController.target = SCNVector3(0, 0.92, 0)
                SCNTransaction.commit()
            }
        }
    }

    // MARK: - Scene Loading & Lighting

    private static func loadBodyScene() -> SCNScene {
        let bundles: [Bundle] = [.main, Bundle(for: Coordinator.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "human_body", withExtension: "obj")
                ?? bundle.url(forResource: "human_body", withExtension: "obj", subdirectory: "Models3D") {
                let asset = MDLAsset(url: url)
                return SCNScene(mdlAsset: asset)
            }
        }
        return SCNScene()
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
                    material.diffuse.contents = structuralUI
                    material.emission.contents = UIColor.black
                    material.roughness.contents = 0.72
                }
            }

            for (region, nodes) in regionNodes {
                let isSelected = (selectedRegion == region)
                let baseColor = (region == .cardio) ? cardioUI : muscleUI
                for node in nodes {
                    for material in node.geometry?.materials ?? [] {
                        material.diffuse.contents = isSelected ? accentUI : baseColor
                        material.emission.contents = isSelected ? accentUI.withAlphaComponent(0.32) : UIColor.black
                        material.roughness.contents = isSelected ? 0.35 : 0.55
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
