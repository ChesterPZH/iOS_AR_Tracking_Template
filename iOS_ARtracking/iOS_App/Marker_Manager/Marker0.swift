//
//  Marker0.swift
//  iOS AR tracking
//
//  Brief: Consumes MainTracking.markerInfos off the main thread,
//  loads model once, and updates its transform when marker id=4 is visible.
//

import Foundation
import SceneKit
import simd
import ARKit
import Combine

final class Marker0: ObservableObject {
    static let shared = Marker0()

    private weak var sceneView: ARSCNView?

    private static let markerNodeName = "marker0Model"
    private static let modelScale: Float = 0.1
    private static let targetMarkerId = 4


    private let processingQueue = DispatchQueue(label: "com.iOS_ARtracking.marker0", qos: .userInitiated)

    private var modelNode: SCNNode?
    private var markerInfosCancellable: AnyCancellable?

    private init() {
        // 在后台队列订阅 MainTracking.shared.markerInfos
        markerInfosCancellable = MainTracking.shared.$markerInfos
            .receive(on: processingQueue)
            .sink { [weak self] infos in
                self?.process(markerInfos: infos)
            }
    }

    func attachSceneView(_ view: ARSCNView) {
        self.sceneView = view
    }

    /// 后台处理 markerInfos，必要时加载/更新模型；SceneKit 操作切回主线程。
    private func process(markerInfos: [MarkerInfo]) {
        guard let marker = markerInfos.first(where: { $0.id == Self.targetMarkerId }) else {
            // marker 不在视野：仅从场景移除节点，不释放缓存
            DispatchQueue.main.async { [weak self] in
                self?.modelNode?.removeFromParentNode()
            }
            return
        }

        // 已有模型节点：只更新变换（每次都要设 scale，否则 simdTransform 会覆盖掉）
        if let node = modelNode {
            let scale = Self.modelScale
            let transform = marker.homoMat
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let sceneView = self.sceneView,
                      let cameraNode = sceneView.pointOfView else { return }
                node.simdTransform = transform
                node.simdScale = SIMD3<Float>(repeating: scale)
                if node.parent != cameraNode {
                    cameraNode.addChildNode(node)
                }
            }
            return
        }

        // 无实例节点：从预加载的模板克隆（模板由 AssetLoader 在启动时加载）
        guard let template = AssetLoader.shared.model0TemplateNode else {
            // 预加载尚未完成，稍后再试
            return
        }

        let node = template.clone()
        node.name = Self.markerNodeName

        // 把 SceneKit 节点挂载 & 变换更新放到主线程（先设 transform，再设 scale，否则 scale 会被覆盖）
        let transform = marker.homoMat
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let sceneView = self.sceneView,
                  let cameraNode = sceneView.pointOfView else { return }
            self.modelNode = node
            node.simdTransform = transform
            node.simdScale = SIMD3<Float>(repeating: Self.modelScale)
            cameraNode.addChildNode(node)
        }
    }
}
