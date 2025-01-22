import Foundation

@objcMembers
public class ATHttpUrlsPool: NSObject {
    private(set) var _urls: [String] = []
    
    private(set) var _index: Int = 0
    
    public var urls: [String] {
        return _urls
    }
    
    public var currentUrl: String {
        if _index < _urls.count {
            return _urls[_index]
        }
        return ""
    }

    public func add(_ urls: [String]) {
        _urls.append(contentsOf: urls)
    }
    
    public func update(_ urls: [String]) {
        _urls.removeAll()
        _urls.append(contentsOf: urls)
    }
    
    public func remove(_ urls: [String]) {
        _urls.removeAll { url in
            urls.contains(url)
        }
    }
    
    public func removeAll() {
        _urls.removeAll()
    }
    
    public func prev() {
        let count = _urls.count
        _index -= 1
        if _index < 0 {
            _index = count - 1
        }
    }
    
    public func next() {
        let count = _urls.count
        
        if count > 0 {
            _index += 1
            if _index >= count {
                _index = 0
            }
        } else {
            _index = 0
        }
    }
    
    public func selectIndex(_ index: Int) {
        if index >= 0 && index < _urls.count {
            _index = index
        }
    }
}
