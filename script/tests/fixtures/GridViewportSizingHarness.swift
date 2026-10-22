import AppKit
@MainActor final class Zoom { static let shared = Zoom(); var zoomOffset = 0; var gridZoomOffset: Int { zoomOffset } }
typealias OnlineLibraryService = Zoom
@MainActor class Probe: NSView {
 let scrollView = NSScrollView(); let collectionView = NSCollectionView(); let flowLayout = NSCollectionViewFlowLayout()
 let service = Zoom.shared; let wallpaperManager = Zoom.shared
 var currentColumnCount=0;var lastComputedColumns=0
 var isLayoutItemSizeUpdateScheduled=false;var pendingLayoutInvalidation=false
 var dataSource: NSCollectionViewDiffableDataSource<Int, Int>!
 var expectedColumns: Int { GridLayoutHelper.columnCount(for: scrollView.contentView.bounds.width-16,zoomOffset: service.zoomOffset, minimumItemWidth: 100) }
 override init(frame:NSRect) {
  super.init(frame:frame)
  scrollView.hasVerticalScroller=true;scrollView.scrollerStyle = .legacy;scrollView.autohidesScrollers=false
  scrollView.translatesAutoresizingMaskIntoConstraints=false
  collectionView.translatesAutoresizingMaskIntoConstraints=false;collectionView.collectionViewLayout=flowLayout
  flowLayout.sectionInset=NSEdgeInsets(top:8,left:8,bottom:8,right:8)
  scrollView.documentView=collectionView;addSubview(scrollView)
  NSLayoutConstraint.activate([scrollView.leadingAnchor.constraint(equalTo:leadingAnchor),scrollView.trailingAnchor.constraint(equalTo:trailingAnchor),scrollView.topAnchor.constraint(equalTo:topAnchor),scrollView.bottomAnchor.constraint(equalTo:bottomAnchor)])
  collectionView.register(NSCollectionViewItem.self,forItemWithIdentifier:NSUserInterfaceItemIdentifier("cell"))
  dataSource=NSCollectionViewDiffableDataSource<Int,Int>(collectionView:collectionView){cv,path,id in cv.makeItem(withIdentifier:NSUserInterfaceItemIdentifier("cell"),for:path)}
 }
 required init?(coder:NSCoder){nil}
 func updateVisibleThumbnailPriorities() {}
 func scheduleThumbnailDemand() {}
 func scheduleViewportPrefetch() {}
 func schedulePreviewPrefetch() {}
 func prioritizeVisibleItemsForHydration() {}
 func scheduleVisibleGridColumnCountUpdateIfNeeded(_ count:Int){currentColumnCount=count}
 func install(_ ids:[Int]) {var s=NSDiffableDataSourceSnapshot<Int,Int>();s.appendSections([0]);s.appendItems(ids);dataSource.apply(s,animatingDifferences:true)}
}

// PRODUCTION_SIZING_CLASSES
@main struct Main {
 @MainActor static func main(){
 _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
 let window=NSWindow(contentRect:NSRect(x:14000,y:14000,width:1000,height:680),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
 window.isReleasedWhenClosed=false
 let probes:[Probe]=[P0(),P1(),P2(),P3()]
 for (i,p) in probes.enumerated(){
  serviceReset();window.setContentSize(NSSize(width:1000,height:680));window.contentView=p;window.orderFront(nil)
  p.install(Array(1...150));settle(window)
  let first=(0..<10).compactMap{p.flowLayout.layoutAttributesForItem(at:IndexPath(item:$0,section:0))?.frame}
  let row=first.filter{abs($0.minY-(first.first?.minY ?? 0))<1}.count
  precondition(row == p.expectedColumns, "module \(i): row \(row) != declared \(p.expectedColumns)")
  window.setContentSize(NSSize(width:2800,height:680));p.service.zoomOffset = -3;settle(window)
  p.install(Array(2...150));window.setContentSize(NSSize(width:620,height:680));settle(window)
  for style: NSScroller.Style in [.legacy, .overlay] {
   p.scrollView.scrollerStyle=style
   for width: CGFloat in [620,1000,2800,1000] {
    for zoom in [-3,0,2] {
     p.service.zoomOffset=zoom;p.needsLayout=true;window.setContentSize(NSSize(width:width,height:680));settle(window)
     let availableWidth = p.scrollView.contentView.bounds.width - 16
     precondition(GridLayoutHelper.availableWidth(in: window.contentView) == availableWidth)
     let count = p.expectedColumns
     let availability = GridLayoutHelper.zoomAvailability(currentOffset: zoom, for: availableWidth, minimumItemWidth: 100)
     for delta in [-1,1] {
      if delta < 0 ? availability.canZoomOut : availability.canZoomIn {
       let next = GridLayoutHelper.zoomedOffset(currentOffset: zoom, delta: delta, for: availableWidth, minimumItemWidth: 100)
       precondition(GridLayoutHelper.columnCount(for: availableWidth, zoomOffset: next, minimumItemWidth: 100) == count + delta)
      }
     }
     let attrs=(0..<8).compactMap{p.flowLayout.layoutAttributesForItem(at:IndexPath(item:$0,section:0))?.frame}
     let columns=attrs.filter{abs($0.minY-(attrs.first?.minY ?? 0))<1}.count
     precondition(columns == p.expectedColumns, "module \(i) width \(width) zoom \(zoom): wrong column count actual=\(columns) expected=\(p.expectedColumns) item=\(p.flowLayout.itemSize) viewport=\(p.scrollView.contentView.bounds) bounds=\(p.bounds)")
     for frame in attrs { precondition(frame.maxX <= p.scrollView.contentView.bounds.width, "card outside viewport") }
    }
   }
  }
  print("module",i,"legacy/overlay resize and zoom PASS")
 }
 print("All four production sizing owners PASS")
 window.close()
 }
 @MainActor static func serviceReset(){Zoom.shared.zoomOffset=0}
 @MainActor static func settle(_ w:NSWindow){for _ in 0..<15{RunLoop.main.run(until:Date().addingTimeInterval(0.004));w.contentView?.layoutSubtreeIfNeeded()}}
}
