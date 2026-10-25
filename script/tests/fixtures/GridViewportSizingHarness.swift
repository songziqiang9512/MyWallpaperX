import AppKit
@MainActor class Probe: NSView {
 let scrollView = NSScrollView(); let collectionView = NSCollectionView(); let flowLayout = NSCollectionViewFlowLayout()
 var preferredColumns = 5 { didSet { needsLayout = true } }
 var lastReportedClipWidth: CGFloat?
 var onClipWidthChange: ((CGFloat) -> Void)?
 var currentColumnCount=0;var lastComputedColumns=0
 var isLayoutItemSizeUpdateScheduled=false;var pendingLayoutInvalidation=false
 var dataSource: NSCollectionViewDiffableDataSource<Int, Int>!
 var expectedColumns: Int { WallpaperLibraryGridMetrics(clipWidth: scrollView.contentView.bounds.width, preferredColumns: preferredColumns).columns }
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
 let probes:[Probe]=[P2()]
 for (i,p) in probes.enumerated(){
  p.preferredColumns=5;window.setContentSize(NSSize(width:1000,height:680));window.contentView=p;window.orderFront(nil)
  var widthReports: [CGFloat] = []
  p.onClipWidthChange = { widthReports.append($0) }
  p.install(Array(1...150));settle(window)
  let first=(0..<10).compactMap{p.flowLayout.layoutAttributesForItem(at:IndexPath(item:$0,section:0))?.frame}
  let row=first.filter{abs($0.minY-(first.first?.minY ?? 0))<1}.count
  precondition(row == p.expectedColumns, "module \(i): row \(row) != declared \(p.expectedColumns)")
  precondition(row == 5, "default preference must remain five columns")
  precondition(widthReports.last == p.scrollView.contentView.bounds.width)
  let reportsBeforeSameLayout = widthReports.count
  p.needsLayout=true;settle(window)
  precondition(widthReports.count == reportsBeforeSameLayout, "same width must not republish layout")
  window.setContentSize(NSSize(width:2800,height:680));p.preferredColumns = 3;settle(window)
  p.install(Array(2...150));window.setContentSize(NSSize(width:620,height:680));settle(window)
  for style: NSScroller.Style in [.legacy, .overlay] {
   p.scrollView.scrollerStyle=style
   for width: CGFloat in [620,1000,2800,1000] {
    for requested in 3...6 {
     p.preferredColumns=requested;p.needsLayout=true;window.setContentSize(NSSize(width:width,height:680));settle(window)
     let clipWidth = p.scrollView.contentView.bounds.width
     precondition(widthReports.last == clipWidth)
     precondition(p.preferredColumns == requested, "resize must not overwrite the requested density")
     let count = p.expectedColumns
     let availability = WallpaperLibraryGridMetrics.zoomAvailability(preferredColumns: requested, clipWidth: clipWidth)
     for delta in [-1,1] {
      if delta < 0 ? availability.canZoomOut : availability.canZoomIn {
       let next = WallpaperLibraryGridMetrics.zoomedColumns(preferredColumns: requested, delta: delta, clipWidth: clipWidth)
       precondition(WallpaperLibraryGridMetrics(clipWidth: clipWidth, preferredColumns: next).columns == count - delta)
      }
     }
     let attrs=(0..<8).compactMap{p.flowLayout.layoutAttributesForItem(at:IndexPath(item:$0,section:0))?.frame}
     let columns=attrs.filter{abs($0.minY-(attrs.first?.minY ?? 0))<1}.count
     precondition(columns == p.expectedColumns, "module \(i) width \(width) requested \(requested): wrong column count actual=\(columns) expected=\(p.expectedColumns) item=\(p.flowLayout.itemSize) viewport=\(p.scrollView.contentView.bounds) bounds=\(p.bounds)")
     precondition(p.flowLayout.itemSize.height == p.flowLayout.itemSize.width)
     precondition(p.flowLayout.minimumLineSpacing == 10 && p.flowLayout.minimumInteritemSpacing == 8)
     for frame in attrs { precondition(frame.maxX <= p.scrollView.contentView.bounds.width, "card outside viewport") }
    }
   }
  }
  print("module",i,"legacy/overlay resize and zoom PASS")
 }
 print("Live online browser sizing owner PASS")
 window.close()
 }
 @MainActor static func settle(_ w:NSWindow){for _ in 0..<15{RunLoop.main.run(until:Date().addingTimeInterval(0.004));w.contentView?.layoutSubtreeIfNeeded()}}
}
