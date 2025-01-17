import Foundation

actor TimeScheduler {
    private let queue = DispatchQueue(label: "com.schduler.timer")
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval
    
    init(initialInterval: TimeInterval) {
        self.interval = initialInterval
    }
    
    func start(sendAction: @escaping () async -> Void) {
        stop()
        timer = DispatchSource.makeTimerSource(queue: queue)
        guard let timer = timer else { return }
        
        timer.schedule(deadline: .now() + interval, repeating: .infinity) //trigger only once here
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            Task {
                await sendAction()
                await self.refreshSchduler()
            }
        }
        timer.resume()
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
    }
    
    func updateInterval(to newInterval: TimeInterval) {
        interval = newInterval
        refreshSchduler()
    }
    
    func refreshSchduler() {
        guard let timer = timer else { return }
        timer.schedule(deadline: .now() + interval, repeating: .infinity)
    }
}