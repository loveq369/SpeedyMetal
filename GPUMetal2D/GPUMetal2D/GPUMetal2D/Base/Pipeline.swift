//
//  Pipeline.swift
//  GPUMetal2D
//
//  Created by Quinn on 2018/12/1.
//  Copyright © 2018 Quinn. All rights reserved.
//

import Foundation

public protocol ImageSource {
    var targets: TargetContainer { get }
    func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt)
}

public protocol ImageConsumer: AnyObject {
    var maximumInputs: UInt { get }
    var sources: SourceContainer { get }
    
    func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt)
}

public protocol ImageProcessingOperation: ImageConsumer, ImageSource {
}

infix operator --> : AdditionPrecedence
@discardableResult public func --><T: ImageConsumer>(source: ImageSource, destination: T) -> T {
    source.addTarget(destination)
    return destination
}

// MARK: -
// MARK: Extensions and supporting types
public extension ImageSource {
    public func addTarget(_ target: ImageConsumer, atTargetIndex: UInt? = nil) {
        if let targetIndex = atTargetIndex {
            target.setSource(self, atIndex: targetIndex)
            targets.append(target, indexAtTarget: targetIndex)
            transmitPreviousImage(to: target, atIndex: targetIndex)
        } else if let indexAtTarget = target.addSource(self) {
            targets.append(target, indexAtTarget: indexAtTarget)
            transmitPreviousImage(to: target, atIndex: indexAtTarget)
        } else {
            debugPrint("Warning: tried to add target beyond target's input capacity")
        }
    }
    
    public func removeAllTargets() {
        for (target, index) in targets {
            target.removeSourceAtIndex(index)
        }
        targets.removeAll()
    }
    
    public func updateTargetsWithTexture(_ texture: Texture) {
        for (target, index) in targets {
            target.newTextureAvailable(texture, fromSourceIndex: index)
        }
    }
}

public extension ImageConsumer {
    public func addSource(_ source: ImageSource) -> UInt? {
        return sources.append(source, maximumInputs: maximumInputs)
    }
    
    public func setSource(_ source: ImageSource, atIndex: UInt) {
        _ = sources.insert(source, atIndex: atIndex, maximumInputs: maximumInputs)
    }
    
    public func removeSourceAtIndex(_ index: UInt) {
        sources.removeAtIndex(index)
    }
}

class WeakImageConsumer {
    weak var value: ImageConsumer?
    let indexAtTarget: UInt
    init (value: ImageConsumer, indexAtTarget: UInt) {
        self.indexAtTarget = indexAtTarget
        self.value = value
    }
}

public class TargetContainer: Sequence {
    var targets = [WeakImageConsumer]()
    var count: Int { get {return targets.count}}
    let dispatchQueue = DispatchQueue(label: "com.colin.MetalImageProcessing.targetContainerQueue",
                                      attributes: [])
    
    public init() {
    }
    
    public func append(_ target: ImageConsumer, indexAtTarget: UInt) {
        // TODO: Don't allow the addition of a target more than once
        dispatchQueue.async{
            self.targets.append(WeakImageConsumer(value: target, indexAtTarget: indexAtTarget))
        }
    }
    
    public func makeIterator() -> AnyIterator<(ImageConsumer, UInt)> {
        var index = 0
        
        return AnyIterator { () -> (ImageConsumer, UInt)? in
            return self.dispatchQueue.sync {
                if (index >= self.targets.count) {
                    return nil
                }
                
                while (self.targets[index].value == nil) {
                    self.targets.remove(at: index)
                    if (index >= self.targets.count) {
                        return nil
                    }
                }
                
                index += 1
                return (self.targets[index - 1].value!, self.targets[index - 1].indexAtTarget)
            }
        }
    }
    
    public func removeAll() {
        dispatchQueue.async {
            self.targets.removeAll()
        }
    }
}

public class SourceContainer {
    var sources: [UInt:ImageSource] = [:]
    
    public init() {
    }
    
    public func append(_ source: ImageSource, maximumInputs: UInt) -> UInt? {
        var currentIndex: UInt = 0
        while currentIndex < maximumInputs {
            if (sources[currentIndex] == nil) {
                sources[currentIndex] = source
                return currentIndex
            }
            currentIndex += 1
        }
        
        return nil
    }
    
    public func insert(_ source: ImageSource, atIndex: UInt, maximumInputs: UInt) -> UInt {
        guard (atIndex < maximumInputs) else {
            fatalError("ERROR: Attempted to set a source beyond the maximum number of inputs on this operation")
        }
        sources[atIndex] = source
        return atIndex
    }
    
    public func removeAtIndex(_ index: UInt) {
        sources[index] = nil
    }
}
