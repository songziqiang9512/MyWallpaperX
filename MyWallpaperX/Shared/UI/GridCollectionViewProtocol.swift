//
//  GridCollectionViewProtocol.swift
//  MyWallpaperX
//
//  三模块网格 CollectionView 的标准交互接口。
//  各模块的 CollectionView 子类遵从此协议，Shell 层和容器视图通过协议交互，
//  不依赖具体模块的类型。
//

import AppKit

/// 标准网格 CollectionView 协议。
/// 定义卡片交互、框选、背景点击等所有模块共用的 handler 接口。
protocol GridCollectionViewProtocol: NSCollectionView, WallpaperGridIdentifiable {

    // MARK: - 背景与卡片交互

    /// 背景空白处左键点击（无卡片命中）
    var onBackgroundLeftClick: (() -> Void)? { get set }

    /// 右键菜单提供者，传入命中的 IndexPath（nil 表示点击空白处）
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)? { get set }

    /// 卡片区域内发生交互（用于通知外层视图区分卡片点击与背景点击）
    var cardInteractionHandler: (() -> Void)? { get set }

    // MARK: - 框选

    /// 是否启用框选（多选模式下开启）
    var isBoxSelectionEnabled: Bool { get set }

    /// 框选开始，传入起始 IndexPath（nil 表示从空白处开始），返回 true 表示接管事件
    var boxSelectionBeginHandler: ((IndexPath?) -> Bool)? { get set }

    /// 框选矩形更新
    var boxSelectionUpdateHandler: ((NSRect) -> Void)? { get set }

    /// 框选结束
    var boxSelectionEndHandler: (() -> Void)? { get set }

    // MARK: - 最后点击记录

    /// 最近一次主点击命中的 IndexPath（mouseUp 后清空）
    var lastPrimaryClickIndexPath: IndexPath? { get }
}
