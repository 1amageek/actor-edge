import Foundation
import Distributed

/// ActorEdgeシステムにおける分散アクターの識別子
/// 
/// 主に固定文字列ID（例："chat-server"）での使用を想定しています。
/// DistributedActorSystemの要件に準拠し、Hashable、Sendable、Codableを実装。
public struct ActorEdgeID: Sendable, Hashable, Codable {
    /// アクターの識別子
    private let value: String
    
    /// 固定IDでアクターIDを作成（推奨）
    /// - Parameter value: アクターの識別文字列
    /// - Example: ActorEdgeID("chat-server")
    public init(_ value: String) {
        self.value = value
    }
    
    /// ランダムなアクターIDを生成
    /// - Note: 主にActorSystemのassignID要件やテスト用
    public init() {
        // UUIDの短縮版（8文字）で十分な一意性を確保
        self.value = UUID().uuidString.prefix(8).lowercased()
    }
    
    /// ID値へのアクセス（デバッグ用）
    public var description: String {
        value
    }
}

// MARK: - CustomStringConvertible
extension ActorEdgeID: CustomStringConvertible {}

// MARK: - ExpressibleByStringLiteral
extension ActorEdgeID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}