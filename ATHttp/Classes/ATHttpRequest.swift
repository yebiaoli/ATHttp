import Foundation
import HandyJSON
import JSONModel
import AnyCodable

@objc public enum ATHttpMethod: Int {
    case connect
    case delete
    case get
    case head
    case options
    case patch
    case post
    case put
    case trace
    
    public var value: String {
        switch self {
        case .connect:
            return "CONNECT"
        case .delete:
            return "DELETE"
        case .get:
            return "GET"
        case .head:
            return "HEAD"
        case .options:
            return "OPTIONS"
        case .patch:
            return "PATCH"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .trace:
            return "TRACE"
        }
    }
}

/// 参数类型
@objc public enum ATHttpParamsType: Int {
    /// 使用JSONSerialization来把参数字典编码为json, 一定会被编码到body中, 并且会设置Content-Type为application/json
    case json
    
    /// 根据参数编码的位置分为: querystring与form表单两种, 种类由Destination枚举控制
    case url
}

/// 参数编码的位置
@objc public enum ATHttpParamsDestination: Int {
    /// 有method决定(get, head, delete为urlquery, 其他为body)
    case methodDependent
    /// url query
    case queryString
    /// body
    case httpBody
}

/// JSON 格式
@objc public enum ATHttpParamsJSONFormat: Int {
    /// 默认类型, 压缩json格式
    case `default`
    /// 标准json格式
    case prettyPrinted
    /// ios11以上支持输出的json根据key排序
    /// case sortedKeys
}

//参数编码方式
@objc public enum ATHttpParamsEncodeStyle: Int {
    /// 对应alamofire的ParameterEncoding，ParameterEncoding只能编码字典数据
    case encoding
    
    /// ParameterEncoder，ParameterEncoder用来编码任意实现Encodable协议的数据类型，ParameterEncoder使用的是一个自己Alamofire自己实现的URLEncodedFormEncoder来进行表单数据编码，可以编码Date，Data等特殊数据
    case encoder
}

///ParameterEncoding
@objcMembers
public class ATHttpParamsEncoding: NSObject {
    public var encoding = ATHttpParamsType.url
    public var jsonFormat = ATHttpParamsJSONFormat.default
    /// encoding == .url 时有效
    public var destination = ATHttpParamsDestination.methodDependent
}

///ParameterEncoder
@objcMembers
public class ATHttpParamsEncoder: NSObject {
    public var encoder = ATHttpParamsType.json
    public var jsonFormat = ATHttpParamsJSONFormat.default
    public var destination = ATHttpParamsDestination.methodDependent
}

/// 请求参数配置
@objcMembers
public class ATHttpParamsConfig: NSObject {
    /// 编码方式
    public var style = ATHttpParamsEncodeStyle.encoding
    
    /// style == .encoding 有效
    public var encoding = ATHttpParamsEncoding.init()
    
    /// style == .encoder 有效
    public var encoder = ATHttpParamsEncoder.init()
}

@objcMembers
public class ATHttpRequestExt: NSObject {
    public var name: String = ""
    public var tryIndex: Int = 0
    public var tryCount: Int = 1
    
    public var disableRetryRequestInterceptor = false
    public var disableRequestInterceptor = false
    public var disableResponseSuccessInterceptor = false
    public var disableResponseFailureInterceptor = false
    
    public var jsonModelClass: JSONModel.Type = ATHttpJsonDictModel.self //支持自定义，用来处理data为数组的情况ATHttpJsonArrayModel
    public var jsonModelSuccess: ((_ request: ATHttpRequest, _ response: [String: Any]?, _ jsonModel: ATHttpJsonModel?) -> Void)?
    
    //***兼容旧逻辑***   成功回调，不检查状态码;　　如果设置了将不走success, jsonModelSuccess, logicError
    public var unCheckStatusSuccess: ((_ request: ATHttpRequest, _ response: [String: Any]?) -> Void)?
    //***兼容旧逻辑***   JSONModel 成功回调，不检查状态码, 如果设置了将不走success, jsonModelSuccess, logicError
    public var unCheckStatusJsonModelSuccess: ((_ request: ATHttpRequest, _ response: [String: Any]?, _ jsonModel: ATHttpJsonModel?) -> Void)?
    
    public var requestHeaders: [String: String]?  //http的请求头
    public var responseHeaders: [String: String]? //http的响应头
    public var statusCode: Int = 0 //http的响应状态码（不是数据状态码）
    
    func canSendRequest() -> Bool {
        return tryIndex < tryCount
    }
    
    func incrTryTimes() {
        tryIndex += 1
    }
}

@objcMembers
public class ATHttpEncoderParams: NSObject {
    private var data:Any?
    public static func create(data:Any?) -> ATHttpEncoderParams {
        return ATHttpEncoderParams.init(data: data)
    }
    public init(data:Any?) {
        self.data = data
    }
    internal var params:AnyEncodable? {
        if let data = self.data {
            return AnyEncodable(data)
        }
        return nil
    }
}

@objcMembers
public class ATHttpRequest: NSObject {
    public var baseUrl: String?
    public var api: String = ""
    public var url: String? // url === baseUrl + api, 如果url为空，则用baseUrl + api
    public var method: ATHttpMethod = .get
    public var headers: [String: String] = [:] //接口请求头
    
    /// 参数配置，主要用来配置参数编码方式，⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️ 注意: paramsConfig.style == .encoder　没验证过
    public var paramsConfig = ATHttpParamsConfig.init()
    
    //paramsConfig.style == .encoding 时有效
    public var params: [String: Any] = [:]

    //paramsConfig.style == .encoder 时有效 ⚠️⚠️⚠️⚠️⚠️⚠️ 注意: 没验证过
    public var encoderParams:ATHttpEncoderParams?
    
    public var timeout: TimeInterval = 20
    public var uploadTimeout: TimeInterval = 60
    public var downloadTimeout: TimeInterval = 20
    public var shouldHandlefCookies = true
    
    public let ext = ATHttpRequestExt()
    
    public var success: ((_ request: ATHttpRequest, _ response: [String: Any]?) -> Void)?
    
    //网络错误回调：指接口请求失败（网络异常或状态码异常），如果没有设置了logicError，发生状态码异常后将会走failure回调
    public var failure: ((_ request: ATHttpRequest, _ error: Error?) -> Void)?
    //请求完成
    public var finish: ((_ request: ATHttpRequest) -> Void)?
    //逻辑错误回调：指接口请求成功，但接口状态码异常;　如果设置了logicError，发生状态码异常后将不会再走failure回调
    public var logicError: ((_ request: ATHttpRequest, _ response: [String: Any]?, _ error: Error?) -> Void)?
    
    public var uploadProgress: ((_ request: ATHttpRequest, _ progress: Progress) -> Void)?
    public var downloadProgress: ((_ request: ATHttpRequest, _ progress: Progress) -> Void)?

    init(_ method: ATHttpMethod = .get) {
        self.method = method
    }
    
    public func setHeader(_ value: String, forKey key: String) {
        headers[key] = value
    }

    public func removeHeader(forKey key: String) {
        headers.removeValue(forKey: key)
    }
    
//    public func setParam(_ value: Any, forKey key: String) {
//        if paramsConfig.style == .encoding {
//            params[key] = value
//        }
//    }
//
//    public func removeParam(key: String) {
//        if paramsConfig.style == .encoding {
//            params.removeValue(forKey: key)
//        }
//    }
    
    public var fullUrl: String {
        if let _url = url {
            return _url
        }
        if let _baseUrl = baseUrl {
            if api.hasPrefix("/") {
                return "\(_baseUrl)\(api)"
            } else {
                return "\(_baseUrl)/\(api)"
            }
        }
        return api
    }
}

public extension ATHttpRequest {
    static var get: ATHttpRequest {
        return ATHttpRequest()
    }
    
    static var post: ATHttpRequest {
        let request = ATHttpRequest(.post)
        request.paramsConfig.encoding.encoding = .json
        return request
    }
    
    static var delete: ATHttpRequest {
        return ATHttpRequest(.delete)
    }
    
    static var put: ATHttpRequest {
        let request = ATHttpRequest(.put)
        request.paramsConfig.encoding.encoding = .json
        return request
    }
}

public extension ATHttpRequest {
    func desc1() -> String {
        return """
        ### ATHttpRequest ###
        .name:\(ext.name)
        .url:\(fullUrl)
        .method:\(method.value)
        .params:\(params)
        """
    }
    
    func desc2() -> String {
        return """
        ### ATHttpRequest ###
        .name:\(ext.name)
        .tryIndex:\(ext.tryIndex)
        .tryCount:\(ext.tryCount)
        .url:\(fullUrl)
        .method:\(method.value)
        .headers:\(headers)
        .params:\(params)
        """
    }
    
    func desc3() -> String {
        return """
        ### ATHttpRequest ###
        .name:\(ext.name)
        .url:\(fullUrl)
        .method:\(method.value)
        .headers:\(headers as NSDictionary)
        .params:\(params as NSDictionary)
        """
    }
}
