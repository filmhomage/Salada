//
//  Object.swift
//  Salada
//
//  Created by nori on 2017/05/29.
//  Copyright © 2017年 Stamp. All rights reserved.
//

import Firebase

open class Object: Base, Referenceable {

    // MARK: -

    /// Date the Object was created
    @objc private(set) var createdAt: Date

    /// Date when Object was updated
    @objc private(set) var updatedAt: Date

    /// Object monitors the properties as they are saved.
    private(set) var isObserved: Bool = false

    /// If all File savings do not end within this time, save will be canceled. default 20 seconds.
    open var timeout: Int {
        return SaladaApp.shared.timeout
    }

    /// If propery is set with String, its property will not be written to Firebase.
    open var ignore: [String] {
        return []
    }

    /// It is Qeueu of File upload.
    public let uploadQueue: DispatchQueue = DispatchQueue(label: "salada.upload.queue")

    /// The IndexKey of the Object.
    @objc public var id: String

    /// A reference to Object.
    private(set) var ref: DatabaseReference

    ///
    private var hasFiles: Bool {
        let mirror = Mirror(reflecting: self)
        for (_, child) in mirror.children.enumerated() {
            if let key: String = child.label {
                switch ValueType(key: key, value: child.value) {
                case .file(_, _): return true
                default: break
                }
                return true
            }
        }
        return false
    }

    // MARK: - Initialize

    public override init() {
        self.createdAt = Date()
        self.updatedAt = Date()
        self.ref = type(of: self).databaseRef.childByAutoId()
        self.id = self.ref.key
    }

    convenience required public init?(snapshot: DataSnapshot) {
        self.init()
        _setSnapshot(snapshot)
    }

    convenience required public init?(id: String) {
        self.init()
        self.id = id
        self.ref = type(of: self).databaseRef.child(id)
    }

    // MARK: - Encode, Decode

    /// Model -> Firebase
    open func encode(_ key: String, value: Any?) -> Any? {
        return nil
    }

    /// Snapshot -> Model
    open func decode(_ key: String, value: Any?) -> Any? {
        return nil
    }

    public var value: [AnyHashable: Any] {
        let mirror = Mirror(reflecting: self)
        var object: [AnyHashable: Any] = [:]
        mirror.children.forEach { (key, value) in
            if let key: String = key {
                if !self.ignore.contains(key) {
                    if let newValue: Any = self.encode(key, value: value) {
                        object[key] = newValue
                        return
                    }
                    switch ValueType(key: key, value: value) {
                    case .bool      (let key, let value):       object[key] = value
                    case .int       (let key, let value):       object[key] = value
                    case .double    (let key, let value):       object[key] = value
                    case .float     (let key, let value):       object[key] = value
                    case .string    (let key, let value):       object[key] = value
                    case .url       (let key, let value, _):    object[key] = value
                    case .date      (let key, let value, _):    object[key] = value
                    case .array     (let key, let value):       object[key] = value
                    case .set       (let key, let value, _):    object[key] = value
                    case .file      (let key, let value):
                        object[key] = value.value
                        value.owner = self
                        value.keyPath = key
                    case .nestedString(let key, let value):     object[key] = value
                    case .nestedInt(let key, let value):        object[key] = value
                    case .object(let key, let value):           object[key] = value
                    case .null: break
                    }
                }
            }
        }
        return object
    }

    // MARK: - Snapshot

    public var snapshot: DataSnapshot? {
        didSet {
            if let snapshot: DataSnapshot = snapshot {

                self.ref = snapshot.ref
                self.id = snapshot.key

                guard let snapshot: [String: Any] = snapshot.value as? [String: Any] else { return }

                let createdAt: Double = snapshot["_createdAt"] as! Double
                let updatedAt: Double = snapshot["_updatedAt"] as! Double

                let createdAtTimestamp: TimeInterval = (createdAt / 1000)
                let updatedAtTimestamp: TimeInterval = (updatedAt / 1000)

                self.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
                self.updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp)

                Mirror(reflecting: self).children.forEach { (key, value) in
                    if let key: String = key {
                        if !self.ignore.contains(key) {
                            if let _: Any = self.decode(key, value: snapshot[key]) {
                                self.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
                                return
                            }
                            let mirror: Mirror = Mirror(reflecting: value)
                            switch ValueType(key: key, mirror: mirror, snapshot: snapshot) {
                            case .bool(let key, let value): self.setValue(value, forKey: key)
                            case .int(let key, let value): self.setValue(value, forKey: key)
                            case .float(let key, let value): self.setValue(value, forKey: key)
                            case .double(let key, let value): self.setValue(value, forKey: key)
                            case .string(let key, let value): self.setValue(value, forKey: key)
                            case .url(let key, _, let value): self.setValue(value, forKey: key)
                            case .date(let key, _, let value): self.setValue(value, forKey: key)
                            case .array(let key, let value): self.setValue(value, forKey: key)
                            case .set(let key, _, let value): self.setValue(value, forKey: key)
                            case .file(let key, let file):
                                file.owner = self
                                file.keyPath = key
                                self.setValue(file, forKey: key)
                            case .nestedString(let key, let value): self.setValue(value, forKey: key)
                            case .nestedInt(let key, let value): self.setValue(value, forKey: key)
                            case .object(let key, let value): self.setValue(value, forKey: key)
                            case .null: break
                            }
                            self.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
                        }
                    }
                }
                self.isObserved = true
            }
        }
    }

    fileprivate func _setSnapshot(_ snapshot: DataSnapshot) {
        self.snapshot = snapshot
        self.ref.keepSynced(true)
    }

    // MARK: - KVO

    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        guard let keyPath: String = keyPath else {
            super.observeValue(forKeyPath: nil, of: object, change: change, context: context)
            return
        }

        guard let object: NSObject = object as? NSObject else {
            super.observeValue(forKeyPath: keyPath, of: nil, change: change, context: context)
            return
        }

        let keys: [String] = Mirror(reflecting: self).children.flatMap({ return $0.label })
        if keys.contains(keyPath) {

            if let value: Any = object.value(forKey: keyPath) as Any? {

                // File
                if let _: File = value as? File {
                    if let change: [NSKeyValueChangeKey: Any] = change as [NSKeyValueChangeKey: Any]? {
                        guard let new: File = change[.newKey] as? File else {
                            if let old: File = change[.oldKey] as? File {
                                old.owner = self
                                old.keyPath = keyPath
                                old.remove()
                            }
                            return
                        }
                        if let old: File = change[.oldKey] as? File {
                            if old.name != new.name {
                                new.owner = self
                                new.keyPath = keyPath
                                old.owner = self
                                old.keyPath = keyPath
                            }
                        } else {
                            new.owner = self
                            new.keyPath = keyPath
                        }
                    }
                    return
                }

                // Set
                if let _: Set<String> = value as? Set<String> {
                    if let change: [NSKeyValueChangeKey: Any] = change as [NSKeyValueChangeKey: Any]? {

                        let new: Set<String> = change[.newKey] as! Set<String>
                        let old: Set<String> = change[.oldKey] as! Set<String>

                        // Added
                        new.subtracting(old).forEach({ (id) in
                            updateValue(keyPath, child: id, value: true)
                        })

                        // Remove
                        old.subtracting(new).forEach({ (id) in
                            updateValue(keyPath, child: id, value: nil)
                        })

                    }
                    return
                }

                if let values: [Any] = value as? [Any] {
                    if values.isEmpty { return }
                    updateValue(keyPath, child: nil, value: value)
                } else if let value: String = value as? String {
                    updateValue(keyPath, child: nil, value: value)
                } else if let value: Date = value as? Date {
                    updateValue(keyPath, child: nil, value: value.timeIntervalSince1970)
                } else {
                    updateValue(keyPath, child: nil, value: value)
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    /** 
     Update the data on Firebase.
     When this function is called, updatedAt of Object is updated at the same time.
     
     - parameter keyPath: Target key path
     - parameter child: Target child
     - parameter value: Save to value. If you enter nil, the data will be deleted.
     */
    internal func updateValue(_ keyPath: String, child: String?, value: Any?) {
        let reference: DatabaseReference = self.ref
        let timestamp: [AnyHashable : Any] = ServerValue.timestamp() as [AnyHashable : Any]

        if let value: Any = value {
            var path: String = keyPath
            if let child: String = child {
                path = "\(keyPath)/\(child)"
            }
            reference.updateChildValues([path: value, "_updatedAt": timestamp], withCompletionBlock: {_,_ in 
                // Nothing
            })
        } else {
            if let childKey: String = child {
                reference.child(keyPath).child(childKey).removeValue()
            }
        }
    }

    // MARK: - Save

    @discardableResult
    public func save() -> [String: StorageUploadTask] {
        return self.save(nil)
    }

    /**
     Save the new Object to Firebase. Save will fail in the off-line.
     - parameter completion: If successful reference will return. An error will return if it fails.
     */
    @discardableResult
    public func save(_ block: ((DatabaseReference?, Error?) -> Void)?) -> [String: StorageUploadTask] {

        // Is Persistenced
        if SaladaApp.isPersistenced {
            if let block = block {
//                debugPrint("<Warning> [Salada.Object] Firebase is configured to be persistent. When this process is executed offline and the application is terminated, the processing in Completion will be thinned. Please use `TransactionSave` to fail processing when offline.")
                return self._transactionSave(block)
            }
            return self._save(nil)
        } else {
            return self._save(block)
        }
    }

    private func _save(_ block: ((DatabaseReference?, Error?) -> Void)?) -> [String: StorageUploadTask] {
        let ref: DatabaseReference = self.ref
        if self.hasFiles {
            return self.saveFiles(block: { (error) in
                if let error = error {
                    block?(ref, error)
                    return
                }
                var value: [AnyHashable: Any] = self.value
                let timestamp: [AnyHashable : Any] = ServerValue.timestamp() as [AnyHashable : Any]
                value["_createdAt"] = timestamp
                value["_updatedAt"] = timestamp
                ref.setValue(value, withCompletionBlock: { (error, ref) in
                    ref.observeSingleEvent(of: .value, with: { (snapshot) in
                        self.snapshot = snapshot
                        block?(ref, error)
                    })
                })
            })
        } else {
            var value: [AnyHashable: Any] = self.value
            let timestamp: [AnyHashable : Any] = ServerValue.timestamp() as [AnyHashable : Any]
            value["_createdAt"] = timestamp
            value["_updatedAt"] = timestamp
            ref.setValue(value, withCompletionBlock: { (error, ref) in
                ref.observeSingleEvent(of: .value, with: { (snapshot) in
                    self.snapshot = snapshot
                    block?(ref, error)
                })
            })
            return [:]
        }
    }

    // MARK: - Transaction

    /**
     Save failing when offline
     */
    public func transactionSave(_ block: ((DatabaseReference?, Error?) -> Void)?) -> [String: StorageUploadTask] {
        return self._transactionSave(block)
    }

    private func _transactionSave(_ block: ((DatabaseReference?, Error?) -> Void)?) -> [String: StorageUploadTask] {
        let ref: DatabaseReference = self.ref
        var value: [AnyHashable: Any] = self.value
        let timestamp: [AnyHashable : Any] = ServerValue.timestamp() as [AnyHashable : Any]
        value["_createdAt"] = timestamp
        value["_updatedAt"] = timestamp
        if self.hasFiles {
            return self.saveFiles(block: { (error) in
                if let error = error {
                    block?(nil, error)
                    return
                }
                ref.runTransactionBlock({ (currentData) -> TransactionResult in
                    currentData.value = value
                    return .success(withValue: currentData)
                }, andCompletionBlock: { (error, committed, snapshot) in
                    if committed {
                        ref.observeSingleEvent(of: .value, with: { (snapshot) in
                            self.snapshot = snapshot
                            block?(snapshot.ref, nil)
                        })
                    } else {
                        let error: ObjectError = ObjectError(kind: .offlineTransaction, description: "A transaction can not be executed when it is offline.")
                        block?(nil, error)
                    }
                }, withLocalEvents: false)
            })
        } else {
            ref.runTransactionBlock({ (currentData) -> TransactionResult in
                currentData.value = value
                return .success(withValue: currentData)
            }, andCompletionBlock: { (error, committed, snapshot) in
                if committed {
                    block?(snapshot?.ref, nil)
                } else {
                    let error: ObjectError = ObjectError(kind: .offlineTransaction, description: "A transaction can not be executed when it is offline.")
                    block?(nil, error)
                }
            }, withLocalEvents: false)
            return [:]
        }
    }

//    /**
//     Set new value. Save will fail in the off-line.
//     - parameter key:
//     - parameter value:
//     - parameter completion: If successful reference will return. An error will return if it fails.
//     */
//    private var transactionBlock: ((DatabaseReference?, Error?) -> Void)?
//
//    public func transaction(key: String, value: Any, completion: ((DatabaseReference?, Error?) -> Void)?) {
//        self.transactionBlock = completion
//        self.setValue(value, forKey: key)
//    }

    // MARK: - Remove

    public func remove() {
        self.ref.removeValue()
        self.ref.removeAllObservers()
    }

    // MARK: - File

    /**
     Save the file set in the object.
     
     - parameter block: If saving succeeds or fails, this callback will be called.
     - returns: Returns the StorageUploadTask set in the property.
    */
    private func saveFiles(block: ((Error?) -> Void)?) -> [String: StorageUploadTask] {

        let group: DispatchGroup = DispatchGroup()
        var uploadTasks: [String: StorageUploadTask] = [:]

        var hasError: Error? = nil

        for (_, child) in Mirror(reflecting: self).children.enumerated() {

            guard let key: String = child.label else { break }
            if self.ignore.contains(key) { break }
            let value = child.value

            let mirror: Mirror = Mirror(reflecting: value)
            let subjectType: Any.Type = mirror.subjectType
            if subjectType == File?.self || subjectType == File.self {
                if let file: File = value as? File {
                    file.owner = self
                    file.keyPath = key
                    group.enter()
                    if let task: StorageUploadTask = file.save(key, completion: { (meta, error) in
                        if let error: Error = error {
                            hasError = error
                            uploadTasks.forEach({ (_, task) in
                                task.cancel()
                            })
                            return
                        }
                        group.leave()
                    }) {
                        uploadTasks[key] = task
                    }
                }
            }
        }

        uploadQueue.async {
            group.notify(queue: DispatchQueue.main, execute: {
                block?(hasError)
            })
            switch group.wait(timeout: .now() + .seconds(self.timeout)) {
            case .success: break
            case .timedOut:
                uploadTasks.forEach({ (_, task) in
                    task.cancel()
                })
                let error: ObjectError = ObjectError(kind: .timeout, description: "Save the file timeout.")
                DispatchQueue.main.async {
                    block?(error)
                }
            }
        }
        return uploadTasks
    }

    /**
     Remove the observer.
     */
    public class func removeObserver(_ key: String, with handle: UInt) {
        self.databaseRef.child(key).removeObserver(withHandle: handle)
    }

    /**
     Remove the observer.
     */
    public class func removeObserver(with handle: UInt) {
        self.databaseRef.removeObserver(withHandle: handle)
    }

    // MARK: - deinit

    deinit {
        if self.isObserved {
            Mirror(reflecting: self).children.forEach { (key, value) in
                if let key: String = key {
                    if !self.ignore.contains(key) {
                        self.removeObserver(self, forKeyPath: key)
                    }
                }
            }
        }
    }

    // MARK: -

    override open var description: String {

        let base: String =
        "  key: \(self.id)\n" +
        "  createdAt: \(self.createdAt)\n" +
        "  updatedAt: \(self.updatedAt)\n"

        let values: String = Mirror(reflecting: self).children.reduce(base) { (result, children) -> String in
            guard let label: String = children.0 else {
                return result
            }
            return result + "  \(label): \(children.1)\n"
        }
        let _self: String = String(describing: Mirror(reflecting: self).subjectType).components(separatedBy: ".").first!
        return "\(_self) {\n\(values)}"
    }

    public subscript(key: String) -> Any? {
        get {
            return self.value(forKey: key)
        }
        set(newValue) {
            self.setValue(newValue, forKey: key)
        }
    }
}

extension Object {
    open override var hashValue: Int {
        return self.id.hash
    }
}

public func == (lhs: Object, rhs: Object) -> Bool {
    return lhs.id == rhs.id
}

// MARK: -

extension Collection where Iterator.Element == String {
    func toKeys() -> [String: Bool] {
        if self.isEmpty { return [:] }
        var keys: [String: Bool] = [:]
        self.forEach { (object) in
            keys[object] = true
        }
        return keys
    }
}

extension Sequence where Iterator.Element: Object {
    /// Return an `Array` containing the sorted elements of `source`
    /// using criteria stored in a NSSortDescriptors array.

    public func sort(sortDescriptors theSortDescs: [NSSortDescriptor]) -> [Self.Iterator.Element] {
        return sorted {
            for sortDesc in theSortDescs {
                switch sortDesc.compare($0, to: $1) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }
}