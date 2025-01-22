import Alamofire
import Foundation
import HandyJSON
import ATMultiBlocks

//@objcMembers
//public class ATHttpNotification: NSObject{
//    public static let NetworkStatusDidChange:String = "NetworkStatusDidChange"
//}

@objc public enum ATHttpNetworkStatus: Int {
    case unknown
    case notReachable
    case ethernetOrWiFi
    case cellular
    
    public var isReachable: Bool {
        return self == .ethernetOrWiFi || self == .cellular
    }
}

@objc public enum ATHttpFileType: Int {
    case none
    case image
    case video
    case audio
    
    var value: String {
        switch self {
        case .image:
            return "image"
        case .video:
            return "video"
        case .audio:
            return "audio"
        default:
            return ""
        }
    }
}

public typealias ATHttpNetworkStatusListener = (_ status: ATHttpNetworkStatus) -> Void
public typealias ATHttpRetryRequestHandler = (_ request: ATHttpRequest) -> Void
public typealias ATHttpRequestHandler = (_ request: ATHttpRequest) -> Void
public typealias ATHttpResponseSuccessHandler = (_ request: ATHttpRequest, _ response: [String: Any]?) -> Error?
public typealias ATHttpResponseFailureHandler = (_ request: ATHttpRequest, _ error: Error) -> Error?

@objcMembers
public class ATHttpClient: NSObject {
    public static let client = ATHttpClient()
    
    private static var _networkListener: ATHttpNetworkStatusListener?
    
    public static var networkStatus: ATHttpNetworkStatus {
        switch NetworkReachabilityManager.default!.status {
        case .notReachable:
            return .notReachable
                
        case .reachable(.cellular):
            return .cellular
                
        case .reachable(.ethernetOrWiFi):
            return .ethernetOrWiFi
                
        case .unknown:
            break
        }
            
        return .unknown
    }
    
    public static var isReachable: Bool {
        return networkStatus.isReachable
    }
    
    public static func initNetworkListening(_ handler: ATHttpNetworkStatusListener?) {
        _networkListener = handler
        
        NetworkReachabilityManager.default!.startListening(onUpdatePerforming: { _ in
            _networkListener?(networkStatus)
//            NotificationCenter.default.post(name: NSNotification.Name(rawValue: ATHttpNotification.NetworkStatusDidChange), object: nil, userInfo: nil)
            multiBlocks.call("networkStateChange",data: networkStatus)
        })
    }
    
    //添加网络监听
    public static func addNetworkListening(forOwner owner:AnyObject, handler: @escaping ATHttpNetworkStatusListener) {
        if _networkListener == nil {
            initNetworkListening(nil)
        }
        multiBlocks.register("networkStateChange", owner: owner) { data in
            if let status:ATHttpNetworkStatus = data as? ATHttpNetworkStatus {
                handler(status)
            }
        }
    }
    //移除网络监听(可以不手动移除，owner为弱引用)
    public static func removeNetworkListening(forOwner owner:AnyObject) {
        multiBlocks.remove("networkStateChange", owner: owner)
        if _networkListener == nil {
            initNetworkListening(nil)
        }
    }
    
    private static var multiBlocks:ATMultiBlocks = ATMultiBlocks.init()
    
    
    public var retryRequestInterceptor: ATHttpRetryRequestHandler?
    public var requestInterceptor: ATHttpRequestHandler?
    public var responseSuccessInterceptor: ATHttpResponseSuccessHandler?
    public var responseFailureInterceptor: ATHttpResponseFailureHandler?
    public let baseUrlsPool = ATHttpUrlsPool()
    
    private func paramsEncoding(_ encoding: ATHttpParamsEncoding) -> ParameterEncoding {
        switch encoding.encoding {
        case .json:
            switch encoding.jsonFormat {
            case .default:
                return JSONEncoding.default
            case .prettyPrinted:
                return JSONEncoding.prettyPrinted
            }
        case .url:
            switch encoding.destination {
            case .methodDependent:
                return URLEncoding.default
            case .queryString:
                return URLEncoding.queryString
            case .httpBody:
                return URLEncoding.httpBody
            }
        }
    }
    
    private func paramsEncoder(_ encoder: ATHttpParamsEncoder) -> ParameterEncoder {
        switch encoder.encoder {
        case .json:
            switch encoder.jsonFormat {
            case .default:
                return JSONParameterEncoder.default
            case .prettyPrinted:
                return JSONParameterEncoder.prettyPrinted
            }
        case .url:
            switch encoder.destination {
            case .methodDependent:
                return URLEncodedFormParameterEncoder.default // == URLEncodedFormParameterEncoder(destination: .methodDependent)
            case .queryString:
                return URLEncodedFormParameterEncoder(destination: .queryString)
            case .httpBody:
                return URLEncodedFormParameterEncoder(destination: .httpBody)
            }
        }
    }
    
    @discardableResult
    private func _dataRequest(_ request: ATHttpRequest) -> DataRequest? {
        if !request.ext.canSendRequest() {
            return nil
        }
        
        if request.baseUrl == nil {
            request.baseUrl = baseUrlsPool.currentUrl
        }
        
        if !request.ext.disableRequestInterceptor {
            requestInterceptor?(request)
        }
        
        request.ext.incrTryTimes()
        
        //encoder编码器编码
        if request.paramsConfig.style == .encoder {
            return AF.request(request.fullUrl,
                              method: HTTPMethod(rawValue: request.method.value),
                              parameters: request.encoderParams?.params,
                              encoder: paramsEncoder(request.paramsConfig.encoder),
                              headers: request.headers.isEmpty ? nil : HTTPHeaders(request.headers),
                              interceptor: nil,
                              requestModifier: {
                $0.timeoutInterval = request.timeout
                $0.httpShouldHandleCookies = request.shouldHandlefCookies
            })
        }
        
        //encoding编码
        return AF.request(request.fullUrl,
                          method: HTTPMethod(rawValue: request.method.value),
                          parameters: request.params.isEmpty ? nil : request.params,
                          encoding: paramsEncoding(request.paramsConfig.encoding),
                          headers: request.headers.isEmpty ? nil : HTTPHeaders(request.headers),
                          interceptor: nil,
                          requestModifier: {
                              $0.timeoutInterval = request.timeout
                              $0.httpShouldHandleCookies = request.shouldHandlefCookies
                          })
    }
    
    @discardableResult
    private func _uploadDataRequest(_ request: ATHttpRequest, fileUrl: URL, fileName: String, type: String, _ mimeType: String = "multipart/form-data") -> UploadRequest? {
        if !request.ext.canSendRequest() {
            return nil
        }
        
        if request.baseUrl == nil {
            request.baseUrl = baseUrlsPool.currentUrl
        }
        
        if !request.ext.disableRequestInterceptor {
            requestInterceptor?(request)
        }
        
        request.ext.incrTryTimes()
        
        return AF.upload(multipartFormData: { formData in
            
            formData.append(type.data(using: .utf8)!, withName: "type")
            formData.append(fileUrl, withName: "file", fileName: fileName, mimeType: mimeType)
            
        }, to: request.fullUrl, method: HTTPMethod(rawValue: request.method.value), headers: HTTPHeaders(request.headers)) {
            $0.timeoutInterval = request.uploadTimeout
            $0.httpShouldHandleCookies = request.shouldHandlefCookies
        }
    }

    private func _uploadDataRequest(_ request: ATHttpRequest, data: Data, fileName: String, type: String, mimeType: String = "multipart/form-data") -> UploadRequest? {
        if !request.ext.canSendRequest() {
            return nil
        }
        
        if request.baseUrl == nil {
            request.baseUrl = baseUrlsPool.currentUrl
        }
        
        if !request.ext.disableRequestInterceptor {
            requestInterceptor?(request)
        }
        
        request.ext.incrTryTimes()
        
        return AF.upload(multipartFormData: { formData in
            if type.count > 0 {
                formData.append(type.data(using: .utf8)!, withName: "type")
            }
            formData.append(data, withName: "file", fileName: fileName, mimeType: mimeType)
            
        }, to: request.fullUrl, method: HTTPMethod(rawValue: request.method.value), headers: HTTPHeaders(request.headers)) {
            $0.timeoutInterval = request.uploadTimeout
            $0.httpShouldHandleCookies = request.shouldHandlefCookies
        }
    }
    
    private func _downloadDataRequest(_ request: ATHttpRequest, cachePath: String? = nil) -> DownloadRequest? {
        if !request.ext.canSendRequest() {
            return nil
        }
        
        if request.baseUrl == nil {
            request.baseUrl = baseUrlsPool.currentUrl
        }
        
        if !request.ext.disableRequestInterceptor {
            requestInterceptor?(request)
        }
        
        request.ext.incrTryTimes()
        
        var destination: DownloadRequest.Destination?
        
        if let cachePath = cachePath {
            destination = { _, _ in
                (URL(fileURLWithPath: cachePath), [.createIntermediateDirectories, .removePreviousFile])
            }
        }
        
        return AF.download(request.fullUrl, method: HTTPMethod(rawValue: request.method.value), parameters: request.params, headers: HTTPHeaders(request.headers), requestModifier: {
            $0.timeoutInterval = request.downloadTimeout
            $0.httpShouldHandleCookies = request.shouldHandlefCookies
        }, to: destination)
    }
    
    @discardableResult
    private func _handleAF(_ request: ATHttpRequest, dataRequest: DataRequest?, rsRuccess: ((_ data: Data, _ dataDict: [String: Any]?) -> Void)?, rsFailure: ((_ error: Error?) -> Void)?) -> ATHttpTask {
        let task = ATHttpTask(dataRequest)
        dataRequest?.validate().responseData(completionHandler: { resp in
            
            _ = task
            
//            request.ext.requestHeaders = resp.request?.allHTTPHeaderFields as? [String: String]
            request.ext.requestHeaders = resp.request?.headers.dictionary as? [String: String]
//            request.ext.responseHeaders = resp.response?.allHeaderFields as? [String: String]
            request.ext.responseHeaders = resp.response?.headers.dictionary as? [String: String]
            request.ext.statusCode = resp.response?.statusCode ?? 0
            
            switch resp.result {
            case .success(let data):
                
                var dataDict = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
                
                if dataDict == nil {
                    // 处理因为不标准的unicode表情符号导致的JSON解析失败问题
                    if let jsonStr = String(data: data, encoding: .utf8) {
                        let mutableStr = NSMutableString(string: jsonStr) as CFMutableString
                        CFStringTransform(mutableStr, nil, "Any-Hex/Java" as CFString, true)
                        
                        let jsonStr2 = mutableStr as String
                        if let data2 = jsonStr2.data(using: .utf8) {
                            dataDict = try? JSONSerialization.jsonObject(with: data2, options: .allowFragments) as? [String: Any]
                        }
                    }
                }
                
                if !request.ext.disableResponseSuccessInterceptor {
                    if let interceptor = self.responseSuccessInterceptor {
                        // 响应成功拦截
                        let error = interceptor(request, dataDict)
                        
                        // ***********************************
                        // ************** 兼容　***************
                        // ***********************************
                        // 是否开启了不检查
                        let isUnCheck = request.ext.unCheckStatusSuccess != nil || request.ext.unCheckStatusJsonModelSuccess != nil
                        // 这里为了兼容旧的接口检查状态逻辑，做了一个特殊处理
                        if isUnCheck {
                            // 返回普通的数据
                            request.ext.unCheckStatusSuccess?(request, dataDict)
                            // 返回JSONModel的数据
                            if let _ = request.ext.unCheckStatusJsonModelSuccess {
//                                if let jsonModel = try? ATHttpJsonDictModel.init(dictionary: dataDict) {
//                                    request.ext.unCheckStatusJsonModelSuccess?(request, dataDict, jsonModel)
//                                } else {
//                                    request.ext.unCheckStatusJsonModelSuccess?(request, dataDict, nil)
//                                }
                                if let jsonModel:ATHttpJsonModel = (try? request.ext.jsonModelClass.init(dictionary: dataDict)) as? ATHttpJsonModel {
                                    request.ext.unCheckStatusJsonModelSuccess?(request, dataDict, jsonModel)
                                }else{
                                    request.ext.unCheckStatusJsonModelSuccess?(request, dataDict, nil)
                                }
                            }
                            return
                        }
                        
                        // 如果有异常，则跳转到失败回调
                        if error != nil {
//                            if let _ = request.logicError {
//                                // 判断是否有逻辑错误回调
//                                request.logicError?(request, dataDict, error)
//                            } else {
//                                // 如果没有逻辑错误回调，则直接认为是网络失败
//                                request.failure?(request, error)
//                            }
//                            rsFailure?(error)
                            
                            if let _logicError = request.logicError {
                                // 判断是否有逻辑错误回调
                                _logicError(request, dataDict, error)
                            } else if let _failure = request.failure {
                                // 如果没有逻辑错误回调，则直接认为是网络失败
                                _failure(request, error)
                            } else {
                                rsFailure?(error)
                            }
                            return
                        }
                    }
                }
                
                request.success?(request, dataDict)
                
                if let _ = request.ext.jsonModelSuccess {
                    if let jsonModel:ATHttpJsonModel = (try? request.ext.jsonModelClass.init(dictionary: dataDict)) as? ATHttpJsonModel {
                        request.ext.jsonModelSuccess?(request, dataDict, jsonModel)
                    }else{
                        request.ext.jsonModelSuccess?(request, dataDict, nil)
                    }
//                    if let jsonModel = try? ATHttpJsonDictModel.init(dictionary: dataDict) {
//                        request.ext.jsonModelSuccess?(request, dataDict, jsonModel)
//                    } else {
//                        request.ext.jsonModelSuccess?(request, dataDict, ATHttpJsonDictModel.init())
//                    }
                }
                rsRuccess?(data, dataDict)
                
            case .failure(let error):
                
                var _err = error as Error
                
                if request.ext.canSendRequest() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                        if !request.ext.disableRetryRequestInterceptor {
                            self.retryRequestInterceptor?(request)
                        }
                        let dataRequest = self._dataRequest(request)
                        self._handleAF(request, dataRequest: dataRequest, rsRuccess: rsRuccess, rsFailure: rsFailure)
                    }
                } else {
                    if !request.ext.disableResponseFailureInterceptor {
                        if let e = self.responseFailureInterceptor?(request, _err) {
                            _err = e
                        }
                    }
                    request.failure?(request, _err)
                    rsFailure?(_err)
                }
            }
            request.finish?(request)
        })
        return task
    }
}

public extension ATHttpClient {
    
    @discardableResult
    func sendRequest(_ request: ATHttpRequest) -> ATHttpTask {
        let dataRequest = _dataRequest(request)
        return _handleAF(request, dataRequest: dataRequest, rsRuccess: nil, rsFailure: nil)
    }
    
    @discardableResult
    func sendRequest(_ request: ATHttpRequest, rsRuccess: ((_ data: Data, _ dataDict: [String: Any]?) -> Void)?, rsFailure: ((_ error: Error?) -> Void)?) -> ATHttpTask {
        let dataRequest = _dataRequest(request)
        return _handleAF(request, dataRequest: dataRequest, rsRuccess: rsRuccess, rsFailure: rsFailure)
    }
    
    @discardableResult
    func sendRequest<T: Any, HandyJsonResponse: ATHttpHandyJsonResponse<T>>(_ request: ATHttpRequest, success: @escaping ((_ handyJsonResponse: HandyJsonResponse?) -> Void), failure: @escaping (_ error: Error?) -> Void) -> ATHttpTask {
        let dataRequest = _dataRequest(request)
        return _handleAF(request, dataRequest: dataRequest) { data, dataDict in
            success(HandyJsonResponse.deserialize(from: dataDict))
        } rsFailure: { error in
            failure(error)
        }
    }
}

public extension ATHttpClient {
    // upload data
    @discardableResult
    func upload(_ request: ATHttpRequest, data: Data, fileName: String, type: ATHttpFileType, uploadProgress: ((_ progress: Progress) -> Void)?, success: ((_ response: [String: Any]?) -> Void)?, failure: ((_ error: Error?) -> Void)?) -> ATHttpTask {
        let dataRequest = _uploadDataRequest(request, data: data, fileName: fileName, type: type.value)
        
        dataRequest?.uploadProgress(closure: { p in
            request.uploadProgress?(request, p)
            uploadProgress?(p)
        })
        
        return _handleAF(request, dataRequest: dataRequest) { _, dataDict in
            success?(dataDict)
        } rsFailure: { error in
            failure?(error)
        }
    }
    
    @discardableResult
    func upload(_ request: ATHttpRequest, data: Data, fileName: String, type: ATHttpFileType) -> ATHttpTask {
        return upload(request, data: data, fileName: fileName, type: type, uploadProgress: nil, success: nil, failure: nil)
    }
    
    @discardableResult
    func upload<T: Any, HandyJsonResponse: ATHttpHandyJsonResponse<T>>(_ request: ATHttpRequest, data: Data, fileName: String, type: ATHttpFileType, uploadProgress: ((_ progress: Progress) -> Void)?, success: @escaping ((_ jsonResponse: HandyJsonResponse?) -> Void), failure: @escaping (_ error: Error?) -> Void) -> ATHttpTask {
        return upload(request, data: data, fileName: fileName, type: type, uploadProgress: uploadProgress) { response in
            success(HandyJsonResponse.deserialize(from: response))
        } failure: { error in
            failure(error)
        }
    }
    
    // upload fileUrl
    @discardableResult
    func upload(_ request: ATHttpRequest, fileUrl: URL, fileName: String, type: ATHttpFileType, uploadProgress: ((_ progress: Progress) -> Void)?, success: ((_ response: [String: Any]?) -> Void)?, failure: ((_ error: Error?) -> Void)?) -> ATHttpTask {
        let dataRequest = _uploadDataRequest(request, fileUrl: fileUrl, fileName: fileName, type: type.value)
        
        dataRequest?.uploadProgress(closure: { p in
            request.uploadProgress?(request, p)
            uploadProgress?(p)
        })
        
        return _handleAF(request, dataRequest: dataRequest) { _, dataDict in
            success?(dataDict)
        } rsFailure: { error in
            failure?(error)
        }
    }
    
    @discardableResult
    func upload(_ request: ATHttpRequest, fileUrl: URL, fileName: String, type: ATHttpFileType) -> ATHttpTask {
        return upload(request, fileUrl: fileUrl, fileName: fileName, type: type, uploadProgress: nil, success: nil, failure: nil)
    }
    
    @discardableResult
    func upload<T: Any, HandyJsonResponse: ATHttpHandyJsonResponse<T>>(_ request: ATHttpRequest, fileUrl: URL, fileName: String, type: ATHttpFileType, uploadProgress: ((_ progress: Progress) -> Void)?, success: @escaping ((_ jsonResponse: HandyJsonResponse?) -> Void), failure: @escaping (_ error: Error?) -> Void) -> ATHttpTask {
        return upload(request, fileUrl: fileUrl, fileName: fileName, type: type, uploadProgress: uploadProgress) { response in
            success(HandyJsonResponse.deserialize(from: response))
        } failure: { error in
            failure(error)
        }
    }
}

public extension ATHttpClient {
    @discardableResult
    func download(_ request: ATHttpRequest, cachePath: String, downloadProgress: ((_ progress: Progress) -> Void)?, success: ((_ url: URL) -> Void)?, failure: ((_ error: Error?) -> Void)?) -> ATHttpTask {
        let downloadRequest = _downloadDataRequest(request, cachePath: cachePath)
        
        let task = ATHttpTask(downloadRequest)
        
        downloadRequest?.downloadProgress(closure: { p in
            request.downloadProgress?(request, p)
            downloadProgress?(p)
        })
        
        downloadRequest?.response(completionHandler: { response in
            _ = task
            switch response.result {
            case .success(let url):
                guard let url = url else {
                    failure?(nil)
                    return
                }
                success?(url)
            case .failure(let error):
                failure?(error)
            }
        })
        
        return task
    }
}
