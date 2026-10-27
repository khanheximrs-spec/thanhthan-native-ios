
private func createEnemy(index: Int, x: Float, z: Float) {
    let node = SCNNode()
    node.position = SCNVector3(x, 0, z)

    if let model = assassinTemplate?.clone() {
        node.addChildNode(model)
    } else {
        let shade = index.isMultiple(of: 2)
            ? UIColor(red: 0.62, green: 0.19, blue: 0.20, alpha: 1)
            : UIColor(red: 0.49, green: 0.27, blue: 0.64, alpha: 1)

        addShape(
            SCNCapsule(capRadius: 0.51, height: 1.5),
            color: shade,
            at: SCNVector3(0, 0.91, 0),
            to: node
        )

        addShape(
            SCNSphere(radius: 0.41),
            color: shade,
            at: SCNVector3(0, 1.78, 0),
            to: node
        )

        for xOffset: Float in [-0.25, 0.25] {
            addShape(
                SCConeCompat(height: 0.42),
                color: .lightGray,
                at: SCNVector3(xOffset, 2.13, 0),
                to: node
            )
        }
    }

    scene.rootNode.addChildNode(node)
    enemies.append(
        Enemy(
            node: node,
            home: SCNVector3(x, 0, z),
            health: 65 + index * 5
        )
    )
}
