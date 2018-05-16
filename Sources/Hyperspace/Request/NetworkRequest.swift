//
//  NetworkRequest.swift
//  Hyperspace
//
//  Created by Tyler Milner on 6/26/17.
//  Copyright © 2017 Bottle Rocket Studios. All rights reserved.
//

//
//  TODO: Future functionality:
//          - Extend to allow for easy handling of multipart form data upload.
//          - Add support for providing a root key to parse the response from (for the NetworkRequest extension dealing with a 'ResponseType' that's 'Decodable').
//

import Foundation
import Result

/// Represents an error which can be constructed from a `NetworkServiceFailure`.
public protocol NetworkServiceFailureInitializable: Swift.Error {
    init(networkServiceFailure: NetworkServiceFailure)
}

/// Represents an error which can be constructed from a `DecodingError` and `Data`.
public protocol DecodingFailureInitializable: Swift.Error {
    init(decodingError: DecodingError, data: Data)
}

/// Encapsulates all the necessary parameters to represent a request that can be sent over the network.
public protocol NetworkRequest {
    
    /// The model type that this NetworkRequest will attempt to transform Data into.
    associatedtype ResponseType
    associatedtype ErrorType: NetworkServiceFailureInitializable
    
    /// The HTTP method to be use when executing this request.
    var method: HTTP.Method { get }
    
    /// The URL to use when executing this network request.
    var url: URL { get }
    
    /// The header field keys/values to use when executing this network request.
    var headers: [HTTP.HeaderKey: HTTP.HeaderValue]? { get set }
    
    /// The payload body for this network request, if any.
    var body: Data? { get set }
    
    /// The cache policy to use when executing this network request.
    var cachePolicy: URLRequest.CachePolicy { get }
    
    /// The timeout to use when executing this network request.
    var timeout: TimeInterval { get }
    
    /// The URLRequest that represents this network request.
    var urlRequest: URLRequest { get }
        
    /// Attempts to parse the provided Data into the associated response model type for this request.
    ///
    /// - Parameter data: The raw Data retrieved from the network.
    /// - Returns: A result indicating the successful or failed transformation of the data into the associated response type.
    func transformData(_ data: Data) -> Result<ResponseType, ErrorType>
}

/// A simple struct representing an empty server response to a request.
/// This is useful primarily for DELETE requests, in which case a "200" status with empty body is often the response.
public struct EmptyResponse {
    
    // NOTE: It would be ideal if the implicitly-generated memberwise initializer could automatically be available publicly instead of defining this manually.
    //       It may be possible someday - https://github.com/apple/swift-evolution/blob/master/proposals/0018-flexible-memberwise-initialization.md
    public init() { }
}

// MARK: - NetworkRequest Defaults

public struct NetworkRequestDefaults {
    
    public static var defaultCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    
    public static var defaultTimeout: TimeInterval = 30
    
    public static func dataTransformer<T: Decodable, E: DecodingFailureInitializable>(for decoder: JSONDecoder) -> (Data) -> Result<T, E> {
        return { data in
            do {
                let decodedResponse: T = try decoder.decode(T.self, from: data)
                return .success(decodedResponse)
            } catch {
                guard let decodingError = error as? DecodingError else { fatalError("JSONDecoder should always throw a DecodingError.") }
                return .failure(E(decodingError: decodingError, data: data))
            }
        }
    }
}

// MARK: - NetworkRequest Default Implementations

public extension NetworkRequest {
    
    var cachePolicy: URLRequest.CachePolicy {
        return NetworkRequestDefaults.defaultCachePolicy
    }
    
    var timeout: TimeInterval {
        return NetworkRequestDefaults.defaultTimeout
    }
        
    var urlRequest: URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body
        
        // Transform the headers from [HTTP.HeaderKey: HTTP.HeaderValue] to [String: String]
        let rawHeaders: [String: String] = Dictionary(uniqueKeysWithValues: (headers ?? [:]).map { ($0.rawValue, $1.rawValue) })
        request.allHTTPHeaderFields = rawHeaders
        
        return request
    }
    
    /// Adds the specified headers to the HTTP headers already attached to the `NetworkRequest`.
    ///
    /// - Parameter additionalHeaders: The HTTP headers to add to the request
    /// - Returns: A new `NetworkReqest` with the combined HTTP headers. In the case of a collision, the value from `additionalHeaders` is preferred.
    func addingHeaders(_ additionalHeaders: [HTTP.HeaderKey: HTTP.HeaderValue]) -> Self {
        let modifiedHeaders = (headers ?? [:])?.merging(additionalHeaders) { return $1 }
        return usingHeaders(modifiedHeaders)
    }
    
    /// Modifies the HTTP headers on the `NetworkRequest`.
    ///
    /// - Parameter headers: The HTTP headers to add to the request.
    /// - Returns: A new `NetworkReqest` with the given HTTP headers.
    func usingHeaders(_ headers: [HTTP.HeaderKey: HTTP.HeaderValue]?) -> Self {
        var copy = self
        copy.headers = headers
        return copy
    }
    
    /// Modifies the HTTP body on the `NetworkRequest`.
    ///
    /// - Parameter body: The HTTP body to add to the request.
    /// - Returns: A new `NetworkReqest` with the given HTTP body
    func usingBody(_ body: Data?) -> Self {
        var copy = self
        copy.body = body
        return copy
    }
}

public extension NetworkRequest where ResponseType: Decodable, ErrorType: DecodingFailureInitializable {
    
    func dataTransformer(with decoder: JSONDecoder) -> (Data) -> Result<ResponseType, ErrorType> {
        return NetworkRequestDefaults.dataTransformer(for: decoder)
    }
    
    func transformData(_ data: Data) -> Result<ResponseType, ErrorType> {
        return dataTransformer(with: JSONDecoder())(data)
    }
}

public extension NetworkRequest where ResponseType == EmptyResponse {
    func transformData(_ data: Data) -> Result<EmptyResponse, ErrorType> {
        return .success(EmptyResponse())
    }
}

// MARK: - AnyError Conformance to NetworkServiceInitializable

extension AnyError: NetworkServiceFailureInitializable {
    public init(networkServiceFailure: NetworkServiceFailure) {
        self.init(networkServiceFailure.error)
    }
}

// MARK: - AnyError Conformance to DecodingFailureInitializable

extension AnyError: DecodingFailureInitializable {
    public init(decodingError: DecodingError, data: Data) {
        self.init(decodingError)
    }
}
