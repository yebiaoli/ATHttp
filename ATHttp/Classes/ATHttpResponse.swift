import Foundation
import HandyJSON
import JSONModel

open class ATHttpHandyJsonResponse<T>: HandyJSON {
    public var status: Int?
    
    public var message: String?
    
    public var data: T?
    
    public required init() {}
    
    open func mapping(mapper: HelpingMapper) {
        mapper <<< self.data <-- ["data", "client", "devices"]
    }
}

@objcMembers
open class ATHttpJsonModel: JSONModel {
    public var status: Int = 200
    
    public var message: String?
    
    override open class func propertyIsOptional(_ propertyName: String!) -> Bool {
        return true
    }
    
    open func rsData() -> Any? {
        return nil
    }
}

@objcMembers
open class ATHttpJsonDictModel: ATHttpJsonModel {
    public var data: [String: Any]?
    open override func rsData() -> Any? {
        return data
    }
}

@objcMembers
open class ATHttpJsonArrayModel: ATHttpJsonModel {
    public var data: Array<Any>?
    open override func rsData() -> Any? {
        return data
    }
}
