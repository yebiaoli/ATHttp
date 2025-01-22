import Alamofire
import Foundation

@objcMembers
public class ATHttpTask: NSObject {
    private var request: Request?
    
    init(_ request: Request?) {
        self.request = request
    }
    
    public func cancel() {
        request?.cancel()
    }
}

public extension ATHttpTask {
    func addToTaskBox(_ taskBox: ATHttpTaskBox) {
        taskBox.addTask(self)
    }
}

@objcMembers
public class ATHttpTaskBox: NSObject {
    var tasks = NSHashTable<ATHttpTask>.weakObjects()
    
    deinit {
        removeAll()
    }
    
    public func addTask(_ task: ATHttpTask) {
        tasks.add(task)
    }
    
    public func removeTask(_ task: ATHttpTask) {
        tasks.remove(task)
    }
    
    public func removeAll() {
        tasks.allObjects.forEach { task in
            task.cancel()
        }
    }
}
