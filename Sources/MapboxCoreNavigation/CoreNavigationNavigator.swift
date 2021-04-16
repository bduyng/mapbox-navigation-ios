import MapboxNavigationNative
import MapboxDirections

class Navigator {
    
    /**
     Tiles version string. If not specified explicitly - will be automatically resolved
     to the latest version.
     
     This property can only be modified before creating `Navigator` shared instance, all
     further changes to this property will have no effect.
     */
    static var tilesVersion: String = ""
    
    /**
     A local path to the tiles storage location. If not specified - will be automatically defaulted
     to the cache subdirectory.
     
     This property can only be modified before creating `Navigator` shared instance, all
     further changes to this property will have no effect.
     */
    static var tilesURL: URL? = nil
    
    func enableHistoryRecorder() {
        historyRecorder.enable(forEnabled: true)
    }
    
    func disableHistoryRecorder() {
        historyRecorder.enable(forEnabled: false)
    }
    
    func history() -> Data {
        return historyRecorder.getHistory()
    }
    
    var historyRecorder: HistoryRecorderHandle!
    
    var navigator: MapboxNavigationNative.Navigator!
    
    var cacheHandle: CacheHandle!
    
    var roadGraph: RoadGraph!
    
    lazy var roadObjectsStore: RoadObjectsStore = {
        return RoadObjectsStore(navigator.roadObjectStore())
    }()
    
    /**
     The Authorization & Authentication credentials that are used for this service. If not specified - will be automatically intialized from the token and host from your app's `info.plist`.
     
     - precondition: `credentials` should be set before getting the shared navigator for the first time.
     */
    static var credentials: DirectionsCredentials? = nil
    
    /**
     Provides a new or an existing `MapboxCoreNavigation.Navigator` instance. Upon first initialization will trigger creation of `MapboxNavigationNative.Navigator` and `HistoryRecorderHandle` instances,
     satisfying provided configuration (`tilesVersion` and `tilesURL`).
     */
    static let shared: Navigator = Navigator()
    
    /**
     Restrict direct initializer access.
     */
    private init() {
        var tilesPath: String! = Self.tilesURL?.path
        if tilesPath == nil {
            let bundle = Bundle.mapboxCoreNavigation
            if bundle.ensureSuggestedTileURLExists() {
                tilesPath = bundle.suggestedTileURL!.path
            } else {
                preconditionFailure("Failed to access cache storage.")
            }
        }
        
        let settingsProfile = SettingsProfile(application: ProfileApplication.kMobile,
                                              platform: ProfilePlatform.KIOS)
        
        let endpointConfig = TileEndpointConfiguration(credentials:Navigator.credentials ?? Directions.shared.credentials,
                                                       tilesVersion: Self.tilesVersion,
                                                       minimumDaysToPersistVersion: nil)
        
        let tilesConfig = TilesConfig(tilesPath: tilesPath,
                                      inMemoryTileCache: nil,
                                      onDiskTileCache: nil,
                                      mapMatchingSpatialCache: nil,
                                      threadsCount: nil,
                                      endpointConfig: endpointConfig)
        
        let configFactory = ConfigFactory.build(for: settingsProfile,
                                                     config: NavigatorConfig(),
                                                     customConfig: "")
        
        historyRecorder = HistoryRecorderHandle.build(forHistoryFile: "", config: configFactory)
        
        let runloopExecutor = RunLoopExecutorFactory.build()
        cacheHandle = CacheFactory.build(for: tilesConfig,
                                              config: configFactory,
                                              runLoop: runloopExecutor,
                                              historyRecorder: historyRecorder)
        
        roadGraph = RoadGraph(MapboxNavigationNative.GraphAccessor(cache: cacheHandle))
        
        navigator = MapboxNavigationNative.Navigator(config: configFactory,
                                                          runLoopExecutor: runloopExecutor,
                                                          cache: cacheHandle,
                                                          historyRecorder: historyRecorder)
        navigator.setElectronicHorizonObserverFor(self)
    }
    
    deinit {
        navigator.setElectronicHorizonObserverFor(nil)
    }
    
    var electronicHorizonOptions: ElectronicHorizonOptions? {
        didSet {
            let nativeOptions: MapboxNavigationNative.ElectronicHorizonOptions?
            if let electronicHorizonOptions = electronicHorizonOptions {
                nativeOptions = MapboxNavigationNative.ElectronicHorizonOptions(electronicHorizonOptions)
            } else {
                nativeOptions = nil
            }
            navigator.setElectronicHorizonOptionsFor(nativeOptions)
        }
    }
}

extension Navigator: ElectronicHorizonObserver {
    public func onPositionUpdated(for position: ElectronicHorizonPosition, distances: [String : MapboxNavigationNative.RoadObjectDistanceInfo]) {
        let userInfo: [ElectronicHorizon.NotificationUserInfoKey: Any] = [
            .positionKey: RoadGraph.Position(position.position()),
            .treeKey: ElectronicHorizon(position.tree()),
            .updatesMostProbablePathKey: position.type() == .UPDATE,
            .distancesByRoadObjectKey: distances.mapValues(RoadObjectDistanceInfo.init),
        ]
        NotificationCenter.default.post(name: .electronicHorizonDidUpdatePosition, object: nil, userInfo: userInfo)
    }
    
    public func onRoadObjectEnter(for info: RoadObjectEnterExitInfo) {
        let userInfo: [ElectronicHorizon.NotificationUserInfoKey: Any] = [
            .roadObjectIdentifierKey: info.roadObjectId,
            .didTransitionAtEndpointKey: info.isEnterFromStartOrExitFromEnd,
        ]
        NotificationCenter.default.post(name: .electronicHorizonDidEnterRoadObject, object: nil, userInfo: userInfo)
    }
    
    public func onRoadObjectExit(for info: RoadObjectEnterExitInfo) {
        let userInfo: [ElectronicHorizon.NotificationUserInfoKey: Any] = [
            .roadObjectIdentifierKey: info.roadObjectId,
            .didTransitionAtEndpointKey: info.isEnterFromStartOrExitFromEnd,
        ]
        NotificationCenter.default.post(name: .electronicHorizonDidExitRoadObject, object: nil, userInfo: userInfo)
    }
}